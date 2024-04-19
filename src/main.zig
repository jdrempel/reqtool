const std = @import("std");
const simargs = @import("simargs");

const glfw = @import("zglfw");
const zgpu = @import("zgpu");
const zopengl = @import("zopengl");
const wgpu = zgpu.wgpu;
const zgui = @import("zgui");

const gl_major = 4;
const gl_minor = 0;
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

    const Self = @This();
    pub fn kindLessThan(self: *const Self, other: Self) bool {
        if (self.kind == .directory and other.kind != .directory) {
            return true;
        }
        if (other.kind == .directory and self.kind != .directory) {
            return false;
        }
        return true;
    }
};

const ReqToolContext = struct {
    selection_data: *std.ArrayList(EntryData),
    browse_path: *[:0]u8,
    parse_odfs: bool,
    show_all_file_types: bool,
    current_dir: *std.fs.Dir,
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
                root_logger.err("{!s}: Could not open absolute dir {s}\n", .{ @errorName(err), arg });
                std.process.exit(1);
            };
        } else b: {
            break :b std.fs.cwd().openDir(arg, .{}) catch |err| {
                root_logger.err("{!s}: Could not open relative dir {s}\n", .{ @errorName(err), arg });
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
    const output_file_name = std.fs.path.basename(try std.fs.cwd().realpathAlloc(allocator, "."));
    try generateReqFile(allocator, .{ .parse_odfs = opt.args.@"parse-odfs".? }, files, output_file_name);
    root_logger.info("reqtool completed successfully", .{});
}

fn runGuiMode(allocator: std.mem.Allocator, opt: anytype) !void {
    try glfw.init();
    defer glfw.terminate();

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

    var browse_path = try allocator.allocSentinel(u8, 4096, 0);

    // Hacks! parse_odfs has to be a var but isn't mutated outside of opaque C code
    //  so we just double-not it. :)
    var parse_odfs = opt.args.@"parse-odfs".?;
    parse_odfs = !!parse_odfs;

    var current_dir = std.fs.cwd();
    try loadDirectory(
        allocator,
        ".",
        &selection_data,
        &current_dir,
        browse_path,
    );

    var context = ReqToolContext{
        .selection_data = &selection_data,
        .browse_path = &browse_path,
        .parse_odfs = parse_odfs,
        .show_all_file_types = false,
        .current_dir = &current_dir,
    };

    while (!window.shouldClose()) {
        setupNewFrame(&gl, &window);

        showMainMenuBar();
        try showMainWindow(allocator, &context);
        showOptionsWindow(&context);

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
    std.sort.pdq(EntryData, selection_data.*.items, {}, struct {
        fn lt(_: void, l: EntryData, r: EntryData) bool {
            return l.kindLessThan(r);
        }
    }.lt);
    std.sort.pdq(EntryData, selection_data.*.items, {}, struct {
        fn lt(_: void, l: EntryData, r: EntryData) bool {
            return std.ascii.lessThanIgnoreCase(l.name, r.name) and l.kindLessThan(r);
        }
    }.lt);
}

fn getNumSelected(selection_data: *std.ArrayList(EntryData)) u32 {
    var count: u32 = 0;
    for (selection_data.*.items) |item| {
        count += if (item.selected.*) 1 else 0;
    }
    return count;
}

fn setAllSelected(val: bool, selection_data: *std.ArrayList(EntryData)) void {
    for (selection_data.*.items) |item| {
        item.selected.* = val;
    }
}

fn generateReqFile(allocator: std.mem.Allocator, options: anytype, files: StrArrayList, output_file_name: []const u8) !void {
    var db = ReqDatabase.init(allocator, options);

    for (files.items) |file_path| {
        try db.addEntry(file_path);
    }

    const full_output_file_name = if (!std.mem.endsWith(u8, output_file_name, ".req")) fofn: {
        break :fofn try std.mem.concat(allocator, u8, &[_][]const u8{ output_file_name, ".req" });
    } else fofn: {
        break :fofn output_file_name;
    };
    const output_file = std.fs.cwd().createFile(full_output_file_name, .{}) catch |err| {
        root_logger.err("{!s}: Unable to create file {s}\n", .{ @errorName(err), output_file_name });
        std.process.exit(1);
    };
    const file_writer = output_file.writer();
    root_logger.info("Writing output to {s}", .{full_output_file_name});
    try db.write(file_writer);
}

fn setupNewFrame(gl_ptr: anytype, window_ptr: *const *glfw.Window) void {
    glfw.pollEvents();

    gl_ptr.*.clearBufferfv(gl_ptr.*.COLOR, 0, &[_]f32{ 0, 0, 0, 1.0 });

    const fb_size = window_ptr.*.getFramebufferSize();

    zgui.backend.newFrame(
        @intCast(fb_size[0]),
        @intCast(fb_size[1]),
    );
}

fn showMainMenuBar() void {
    if (zgui.beginMainMenuBar()) {
        if (zgui.beginMenu("File", true)) {
            if (zgui.menuItem("Quit", .{})) {}
            zgui.endMenu();
        }
        if (zgui.beginMenu("Help", true)) {
            if (zgui.menuItem("About...", .{})) {}
            zgui.endMenu();
        }
        zgui.endMainMenuBar();
    }
}

fn showMainWindow(allocator: std.mem.Allocator, context: *ReqToolContext) !void {
    const main_viewport = zgui.getMainViewport();
    const main_viewport_size = main_viewport.getWorkSize();
    const main_viewport_pos = main_viewport.getWorkPos();
    zgui.setNextWindowPos(.{
        .x = main_viewport_pos[0],
        .y = main_viewport_pos[1],
        .cond = .always,
    });
    zgui.setNextWindowSize(.{
        .w = main_viewport_size[0] * 2.0 / 3.0,
        .h = main_viewport_size[1],
        .cond = .always,
    });

    if (zgui.begin("My window", .{
        .flags = .{
            .no_title_bar = true,
            .no_resize = true,
            .no_move = true,
            .no_scrollbar = true,
            .no_scroll_with_mouse = true,
            .no_collapse = true,
        },
    })) {
        if (zgui.button("Go up", .{})) {
            try loadDirectory(
                allocator,
                "..",
                context.*.selection_data,
                context.*.current_dir,
                context.*.browse_path.*,
            );
        }
        zgui.sameLine(.{ .spacing = 50.0 });
        if (zgui.inputTextWithHint("##Browse", .{ .hint = "Navigate to an absolute path", .buf = context.*.browse_path.* })) {}
        zgui.sameLine(.{});
        if (zgui.button("Go", .{})) {
            var val: []u8 = undefined;
            var stream = std.io.fixedBufferStream(context.*.browse_path.*);
            const reader = stream.reader();
            val = try reader.readUntilDelimiterAlloc(allocator, 0, 4096);
            root_logger.debug("Abs path: {s}", .{val});
            try loadDirectoryAbsolute(
                allocator,
                val,
                context.*.selection_data,
                context.*.current_dir,
                context.*.browse_path.*,
            );
        }
        if (zgui.beginListBox("##FileSelect", .{ .w = -1.0, .h = -100.0 })) {
            for (context.*.selection_data.items) |item| {
                const prefix = switch (item.kind) {
                    .directory => "-> ",
                    .file => "    ",
                    else => " " ** 4,
                };
                const selectable_name = try std.mem.concatWithSentinel(
                    allocator,
                    u8,
                    &[_][]const u8{ prefix, item.name },
                    0,
                );
                const selectable_flags: zgui.SelectableFlags = switch (item.kind) {
                    .directory => .{ .allow_double_click = true, .allow_overlap = true },
                    .file => .{ .allow_overlap = true },
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
                            context.*.selection_data,
                            context.*.current_dir,
                            context.*.browse_path.*,
                        );
                        break;
                    }
                }
            }
            zgui.endListBox();
        }
        if (zgui.button("Select all", .{})) {
            setAllSelected(true, context.*.selection_data);
        }
        zgui.sameLine(.{});
        if (zgui.button("Select none", .{})) {
            setAllSelected(false, context.*.selection_data);
        }
        zgui.sameLine(.{});
        const num_selected = getNumSelected(context.*.selection_data);
        zgui.text("Selected: {d}", .{num_selected});
        if (num_selected == 0) {
            zgui.beginDisabled(.{});
        }
        if (zgui.button("Generate REQ", .{})) {
            var files = StrArrayList.init(allocator);
            const trimmed_browse_path = std.mem.trim(u8, context.*.browse_path.*, &[_]u8{0});
            for (context.*.selection_data.items) |item| {
                if (!item.selected.*) continue;
                const full_path = try std.fs.path.join(allocator, &[_][]const u8{
                    trimmed_browse_path,
                    item.name,
                });
                const real_path = try std.fs.realpathAlloc(allocator, full_path);
                try files.append(real_path);
            }
            try generateReqFile(allocator, context.*, files, std.fs.path.basename(trimmed_browse_path));
        }
        if (num_selected == 0) {
            zgui.endDisabled();
        }
        zgui.end();
    }
}

fn showOptionsWindow(context: *ReqToolContext) void {
    const main_viewport = zgui.getMainViewport();
    const main_viewport_size = main_viewport.getWorkSize();
    const main_viewport_pos = main_viewport.getWorkPos();

    zgui.setNextWindowPos(.{
        .x = main_viewport_size[0] * 2.0 / 3.0,
        .y = main_viewport_pos[1],
        .cond = .always,
    });
    zgui.setNextWindowSize(.{
        .w = main_viewport_size[0] * 1.0 / 3.0,
        .h = main_viewport_size[1],
        .cond = .always,
    });

    if (zgui.begin("Your window", .{
        .flags = .{
            .no_title_bar = true,
            .no_resize = true,
            .no_move = true,
            .always_auto_resize = true,
            .no_collapse = true,
        },
    })) {
        zgui.text("Options", .{});
        zgui.separator();
        _ = zgui.checkbox("Show unrecognized file types", .{ .v = &(context.*.show_all_file_types) });
        _ = zgui.checkbox("Parse ODF files", .{ .v = &(context.*.parse_odfs) });
        zgui.end();
    }
}
