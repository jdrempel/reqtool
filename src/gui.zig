//-------- IMPORTS --------//
const std = @import("std");

const glfw = @import("zglfw");
const zgpu = @import("zgpu");
const zopengl = @import("zopengl");
const wgpu = zgpu.wgpu;
const zgui = @import("zgui");

const build_options = @import("build_options");
const util = @import("util/root.zig");
const writer = @import("writer.zig");
const FileTypes = @import("writer.zig").FileTypes;

//-------- TYPES --------//
const StrArrayList = std.ArrayList([]const u8);

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

//-------- STATIC CONSTANTS --------//
const gl_major = 4;
const gl_minor = 0;
const window_title = "reqtool";
var context: *ReqToolContext = undefined;
var about_menu_open = false;
const about_menu_text =
    \\reqtool
    \\
    \\{s} ({s})
    \\
    \\Author: jedimoose32
    \\Repository: {s}
    \\License: {s}
;

const root_logger = std.log.scoped(.root);

//-------- CODE --------//
pub fn run(allocator: std.mem.Allocator, opt: anytype) !void {
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
    defer allocator.free(browse_path);

    // Hacks! parse_odfs has to be a var but isn't mutated outside of opaque C code
    //  so we just double-not it. :)
    var parse_odfs = opt.args.@"parse-odfs".?;
    parse_odfs = !!parse_odfs;

    var current_dir = std.fs.cwd();

    context = try allocator.create(ReqToolContext);
    defer allocator.destroy(context);
    context.* = ReqToolContext{
        .selection_data = &selection_data,
        .browse_path = &browse_path,
        .parse_odfs = parse_odfs,
        .show_all_file_types = false,
        .current_dir = &current_dir,
    };

    try loadDirectory(allocator, ".");

    while (!window.shouldClose()) {
        setupNewFrame(&gl, &window);

        showMainMenuBar();
        showAboutModal();
        try showMainWindow(allocator);
        try showOptionsWindow(allocator);

        zgui.backend.draw();
        window.swapBuffers();
    }
}

fn loadDirectory(allocator: std.mem.Allocator, path: []const u8) !void {
    const dir = try context.*.current_dir.*.openDir(path, .{ .iterate = true });
    @memset(context.*.browse_path.*[0..4096], 0);
    const new_browse_path = try dir.realpathAlloc(allocator, ".");
    std.mem.copyForwards(u8, context.*.browse_path.*, new_browse_path);
    context.*.selection_data.*.clearAndFree();
    context.*.current_dir.* = dir;
    try _loadDirectoryImpl(allocator, dir);
}

fn loadDirectoryAbsolute(allocator: std.mem.Allocator, path: []const u8) !void {
    const dir = try std.fs.openDirAbsolute(path, .{ .iterate = true });
    @memset(context.*.browse_path.*[0..4096], 0);
    const new_browse_path = try dir.realpathAlloc(allocator, ".");
    std.mem.copyForwards(u8, context.*.browse_path.*, new_browse_path);
    context.*.selection_data.*.clearAndFree();
    context.*.current_dir.* = dir;
    try _loadDirectoryImpl(allocator, dir);
}

fn _loadDirectoryImpl(allocator: std.mem.Allocator, dir: std.fs.Dir) !void {
    var it: std.fs.Dir.Iterator = dir.iterate();
    var current = it.next() catch null;
    while (current) |entry| : (current = it.next() catch null) {
        if (entry.kind != .directory) {
            const extension = try util.path.extension(allocator, entry.name);
            const file_type = std.meta.stringToEnum(FileTypes, extension) orelse .__unknown__;
            if (file_type == .__unknown__ and context.*.show_all_file_types == false) {
                continue;
            }
        }
        const entry_name = try allocator.allocSentinel(u8, entry.name.len, 0);
        std.mem.copyForwards(u8, entry_name, entry.name);
        const b = try allocator.create(bool);
        try context.*.selection_data.*.append(.{
            .name = entry_name,
            .selected = b,
            .kind = entry.kind,
        });
    }
    std.sort.insertion(EntryData, context.*.selection_data.*.items, {}, struct {
        fn lt(_: void, l: EntryData, r: EntryData) bool {
            return l.kindLessThan(r);
        }
    }.lt);
    std.sort.insertion(EntryData, context.*.selection_data.*.items, {}, struct {
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

fn setAllFilesSelected(val: bool, selection_data: *std.ArrayList(EntryData)) void {
    for (selection_data.*.items) |item| {
        item.selected.* = (item.kind == .file) and val;
    }
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
            if (zgui.menuItem("Quit", .{})) {
                std.process.exit(0);
            }
            zgui.endMenu();
        }
        if (zgui.beginMenu("Help", true)) {
            if (zgui.menuItem("About...", .{})) {
                about_menu_open = true;
            }
            zgui.endMenu();
        }
        zgui.endMainMenuBar();
    }
}

fn showAboutModal() void {
    if (about_menu_open) {
        zgui.openPopup("About reqtool", .{});
    }
    const center = zgui.getMainViewport().getCenter();
    zgui.setNextWindowPos(.{
        .x = center[0],
        .y = center[1],
        .cond = .always,
        .pivot_x = 0.5,
        .pivot_y = 0.5,
    });
    if (zgui.beginPopupModal("About reqtool", .{ .flags = .{ .always_auto_resize = true } })) {
        zgui.text(about_menu_text, .{
            build_options.version,
            build_options.platform,
            "https://github.com/jdrempel/reqtool",
            "<license>",
        });
        zgui.setItemDefaultFocus();
        if (zgui.button("Close", .{ .w = -1.0 })) {
            about_menu_open = false;
            zgui.closeCurrentPopup();
        }
        zgui.endPopup();
    }
}

fn showMainWindow(allocator: std.mem.Allocator) !void {
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
            try loadDirectory(allocator, "..");
        }
        zgui.sameLine(.{ .spacing = 50.0 });
        _ = zgui.inputTextWithHint(
            "##Browse",
            .{
                .hint = "Navigate to an absolute path",
                .buf = context.*.browse_path.*,
            },
        );
        zgui.sameLine(.{});
        if (zgui.button("Go", .{})) {
            var val: []u8 = undefined;
            var stream = std.io.fixedBufferStream(context.*.browse_path.*);
            const reader = stream.reader();
            val = try reader.readUntilDelimiterAlloc(allocator, 0, 4096);
            try loadDirectoryAbsolute(allocator, val);
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
                        try loadDirectory(allocator, item.name);
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
        if (zgui.button("Select files", .{})) {
            setAllFilesSelected(true, context.*.selection_data);
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
            try writer.generateReqFile(allocator, context.*, files, std.fs.path.basename(trimmed_browse_path));
        }
        if (num_selected == 0) {
            zgui.endDisabled();
        }
        zgui.end();
    }
}

fn showOptionsWindow(allocator: std.mem.Allocator) !void {
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

    if (zgui.begin("##Options", .{
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
        if (zgui.checkbox("Show unrecognized file types", .{ .v = &(context.*.show_all_file_types) })) {
            try loadDirectory(allocator, ".");
        }
        _ = zgui.checkbox("Parse ODF files", .{ .v = &(context.*.parse_odfs) });
        zgui.end();
    }
}
