const std = @import("std");

const parser = @import("parser.zig");
const util = @import("util/root.zig");

const writer_logger = std.log.scoped(.writer);

const StrArrayList = std.ArrayList([]const u8);

const FileTypes = enum {
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

pub const ReqDatabase = struct {
    allocator: std.mem.Allocator,
    parse_odfs: ?bool = false,
    sections: std.StringHashMap(StrArrayList),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, options: anytype) Self {
        return Self{
            .allocator = allocator,
            .parse_odfs = options.args.@"parse-odfs",
            .sections = std.StringHashMap(StrArrayList).init(allocator),
        };
    }

    pub fn addEntry(self: *Self, entry: []const u8) !void {
        const raw_extension = std.fs.path.extension(entry);
        const lower_extension = try std.ascii.allocLowerString(self.allocator, raw_extension);
        const extension = std.mem.trimLeft(u8, lower_extension, ".");
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
                if (!self.parse_odfs.?) break :o .class;

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
        while (iter.next()) |section_name| {
            try writer.writeAll("\tREQN\n\t{\n");
            try std.fmt.format(writer, "\t\t{!s}\n", .{self.quote(section_name.*)});
            for (self.sections.get(section_name.*).?.items) |item| {
                try std.fmt.format(writer, "\t\t{!s}\n", .{self.quote(item)});
            }
            try writer.writeAll("\t}\n");
        }
        try writer.writeAll("}\n");
        writer_logger.debug("Completed req database write", .{});
    }
};
