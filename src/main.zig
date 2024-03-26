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
            const parentDir = try std.fs.openDirAbsolute(p, .{});
            const stat = try parentDir.statFile(arg);
            switch (stat.kind) {
                .directory => {
                    print("{s} was a directory, iterating...\n", .{arg});
                    const dir = try std.fs.openDirAbsolute(arg, .{ .iterate = true });
                    var iter = dir.iterate();
                    while (try iter.next()) |entry| {
                        if (entry.kind != std.fs.File.Kind.file) continue; // TODO what about PC/XBOX/PS2 platform dirs?
                        const entryNameCopy = try allocator.dupe(u8, entry.name);
                        try files.append(entryNameCopy);
                    }
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
        print("FILE    {s}\n", .{filePath});
        try db.addEntry(filePath);
    }

    for (directories.items) |dirPath| {
        _ = dirPath;
    }

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
