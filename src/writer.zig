const std = @import("std");
const util = @import("util/root.zig");

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
    sections: std.StringHashMap(StrArrayList),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .sections = std.StringHashMap(StrArrayList).init(allocator),
        };
    }

    pub fn addEntry(self: *Self, entry: []const u8) !void {
        const rawExtension = std.fs.path.extension(entry);
        const untrimmedExtension = try std.ascii.allocLowerString(self.allocator, rawExtension);
        const extension = std.mem.trimLeft(u8, untrimmedExtension, ".");
        const fileType = std.meta.stringToEnum(FileTypes, extension) orelse .__unknown__;

        const sectionType: Sections = switch (fileType) {
            .anm, .bar, .hnt, .lyr, .rgn, .ter, .wld => .world,
            .cfg => .loc,
            .class, .lvl, .req => .lvl,
            .envfx => .envfx,
            .fff => .font,
            .ffx, .fx, .hud, .mus, .snd => .config,
            .lua => .script,
            .msh => .model,
            .odf => .class,
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
        const sectionName: []const u8 = @tagName(sectionType);

        const pathStem = try util.path.stem(entry, self.allocator);
        if (self.sections.getPtr(sectionName)) |section| {
            try section.*.append(pathStem);
        } else {
            var section = StrArrayList.init(self.allocator);
            try section.append(pathStem);
            try self.sections.put(sectionName, section);
        }
    }

    fn quote(self: *Self, string: []const u8) ![]const u8 {
        return try util.string.quoteString(string, self.allocator);
    }

    pub fn write(self: *Self, writer: anytype) !void {
        try writer.writeAll("ucft\n{\n");
        var iter = self.sections.keyIterator();
        while (iter.next()) |sectionName| {
            try writer.writeAll("\tREQN\n\t{\n");
            try std.fmt.format(writer, "\t\t{!s}\n", .{self.quote(sectionName.*)});
            for (self.sections.get(sectionName.*).?.items) |item| {
                try std.fmt.format(writer, "\t\t{!s}\n", .{self.quote(item)});
            }
            try writer.writeAll("\t}\n");
        }
        try writer.writeAll("}\n");
    }
};
