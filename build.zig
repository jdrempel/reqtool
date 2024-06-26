const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "reqtool",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const arch_name = if (target.query.cpu_arch) |arch| @tagName(arch) else "native";
    const os_name = if (target.query.os_tag) |os_tag| @tagName(os_tag) else "native";
    const options = .{
        .version = b.option(
            []const u8,
            "release_version",
            "The semver name for the release this build is part of",
        ) orelse "0.0.0",
        .platform = b.option(
            []const u8,
            "platform",
            "The name of the platform for which this build was released",
        ) orelse try std.mem.concat(b.allocator, u8, &[_][:0]const u8{ arch_name, "-", os_name }),
    };
    const options_step = b.addOptions();
    inline for (std.meta.fields(@TypeOf(options))) |field| {
        options_step.addOption(field.type, field.name, @field(options, field.name));
    }
    const options_module = options_step.createModule();
    exe.root_module.addImport("build_options", options_module);

    // zigcli stuff
    {
        const zigcli = b.dependency("zigcli", .{});
        exe.root_module.addImport("simargs", zigcli.module("simargs"));
    }

    // zig-gamedev stuff
    {
        @import("system_sdk").addLibraryPathsTo(exe);

        if (target.query.os_tag == .windows) {
            const zwin32 = b.dependency("zwin32", .{});
            const zwin32_path = zwin32.path("").getPath(b);
            exe.root_module.addImport("zwin32", zwin32.module("root"));
            try @import("zwin32").install_d3d12(b.getInstallStep(), .bin, zwin32_path);

            const zd3d12 = b.dependency("zd3d12", .{
                .debug_layer = false,
                .gbv = false,
            });
            exe.root_module.addImport("zd3d12", zd3d12.module("root"));
        }

        const zgui = b.dependency("zgui", .{
            .shared = false,
            .with_implot = true,
            .backend = .glfw_opengl3,
        });
        exe.root_module.addImport("zgui", zgui.module("root"));
        exe.linkLibrary(zgui.artifact("imgui"));

        const zglfw = b.dependency("zglfw", .{});
        exe.root_module.addImport("zglfw", zglfw.module("root"));
        exe.linkLibrary(zglfw.artifact("glfw"));

        const zopengl = b.dependency("zopengl", .{
            .target = target,
        });
        exe.root_module.addImport("zopengl", zopengl.module("root"));
    }

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
