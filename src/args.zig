const std = @import("std");

pub const Args = struct {
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

pub const OutputLocation = enum {
    @"Current working directory",
    @"Parent of selected files",
};

pub const Options = struct {
    files: std.ArrayList([]const u8),
    output_name: []const u8,
    parse_odfs: bool,
};
