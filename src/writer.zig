const std = @import("std");

const parser = @import("parser.zig");
const util = @import("util/root.zig");

const writer_logger = std.log.scoped(.writer);

const StrArrayList = std.ArrayList([]const u8);

pub const FileTypes = enum {
    anm,
    bar,
    cfg,
    class,
    envfx,
    fff,
    ffx,
    fx,
    hnt,
    hud,
    lua,
    lvl,
    lyr,
    msh,
    mus,
    odf,
    option,
    pic,
    pln,
    prp,
    pth,
    req,
    rgn,
    sfx,
    snd,
    stm,
    ter,
    tga,
    wld,
    xml,
    zafbin,
    __unknown__,
};

const Sections = enum {
    animbank,
    bnk,
    class,
    config,
    congraph,
    envfx,
    font,
    loc,
    lvl,
    model,
    path,
    prop,
    script,
    shader,
    str,
    texture,
    world,
};

const ReqDatabase = struct {
    allocator: std.mem.Allocator,
    parse_odfs: bool = false,
    sections: std.StringHashMap(StrArrayList),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, options: anytype) Self {
        return Self{
            .allocator = allocator,
            .parse_odfs = options.parse_odfs,
            .sections = std.StringHashMap(StrArrayList).init(allocator),
        };
    }

    pub fn addEntry(self: *Self, entry: []const u8) !void {
        const extension = try util.path.extension(self.allocator, entry);
        const file_type = std.meta.stringToEnum(FileTypes, extension) orelse .__unknown__;

        const section_type: Sections = switch (file_type) {
            .anm, .bar, .hnt, .lyr, .rgn, .ter, .wld => .world,
            .cfg => .loc,
            .class, .lvl, .req => .lvl,
            .envfx => .envfx,
            .fff => .font,
            .ffx, .fx, .hud, .mus, .snd => .config,
            .lua => .script,
            .msh => .model,
            .odf => o: {
                // Default: don't parse odfs
                if (!self.parse_odfs) break :o .class;

                // Otherwise, parse each odf for dependencies and add them
                var odf_parser = parser.OdfParser.init(self.allocator);
                const dependencies = try odf_parser.parse(entry);
                var iter = dependencies.keyIterator();
                while (iter.next()) |dep_section_name| {
                    for (dependencies.get(dep_section_name.*).?.items) |item| {
                        try self.addEntryImpl(dep_section_name.*, item);
                    }
                }
                break :o .class;
            },
            .option => {
                // Ignore .option files... if there are other types we should be ignoring, add them here
                return;
            },
            .pic, .tga => .texture,
            .pln => .congraph,
            .prp => .prop,
            .pth => .path,
            .sfx => .bnk,
            .stm => .str,
            .xml => .shader,
            .zafbin => .animbank,
            else => .config, // Default to config since it seems to contain most non-world-specific types
        };
        const section_name: []const u8 = @tagName(section_type);
        writer_logger.debug("Adding entry to section \"{s}\": {s}", .{ section_name, entry });
        try self.addEntryImpl(section_name, entry);
    }

    fn addEntryImpl(self: *Self, section_name: []const u8, entry: []const u8) !void {
        const entry_name = try util.path.stem(entry, self.allocator);
        if (entry_name.len == 0) return;
        if (self.sections.getPtr(section_name)) |section| {
            // TODO this is O(n) for performance, eventually I'd like to just store a HashMap of string:null
            for (section.*.items) |existing_item| {
                if (std.mem.eql(u8, existing_item, entry_name)) return;
            }
            try section.*.append(entry_name);
        } else {
            var section = StrArrayList.init(self.allocator);
            try section.append(entry_name);
            try self.sections.put(section_name, section);
        }
    }

    fn quote(self: *Self, string: []const u8) ![]const u8 {
        return try util.string.quoteString(string, self.allocator);
    }

    pub fn write(self: *Self, writer: anytype) !void {
        writer_logger.debug("Beginning req database write...", .{});
        try writer.writeAll("ucft\n{\n");
        var iter = self.sections.keyIterator();
        var sections = StrArrayList.init(self.allocator);
        defer sections.deinit();
        while (iter.next()) |section_name| {
            try sections.append(section_name.*);
        }
        std.sort.insertion([]const u8, sections.items, {}, struct {
            fn lt(_: void, l: []const u8, r: []const u8) bool {
                return std.ascii.lessThanIgnoreCase(l, r);
            }
        }.lt);
        for (sections.items) |section_name| {
            try writer.writeAll("\tREQN\n\t{\n");
            try std.fmt.format(writer, "\t\t{!s}\n", .{self.quote(section_name)});
            std.sort.pdq([]const u8, self.sections.get(section_name).?.items, {}, struct {
                fn lt(_: void, l: []const u8, r: []const u8) bool {
                    return std.ascii.lessThanIgnoreCase(l, r);
                }
            }.lt);
            for (self.sections.get(section_name).?.items) |item| {
                try std.fmt.format(writer, "\t\t{!s}\n", .{self.quote(item)});
            }
            try writer.writeAll("\t}\n");
        }
        try writer.writeAll("}\n");
        writer_logger.debug("Completed req database write", .{});
    }
};

pub fn generateReqFile(
    allocator: std.mem.Allocator,
    options: anytype,
    files: StrArrayList,
    output_file_name: []const u8,
) !void {
    var db = ReqDatabase.init(allocator, options);

    for (files.items) |file_path| {
        try db.addEntry(file_path);
    }

    const full_output_file_name = if (!std.mem.endsWith(u8, output_file_name, ".req")) fofn: {
        break :fofn try std.mem.concat(allocator, u8, &[_][]const u8{ output_file_name, ".req" });
    } else fofn: {
        break :fofn output_file_name;
    };
    const output_file = std.fs.cwd().createFile(full_output_file_name, .{}) catch |err| {
        writer_logger.err("{!s}: Unable to create file {s}\n", .{ @errorName(err), output_file_name });
        std.process.exit(1);
    };
    const file_writer = output_file.writer();
    writer_logger.info("Writing output to {s}", .{full_output_file_name});
    try db.write(file_writer);
}
