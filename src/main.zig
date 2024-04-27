//-------- IMPORTS --------//
const std = @import("std");
const simargs = @import("simargs");

const cli = @import("cli.zig");
const gui = @import("gui.zig");
const modargs = @import("args.zig");
const util = @import("util/root.zig");
const writer = @import("writer.zig");

//-------- TYPES --------//
const StrArrayList = std.ArrayList([]const u8);
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

const UiType = enum { cli, gui };
const Ui = union(UiType) {
    cli: cli.Cli,
    gui: gui.Gui,
};

//-------- CODE :) --------//
pub fn main() !void {
    root_logger.info("Starting reqtool", .{});

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const ally = arena.allocator();

    var args = try simargs.parse(ally, modargs.Args, "FILES...", null);
    defer args.deinit();

    const options = modargs.Options{
        .files = args.positional_args,
        .parse_odfs = args.args.@"parse-odfs".?,
        .output_name = args.args.output orelse "",
    };

    var ui: Ui = if (args.positional_args.items.len > 0) cli: {
        break :cli Ui{ .cli = try cli.Cli.init(ally, options) };
    } else gui: {
        break :gui Ui{ .gui = try gui.Gui.init(ally, options) };
    };
    switch (ui) {
        .cli => try ui.cli.run(),
        .gui => try ui.gui.run(),
    }
}
