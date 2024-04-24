//-------- IMPORTS --------//
const std = @import("std");

const writer = @import("writer.zig");

//-------- TYPES --------//
const StrArrayList = std.ArrayList([]const u8);

//-------- STATIC CONSTANTS --------//
const root_logger = std.log.scoped(.root);

//-------- CODE --------//
pub const Cli = struct {
    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, options: anytype) !Self {
        _ = allocator;
        _ = options;
        return Self{};
    }

    pub fn run(self: *Self) !void {
        _ = self;
    }
};

pub fn run(allocator: std.mem.Allocator, opt: anytype) !void {
    var files = StrArrayList.init(allocator);
    defer files.deinit();

    for (opt.positional_args.items, 0..) |arg, idx| {
        const abs_dir = if (std.fs.path.isAbsolute(arg)) abs_dir: {
            break :abs_dir std.fs.openDirAbsolute(arg, .{}) catch |err| {
                root_logger.err("{!s}: Could not open absolute dir {s}\n", .{ @errorName(err), arg });
                std.process.exit(1);
            };
        } else rel_dir: {
            break :rel_dir std.fs.cwd().openDir(arg, .{}) catch |err| {
                root_logger.err("{!s}: Could not open relative dir {s}\n", .{ @errorName(err), arg });
                std.process.exit(1);
            };
        };
        const abs_dir_path = try abs_dir.realpathAlloc(allocator, ".");
        if (std.fs.path.dirname(abs_dir_path)) |parent_name| {
            var parent_dir = try std.fs.openDirAbsolute(parent_name, .{});
            defer parent_dir.close();

            const stat = try parent_dir.statFile(abs_dir_path);
            switch (stat.kind) {
                .directory => {
                    const dir = try std.fs.openDirAbsolute(abs_dir_path, .{ .iterate = true });
                    var iter = dir.iterate();
                    while (try iter.next()) |entry| {
                        if (entry.kind != .file) continue; // TODO what about PC/XBOX/PS2 platform dirs?
                        const abs_file_path = try std.fs.path.join(
                            allocator,
                            &[_][]const u8{
                                try dir.realpathAlloc(allocator, "."),
                                entry.name,
                            },
                        );
                        try files.append(abs_file_path);
                    }
                },
                .file => {
                    try files.append(arg);
                },
                else => {
                    root_logger.warn(
                        "{s} in position {d} was somehow neither a dir or file, skipping...\n",
                        .{ arg, idx },
                    );
                },
            }
        }
    }
    root_logger.info("Found {d} files", .{files.items.len});
    const output_file_name = std.fs.path.basename(try std.fs.cwd().realpathAlloc(allocator, "."));
    try writer.generateReqFile(
        allocator,
        .{ .parse_odfs = opt.args.@"parse-odfs".?, .output_name = &output_file_name },
        files,
    );
    root_logger.info("reqtool completed successfully", .{});
}
