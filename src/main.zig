const std = @import("std");
const simargs = @import("simargs");

const glfw = @import("zglfw");
const zgpu = @import("zgpu");
const zopengl = @import("zopengl");
const wgpu = zgpu.wgpu;
const zgui = @import("zgui");

const window_title = "reqtool";

const util = @import("util/root.zig");
const ReqDatabase = @import("writer.zig").ReqDatabase;

pub const std_options = struct {
    pub const log_level = .info;
    pub const logFn = stdLog;
};
fn stdLog(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const scope_prefix = "(" ++ switch (scope) {
        .root, .parser, .writer, std.log.default_log_scope => @tagName(scope),
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

const EntryData = struct {
    name: [:0]const u8,
    selected: *bool,
    kind: std.fs.File.Kind,
};

const root_logger = std.log.scoped(.root);

pub fn main() !void {
    root_logger.info("Starting reqtool", .{});

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var opt = try simargs.parse(allocator, Args, "FILES...", null);
    defer opt.deinit();

    if (opt.positional_args.items.len > 0) {
        try runCliMode(allocator, opt);
    } else {
        try runGuiMode(allocator, opt);
    }
}

fn runCliMode(allocator: std.mem.Allocator, opt: anytype) !void {
    var files = StrArrayList.init(allocator);
    defer files.deinit();

    for (opt.positional_args.items, 0..) |arg, idx| {
        const abs_dir = if (std.fs.path.isAbsolute(arg)) a: {
            break :a std.fs.openDirAbsolute(arg, .{}) catch |err| {
                root_logger.err("{!s}: {s}\n", .{ @errorName(err), arg });
                std.process.exit(1);
            };
        } else b: {
            break :b std.fs.cwd().openDir(arg, .{}) catch |err| {
                root_logger.err("{!s}: {s}\n", .{ @errorName(err), arg });
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
                    const dir = try std.fs.openDirAbsolute(abs_dir_path, .{ .iterate = true });
                    var iter = dir.iterate();
                    while (try iter.next()) |entry| {
                        if (entry.kind != std.fs.File.Kind.file) continue; // TODO what about PC/XBOX/PS2 platform dirs?
                        const abs_file_path = try std.fs.path.join(allocator, &[_][]const u8{
                            try dir.realpathAlloc(allocator, "."),
                            entry.name,
                        });
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

    var db = ReqDatabase.init(allocator, opt);

    for (files.items) |file_path| {
        try db.addEntry(file_path);
    }

    var output_file_name = opt.args.output orelse "output.req";
    if (!std.mem.endsWith(u8, output_file_name, ".req")) {
        output_file_name = try std.mem.concat(allocator, u8, &[_][]const u8{ output_file_name, ".req" });
    }
    const output_file = std.fs.cwd().createFile(output_file_name, .{}) catch |err| {
        root_logger.err("{!s}: {s}\n", .{ @errorName(err), output_file_name });
        std.process.exit(1);
    };
    const file_writer = output_file.writer();
    root_logger.info("Writing output to {s}", .{output_file_name});
    try db.write(file_writer);

    root_logger.info("reqtool completed successfully", .{});
}

fn runGuiMode(allocator: std.mem.Allocator, opt: anytype) !void {
    _ = opt;

    try glfw.init();
    defer glfw.terminate();

    const gl_major = 4;
    const gl_minor = 0;
    glfw.windowHintTyped(.context_version_major, gl_major);
    glfw.windowHintTyped(.context_version_minor, gl_minor);
    glfw.windowHintTyped(.opengl_profile, .opengl_core_profile);
    glfw.windowHintTyped(.opengl_forward_compat, true);
    glfw.windowHintTyped(.client_api, .opengl_api);
    glfw.windowHintTyped(.doublebuffer, true);

    const window = try glfw.Window.create(800, 600, window_title, null);
    defer window.destroy();
    window.setSizeLimits(400, 300, -1, -1);

    glfw.makeContextCurrent(window);
    glfw.swapInterval(1);

    try zopengl.loadCoreProfile(glfw.getProcAddress, gl_major, gl_minor);

    const gl = zopengl.bindings;

    zgui.init(allocator);
    defer zgui.deinit();

    const scale_factor = scale_factor: {
        const scale = window.getContentScale();
        break :scale_factor @max(scale[0], scale[1]);
    };
    _ = zgui.io.addFontFromFile(
        "assets/Roboto-Medium.ttf",
        std.math.floor(16.0 * scale_factor),
    );

    zgui.getStyle().scaleAllSizes(scale_factor);

    zgui.backend.init(window);
    defer zgui.backend.deinit();

    var selection_data = std.ArrayList(EntryData).init(allocator);
    defer selection_data.deinit();

    const browse_path = try allocator.allocSentinel(u8, 4096, 0);

    var current_dir = std.fs.cwd();
    try loadDirectory(
        allocator,
        ".",
        &selection_data,
        &current_dir,
        browse_path,
    );

    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        glfw.pollEvents();

        gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0, 0, 0, 1.0 });

        const fb_size = window.getFramebufferSize();

        zgui.backend.newFrame(
            @intCast(fb_size[0]),
            @intCast(fb_size[1]),
        );

        zgui.setNextWindowPos(.{ .x = 0.0, .y = 0.0, .cond = .always });
        zgui.setNextWindowSize(.{ .w = 400.0, .h = 600.0, .cond = .always });

        if (zgui.begin("My window", .{
            .flags = .{
                .no_title_bar = true,
                .no_resize = true,
                .no_move = true,
                .always_auto_resize = true,
                .no_background = true,
                .no_scrollbar = true,
                .no_scroll_with_mouse = true,
                .no_collapse = true,
            },
        })) {
            if (zgui.button("Go up", .{})) {
                try loadDirectory(
                    allocator,
                    "..",
                    &selection_data,
                    &current_dir,
                    browse_path,
                );
            }
            zgui.sameLine(.{ .spacing = 50.0 });
            if (zgui.inputTextWithHint("##Browse", .{ .hint = "Navigate to an absolute path", .buf = browse_path })) {}
            zgui.sameLine(.{});
            if (zgui.button("Go", .{})) {
                var val: []u8 = undefined;
                var stream = std.io.fixedBufferStream(browse_path);
                const reader = stream.reader();
                val = try reader.readUntilDelimiterAlloc(allocator, 0, 4096);
                root_logger.debug("Abs path: {s}", .{val});
                try loadDirectoryAbsolute(
                    allocator,
                    val,
                    &selection_data,
                    &current_dir,
                    browse_path,
                );
            }
            if (zgui.beginListBox("##FileSelect", .{ .w = -1.0, .h = -1.0 })) {
                for (selection_data.items) |item| {
                    const prefix = switch (item.kind) {
                        .directory => "[D] ",
                        .file => "[F] ",
                        else => " " ** 4,
                    };
                    const selectable_name = try std.mem.concatWithSentinel(
                        allocator,
                        u8,
                        &[_][]const u8{ prefix, item.name },
                        0,
                    );
                    const selectable_flags: zgui.SelectableFlags = switch (item.kind) {
                        .directory => .{ .allow_double_click = true },
                        .file => .{},
                        else => .{},
                    };
                    if (zgui.selectableStatePtr(selectable_name, .{
                        .pselected = item.selected,
                        .flags = selectable_flags,
                    })) {
                        if (zgui.isMouseDoubleClicked(.left)) {
                            try loadDirectory(
                                allocator,
                                item.name,
                                &selection_data,
                                &current_dir,
                                browse_path,
                            );
                            break;
                        }
                    }
                }
                zgui.endListBox();
            }
            if (zgui.button("Generate REQ", .{})) {}
            zgui.end();
        }

        zgui.setNextWindowPos(.{ .x = 400.0, .y = 0.0, .cond = .always });
        zgui.setNextWindowSize(.{ .w = 400.0, .h = 600.0, .cond = .always });

        if (zgui.begin("Your window", .{
            .flags = .{
                .no_title_bar = true,
                .no_resize = true,
                .no_move = true,
                .always_auto_resize = true,
                .no_background = true,
                .no_scrollbar = true,
                .no_scroll_with_mouse = true,
                .no_collapse = true,
            },
        })) {
            zgui.end();
        }

        zgui.backend.draw();

        window.swapBuffers();
    }
}

fn loadDirectory(
    allocator: std.mem.Allocator,
    path: []const u8,
    selection_data: *std.ArrayList(EntryData),
    current_dir: *std.fs.Dir,
    browse_path: [:0]u8,
) !void {
    const dir = try current_dir.*.openDir(path, .{ .iterate = true });
    @memset(browse_path[0..4096], 0);
    const new_browse_path = try dir.realpathAlloc(allocator, ".");
    std.mem.copyForwards(u8, browse_path, new_browse_path);
    selection_data.*.clearAndFree();
    current_dir.* = dir;
    try _loadDirectoryImpl(dir, allocator, selection_data);
}

fn loadDirectoryAbsolute(
    allocator: std.mem.Allocator,
    path: []const u8,
    selection_data: *std.ArrayList(EntryData),
    current_dir: *std.fs.Dir,
    browse_path: [:0]u8,
) !void {
    const dir = try std.fs.openDirAbsolute(path, .{ .iterate = true });
    @memset(browse_path[0..4096], 0);
    const new_browse_path = try dir.realpathAlloc(allocator, ".");
    std.mem.copyForwards(u8, browse_path, new_browse_path);
    selection_data.*.clearAndFree();
    current_dir.* = dir;
    try _loadDirectoryImpl(dir, allocator, selection_data);
}

fn _loadDirectoryImpl(
    dir: std.fs.Dir,
    allocator: std.mem.Allocator,
    selection_data: *std.ArrayList(EntryData),
) !void {
    var it: std.fs.Dir.Iterator = dir.iterate();
    var current = it.next() catch null;
    while (current) |entry| {
        const entry_name = try allocator.allocSentinel(u8, entry.name.len, 0);
        std.mem.copyForwards(u8, entry_name, entry.name);
        const b = try allocator.create(bool);
        try selection_data.*.append(.{
            .name = entry_name,
            .selected = b,
            .kind = entry.kind,
        });
        current = it.next() catch null;
    }
}
