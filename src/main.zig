const std = @import("std");
const simargs = @import("simargs");

const print = std.debug.print;

fn str(comptime N: usize) type {
    return *const [N:0]u8;
}

const Args = struct {};

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

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var opt = try simargs.parse(allocator, Args, "[file]", null);
    defer opt.deinit();

    var numDirectories: u32 = 0;
    var directories = std.ArrayList([]const u8).init(allocator);
    defer directories.deinit();

    var numFiles: u32 = 0;
    var files = std.ArrayList([]const u8).init(allocator);
    defer files.deinit();

    for (opt.positional_args.items, 0..) |arg, idx| {
        const parent = std.fs.path.dirname(arg);
        if (parent) |p| {
            const dir = try std.fs.openDirAbsolute(p, .{});
            const stat = try dir.statFile(arg);
            switch (stat.kind) {
                .directory => {
                    print("{s} was a directory\n", .{arg});
                    try directories.append(arg);
                    numDirectories += 1;
                },
                .file => {
                    print("{s} was a file\n", .{arg});
                    try files.append(arg);
                    numFiles += 1;
                },
                else => {
                    print("{s} in position {d} was somehow neither a dir or file, skipping...\n", .{ arg, idx });
                },
            }
        }
    }

    print("There are {d} files and {d} directories given.\n", .{ files.items.len, directories.items.len });

    var map = std.StringHashMap(std.ArrayList([]const u8)).init(allocator);
    defer map.deinit();

    for (files.items) |filePath| {
        const rawExtension = std.fs.path.extension(filePath);
        const extension = try std.ascii.allocLowerString(allocator, rawExtension);
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

        if (map.getPtr(sectionName)) |section| {
            try section.*.append(std.fs.path.basename(filePath));
        } else {
            var section = std.ArrayList([]const u8).init(allocator);
            try section.append(std.fs.path.basename(filePath));
            try map.put(sectionName, section);
        }
    }

    const outputFileName = "output.req";
    const outputFile = try std.fs.cwd().createFile(outputFileName, .{});
    const writer = outputFile.writer();
    _ = try writer.write("ucft\n{\n\tREQN\n\t{\n");
    var iter = map.keyIterator();
    while (iter.next()) |sectionName| {
        try std.fmt.format(writer, "\t\t\"{s}\"\n", .{sectionName.*});
        for (map.get(sectionName.*).?.items) |item| {
            try std.fmt.format(writer, "\t\t\"{s}\"\n", .{item});
        }
    }
    _ = try writer.write("\t}\n}\n");
}

fn readOdfLines(file: std.fs.File) void {
    const reader = file.reader();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var maybeLine = try reader.readUntilDelimiterOrEofAlloc(allocator, '\n', 2048);
    while (maybeLine) |line| : (maybeLine = try reader.readUntilDelimiterOrEofAlloc(allocator, '\n', 2048)) {
        print("Got line: {s}\n", .{line});
    }
}
