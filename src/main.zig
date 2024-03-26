const std = @import("std");
const simargs = @import("simargs");

const util = @import("util/root.zig");
const ReqDatabase = @import("writer.zig").ReqDatabase;

const print = std.debug.print;

const StrArrayList = std.ArrayList([]const u8);

const Args = struct {};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var opt = try simargs.parse(allocator, Args, "[file]", null);
    defer opt.deinit();

    var files = StrArrayList.init(allocator);
    defer files.deinit();

    for (opt.positional_args.items, 0..) |arg, idx| {
        const abs_dir = if (std.fs.path.isAbsolute(arg)) a: {
            break :a std.fs.openDirAbsolute(arg, .{}) catch |err| {
                print("{!}: {s}\n", .{ err, arg });
                std.process.exit(1);
            };
        } else b: {
            break :b std.fs.cwd().openDir(arg, .{}) catch |err| {
                print("{!}: {s}\n", .{ err, arg });
                std.process.exit(1);
            };
        };
        const abs_dir_path = try abs_dir.realpathAlloc(allocator, ".");
        const maybe_parent_name = std.fs.path.dirname(abs_dir_path);
        if (maybe_parent_name) |parent_name| {
            var parent_dir = try std.fs.openDirAbsolute(parent_name, .{});
            defer parent_dir.close();

            const stat = try parent_dir.statFile(abs_dir_path);
            switch (stat.kind) {
                .directory => {
                    print("{s} was a directory, iterating...\n", .{abs_dir_path});
                    const dir = try std.fs.openDirAbsolute(abs_dir_path, .{ .iterate = true });
                    var iter = dir.iterate();
                    while (try iter.next()) |entry| {
                        if (entry.kind != std.fs.File.Kind.file) continue; // TODO what about PC/XBOX/PS2 platform dirs?
                        var path_components = StrArrayList.init(allocator);
                        try path_components.append(try dir.realpathAlloc(allocator, "."));
                        try path_components.append(entry.name);
                        const abs_file_path = try std.fs.path.join(allocator, path_components.items);
                        // const entry_name_copy = try allocator.dupe(u8, entry.name);
                        try files.append(abs_file_path);
                    }
                },
                .file => {
                    try files.append(arg);
                },
                else => {
                    print("{s} in position {d} was somehow neither a dir or file, skipping...\n", .{ arg, idx });
                },
            }
        }
    }

    var db = ReqDatabase.init(allocator);

    for (files.items) |file_path| {
        try db.addEntry(file_path);
    }

    const output_file = try std.fs.cwd().createFile("output.req", .{});
    const file_writer = output_file.writer();
    try db.write(file_writer);
}
