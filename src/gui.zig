//-------- IMPORTS --------//
const std = @import("std");

const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const zgui = @import("zgui");

const build_options = @import("build_options");
const modargs = @import("args.zig");
const util = @import("util/root.zig");
const writer = @import("writer.zig");

//-------- TYPES --------//
const StrArrayList = std.ArrayList([]const u8);

const EntryData = struct {
    name: [:0]const u8,
    selected: *bool,
    kind: std.fs.File.Kind,
    file_type: writer.FileTypes,

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

const InputState = enum {
    clean,
    dirty,
};

const ReqToolContext = struct {
    selection_data: *std.ArrayList(EntryData),
    browse_path: *[:0]u8,
    output_name: *[:0]u8,
    parse_odfs: bool,
    show_all_file_types: bool,
    current_dir: *std.fs.Dir,
    output_name_state: InputState = .clean,
    db: writer.ReqDatabase,
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
    \\License: MIT
;
const repo_url = "https://github.com/jdrempel/reqtool";

const root_logger = std.log.scoped(.root);

//-------- CODE --------//
pub const Gui = struct {
    allocator: std.mem.Allocator,
    options: modargs.Options,
    const Self = @This();

    pub fn init(ally: std.mem.Allocator, options: modargs.Options) !Self {
        return Self{
            .allocator = ally,
            .options = options,
        };
    }

    pub fn run(self: *Self) !void {
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

        zgui.init(self.allocator);
        defer zgui.deinit();

        const scale_factor = scale_factor: {
            const scale = window.getContentScale();
            break :scale_factor @max(scale[0], scale[1]);
        };
        _ = zgui.io.addFontFromMemoryCompressed(
            &(@import("assets/font_binary.zig").roboto_medium_compressed_data),
            std.math.floor(16.0 * scale_factor),
        );

        zgui.getStyle().scaleAllSizes(scale_factor);

        zgui.backend.init(window);
        defer zgui.backend.deinit();

        var selection_data = std.ArrayList(EntryData).init(self.allocator);
        defer selection_data.deinit();

        var browse_path = try self.allocator.allocSentinel(u8, 4096, 0);
        @memset(browse_path, 0);
        defer self.allocator.free(browse_path);

        var output_name = try self.allocator.allocSentinel(u8, 512, 0);
        @memset(output_name, 0);
        defer self.allocator.free(output_name);

        // Hacks! parse_odfs has to be a var but isn't mutated outside of opaque C code
        //  so we just double-not it. :)
        var parse_odfs = self.options.parse_odfs;
        parse_odfs = !!parse_odfs;

        var current_dir = std.fs.cwd();
        const cwd_realpath = try current_dir.realpathAlloc(self.allocator, ".");
        std.mem.copyForwards(u8, output_name, std.fs.path.basename(cwd_realpath));
        self.allocator.free(cwd_realpath);

        context = try self.allocator.create(ReqToolContext);
        defer self.allocator.destroy(context);
        context.* = ReqToolContext{
            .selection_data = &selection_data,
            .browse_path = &browse_path,
            .output_name = &output_name,
            .parse_odfs = parse_odfs,
            .show_all_file_types = false,
            .current_dir = &current_dir,
            .db = writer.ReqDatabase.init(self.allocator, .{ .parse_odfs = parse_odfs }),
        };

        try self.loadDirectory(".");

        while (!window.shouldClose()) {
            self.setupNewFrame(&gl, &window);

            try self.showMainMenuBar();
            self.showAboutModal();
            try self.showMainWindow();
            try self.showPreviewWindow();

            zgui.backend.draw();
            window.swapBuffers();
        }
    }

    fn setupNewFrame(self: *Self, gl_ptr: anytype, window_ptr: *const *glfw.Window) void {
        _ = self;

        glfw.pollEvents();

        gl_ptr.*.clearBufferfv(gl_ptr.*.COLOR, 0, &[_]f32{ 0, 0, 0, 1.0 });

        const fb_size = window_ptr.*.getFramebufferSize();

        zgui.backend.newFrame(
            @intCast(fb_size[0]),
            @intCast(fb_size[1]),
        );
    }

    fn showMainMenuBar(self: *Self) !void {
        if (zgui.beginMainMenuBar()) {
            if (zgui.beginMenu("File", true)) {
                if (zgui.menuItem("Open...", .{})) {}
                if (zgui.menuItem("Quit", .{})) {
                    std.process.exit(0);
                }
                zgui.endMenu();
            }
            if (zgui.beginMenu("Options", true)) {
                if (zgui.menuItemPtr("Show unrecognized file types", .{ .selected = &context.*.show_all_file_types })) {
                    try self.loadDirectory(".");
                }
                _ = zgui.menuItemPtr("Parse ODF files", .{ .selected = &context.*.parse_odfs });
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

    fn showAboutModal(self: *Self) void {
        _ = self;

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
                repo_url,
            });
            zgui.setItemDefaultFocus();
            if (zgui.button("Close", .{ .w = -1.0 })) {
                about_menu_open = false;
                zgui.closeCurrentPopup();
            }
            zgui.endPopup();
        }
    }

    fn showMainWindow(self: *Self) !void {
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
                try self.loadDirectory("..");
            }
            zgui.sameLine(.{});
            if (zgui.inputTextWithHint(
                "##Browse",
                .{
                    .hint = "Navigate to an absolute path (Ctrl+Z to undo)",
                    .buf = context.*.browse_path.*,
                    .flags = .{
                        .enter_returns_true = true,
                    },
                },
            )) {
                self.loadAtBrowsePath() catch |err| {
                    root_logger.err("Cannot load path {s}: {s}", .{ context.*.browse_path.*, @errorName(err) });
                };
            }
            zgui.sameLine(.{});
            const browse_path_empty = (std.mem.indexOfScalar(u8, context.*.browse_path.*, 0) == 0);
            if (browse_path_empty) {
                zgui.beginDisabled(.{});
            }
            if (zgui.button("Go", .{})) {
                self.loadAtBrowsePath() catch |err| {
                    root_logger.err("Cannot load path {s}: {s}", .{ context.*.browse_path.*, @errorName(err) });
                };
            }
            if (browse_path_empty) {
                zgui.endDisabled();
            }
            if (zgui.beginListBox("##FileSelect", .{ .w = -1.0, .h = -100.0 })) {
                self.showFileBrowserContents();
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
            zgui.separator();
            if (num_selected == 0) {
                zgui.beginDisabled(.{});
            }
            zgui.text("Output:", .{});
            zgui.sameLine(.{});
            const extension = ".req";
            zgui.setNextItemWidth(getFillWidthAgainstText(extension));
            _ = zgui.inputTextWithHint("##OutputName", .{
                .hint = "Name of output REQ",
                .buf = context.*.output_name.*,
                .callback = onOutputNameModified,
                .flags = .{
                    .callback_edit = true,
                },
            });
            zgui.sameLine(.{});
            const output_name_empty = (std.mem.indexOfScalar(u8, context.*.output_name.*, 0) == 0);
            zgui.text(extension, .{});
            if (output_name_empty) {
                zgui.beginDisabled(.{});
            }
            if (zgui.button("Generate REQ", .{ .w = -1.0, .h = -1.0 })) {
                try self.generateReqFile();
            }
            if (output_name_empty) {
                zgui.endDisabled();
            }
            if (num_selected == 0) {
                zgui.endDisabled();
            }
            zgui.end();
        }
    }

    fn showFileBrowserContents(self: *Self) void {
        for (context.*.selection_data.items) |item| {
            const prefix = switch (item.kind) {
                .directory => "-> ",
                .file => "    ",
                else => " " ** 4,
            };
            const selectable_name = std.mem.concatWithSentinel(
                self.allocator,
                u8,
                &[_][]const u8{ prefix, item.name },
                0,
            ) catch |err| e: {
                root_logger.err("OOM: {s}", .{@errorName(err)});
                break :e "ERROR: Out of memory";
            };

            const selectable_flags: zgui.SelectableFlags = switch (item.kind) {
                .directory => .{ .allow_double_click = true, .allow_overlap = true },
                .file => .{ .allow_overlap = true },
                else => .{},
            };

            // Directories should be pale blue, unknown types should be red
            if (item.kind == .directory or item.file_type == .__unknown__) {
                if (item.kind == .directory) {
                    zgui.pushStyleColor4f(.{
                        .idx = .text,
                        .c = .{ 0.75, 0.75, 0.9, 1.0 },
                    });
                } else if (item.file_type == .__unknown__) {
                    zgui.pushStyleColor4f(.{
                        .idx = .text,
                        .c = .{ 0.5, 0.4, 0.4, 1.0 },
                    });
                }
            }

            if (zgui.selectableStatePtr(selectable_name, .{
                .pselected = item.selected,
                .flags = selectable_flags,
            })) {
                if (zgui.isMouseDoubleClicked(.left)) {
                    self.loadDirectory(item.name) catch break;
                    if (item.kind == .directory or item.file_type == .__unknown__) {
                        zgui.popStyleColor(.{});
                    }
                    break;
                }
            }
            if (item.kind == .directory or item.file_type == .__unknown__) {
                zgui.popStyleColor(.{});
            }
        }
    }

    fn showPreviewWindow(self: *Self) !void {
        _ = self;

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

        if (zgui.begin("##Preview", .{
            .flags = .{
                .no_title_bar = true,
                .no_resize = true,
                .no_move = true,
                .always_auto_resize = true,
                .no_collapse = true,
            },
        })) {
            zgui.text("Preview", .{});
            zgui.separator();
            zgui.end();
        }
    }

    fn loadAtBrowsePath(self: *Self) !void {
        var val: []u8 = undefined;
        var stream = std.io.fixedBufferStream(context.*.browse_path.*);
        const reader = stream.reader();
        val = try reader.readUntilDelimiterAlloc(self.allocator, 0, 4096);
        if (val.len == 0) return;
        try self.loadDirectoryAbsolute(val);
    }

    fn loadDirectory(self: *Self, path: []const u8) !void {
        // Can't close the dir otherwise we end up with a panic situation
        const dir = try context.*.current_dir.*.openDir(path, .{ .iterate = true });
        try self.loadDirectoryImpl(dir);
    }

    fn loadDirectoryAbsolute(self: *Self, path: []const u8) !void {
        // Can't close the dir otherwise we end up with a panic situation
        const dir = try std.fs.openDirAbsolute(path, .{ .iterate = true });
        try self.loadDirectoryImpl(dir);
    }

    fn loadDirectoryImpl(self: *Self, dir: std.fs.Dir) !void {
        @memset(context.*.browse_path.*[0..4096], 0);
        const new_browse_path = try dir.realpathAlloc(self.allocator, ".");
        std.mem.copyForwards(u8, context.*.browse_path.*, new_browse_path);
        context.*.selection_data.*.clearAndFree();
        context.*.current_dir.* = dir;
        if (context.*.output_name_state == .clean) {
            const cwd_realpath = try context.*.current_dir.*.realpathAlloc(self.allocator, ".");
            @memset(context.*.output_name.*[0..512], 0);
            std.mem.copyForwards(u8, context.*.output_name.*, std.fs.path.basename(cwd_realpath));
        }

        var it: std.fs.Dir.Iterator = dir.iterate();
        var current = it.next() catch null;
        while (current) |entry| : (current = it.next() catch null) {
            const extension = try util.path.extension(self.allocator, entry.name);
            const file_type = std.meta.stringToEnum(writer.FileTypes, extension) orelse .__unknown__;
            if (entry.kind != .directory) {
                if (file_type == .__unknown__ and context.*.show_all_file_types == false) {
                    continue;
                }
            }
            const entry_name = try self.allocator.allocSentinel(u8, entry.name.len, 0);
            std.mem.copyForwards(u8, entry_name, entry.name);
            const b = try self.allocator.create(bool);
            try context.*.selection_data.*.append(.{
                .name = entry_name,
                .selected = b,
                .kind = entry.kind,
                .file_type = file_type,
            });
        }
        // Separate dirs and files
        std.sort.insertion(EntryData, context.*.selection_data.*.items, {}, struct {
            fn lt(_: void, l: EntryData, r: EntryData) bool {
                return l.kindLessThan(r);
            }
        }.lt);
        // Sort ascending alphabetically while preserving the dir/file separation from the last sort
        std.sort.insertion(EntryData, context.*.selection_data.*.items, {}, struct {
            fn lt(_: void, l: EntryData, r: EntryData) bool {
                return std.ascii.lessThanIgnoreCase(l.name, r.name) and l.kindLessThan(r);
            }
        }.lt);
    }

    fn generateReqFile(self: *Self) !void {
        var files = StrArrayList.init(self.allocator);
        const trimmed_browse_path = std.mem.trim(u8, context.*.browse_path.*, &[_]u8{0});
        for (context.*.selection_data.items) |item| {
            if (!item.selected.*) continue;
            const full_path = try std.fs.path.join(self.allocator, &[_][]const u8{
                trimmed_browse_path,
                item.name,
            });
            defer self.allocator.free(full_path);

            const real_path = try std.fs.realpathAlloc(self.allocator, full_path);

            if (item.kind == .file) {
                try files.append(real_path);
            } else if (item.kind == .directory) {
                root_logger.debug("Iterating {s}", .{real_path});
                const dir = try std.fs.openDirAbsolute(real_path, .{ .iterate = true });
                var iter = dir.iterate();
                var current = try iter.next();
                while (current) |entry| : (current = try iter.next()) {
                    if (entry.kind != .file) {
                        root_logger.debug("Skipping {s} because it is not a file...", .{entry.name});
                        continue;
                    }
                    if ((try util.path.extension(self.allocator, entry.name)).len == 0) {
                        root_logger.debug("Skipping {s} because it has no extension...", .{entry.name});
                        continue;
                    }
                    try files.append(try std.fs.path.join(self.allocator, &[_][]const u8{ real_path, entry.name }));
                }
            }
        }
        try writer.generateReqFile(self.allocator, context, files);
    }
};

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

fn getFillWidthAgainstText(text: []const u8) f32 {
    const avail = zgui.getContentRegionAvail();
    const text_size = zgui.calcTextSize(text, .{});
    const style_inner_spacing = zgui.getStyle().item_inner_spacing;
    return avail[0] - (text_size[0] + 2.0 * style_inner_spacing[0]);
}

fn onOutputNameModified(data: *zgui.InputTextCallbackData) i32 {
    _ = data;
    context.*.output_name_state = .dirty;
    return 1;
}
