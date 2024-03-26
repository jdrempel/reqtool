const std = @import("std");
const simargs = @import("simargs");

const util = @import("util/root.zig");
const ReqDatabase = @import("writer.zig").ReqDatabase;

const print = std.debug.print;

fn str(comptime N: usize) type {
    return *const [N:0]u8;
}

const StrArrayList = std.ArrayList([]const u8);

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
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var opt = try simargs.parse(allocator, Args, "[file]", null);
    defer opt.deinit();

    var directories = StrArrayList.init(allocator);
    defer directories.deinit();

    var files = StrArrayList.init(allocator);
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
                },
                .file => {
                    print("{s} was a file\n", .{arg});
                    try files.append(arg);
                },
                else => {
                    print("{s} in position {d} was somehow neither a dir or file, skipping...\n", .{ arg, idx });
                },
            }
        }
    }

    print("There are {d} files and {d} directories given.\n", .{ files.items.len, directories.items.len });

    var db = ReqDatabase.init(allocator);

    for (files.items) |filePath| {
        try db.addEntry(filePath);
    }

    for (directories.items) |dirPath| {}

    const outputFile = try std.fs.cwd().createFile("output.req", .{});
    const fileWriter = outputFile.writer();
    try db.write(fileWriter);

    const result = try util.string.quoteString("foobar", allocator);
    print("{s}\n", .{result});
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
