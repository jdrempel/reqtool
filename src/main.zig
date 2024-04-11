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
        .@"parse-odfs" = "When set, .odf files will be parsed and have dependencies added to the .req file automatically",
    };
};

const root_logger = std.log.scoped(.root);

pub fn main() !void {
    root_logger.info("Starting reqtool", .{});

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

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

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

    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        glfw.pollEvents();

        gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0, 0, 0, 1.0 });

        const fb_size = window.getFramebufferSize();

        zgui.backend.newFrame(
            @intCast(fb_size[0]),
            @intCast(fb_size[1]),
        );

        zgui.setNextWindowPos(.{ .x = 20.0, .y = 20.0, .cond = .first_use_ever });
        zgui.setNextWindowSize(.{ .w = -1.0, .h = -1.0, .cond = .first_use_ever });

        if (zgui.begin("My window", .{})) {
            if (zgui.button("Press me!", .{ .w = 200.0 })) {
                root_logger.info("Button pressed", .{});
            }
        }
        zgui.end();

        zgui.backend.draw();

        window.swapBuffers();
    }

    var opt = try simargs.parse(allocator, Args, "FILES...", null);
    defer opt.deinit();

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
                        const abs_file_path = try std.fs.path.join(allocator, &[_][]const u8{ try dir.realpathAlloc(allocator, "."), entry.name });
                        try files.append(abs_file_path);
                    }
                },
                .file => {
                    try files.append(arg);
                },
                else => {
                    root_logger.warn("{s} in position {d} was somehow neither a dir or file, skipping...\n", .{ arg, idx });
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
