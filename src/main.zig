//-------- IMPORTS --------//
const std = @import("std");
const simargs = @import("simargs");

const writer = @import("writer.zig");
const cli = @import("cli.zig");
const gui = @import("gui.zig");
const util = @import("util/root.zig");

//-------- TYPES --------//
const StrArrayList = std.ArrayList([]const u8);

const Args = struct {
    output: ?[]const u8,
    @"parse-odfs": ?bool = false,
    help: bool = false,

    pub const __shorts__ = .{
        .output = .o,
        .@"parse-odfs" = .p,
        .help = .h,
    };

    pub const __messages__ = .{
        .output = "The name of the .req file to output (no extension required)",
        .@"parse-odfs" =
        \\When set, .odf files will be parsed and have dependencies added to 
        \\the .req file automatically
        ,
    };
};

const root_logger = std.log.scoped(.root);

//-------- LOGGING --------//
pub const std_options: std.Options = .{
    .log_level = .info,
    .logFn = stdLog,
};
fn stdLog(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const scope_prefix = "(" ++ switch (scope) {
        .root,
        .parser,
        .writer,
        std.log.default_log_scope,
        => @tagName(scope),
        else => if (@intFromEnum(level) <= @intFromEnum(std.log.Level.err))
            @tagName(scope)
        else
            return,
    } ++ "):\t";

    const prefix = "[" ++ comptime level.asText() ++ "] " ++ scope_prefix;

    std.debug.getStderrMutex().lock();
    defer std.debug.getStderrMutex().unlock();
    const stderr = std.io.getStdErr().writer();
    nosuspend stderr.print(prefix ++ format ++ "\n", args) catch return;
}

//-------- CODE :) --------//
pub fn main() !void {
    root_logger.info("Starting reqtool", .{});

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var opt = try simargs.parse(allocator, Args, "FILES...", null);
    defer opt.deinit();

    if (opt.positional_args.items.len > 0) {
        try cli.run(allocator, opt);
    } else {
        try gui.run(allocator, opt);
    }
}
