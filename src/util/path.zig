const std = @import("std");
const testing = std.testing;
const types = @import("types.zig");

pub fn stem(path: []const u8, allocator: std.mem.Allocator) std.fmt.AllocPrintError![]const u8 {
    var components = std.mem.splitScalar(u8, path, '/');
    var latestComponent = components.first();
    while (types.optArrayToBool(u8, components.peek())) {
        latestComponent = components.next().?;
    }
    var pieces = std.mem.splitScalar(u8, latestComponent, '.');
    var latestPiece = pieces.first();
    while (pieces.next()) |piece| {
        if (!types.optArrayToBool(u8, pieces.peek())) break;
        latestPiece = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ latestPiece, piece });
    }
    return latestPiece;
}

test "path stem" {
    try testing.expectEqualStrings("baz", try stem("/foo/bar/baz"));
    try testing.expectEqualStrings("baz", try stem("/foo/bar/baz/"));
    try testing.expectEqualStrings("baz", try stem("/foo/bar/baz."));
    try testing.expectEqualStrings("baz", try stem("/foo/bar/baz./"));
    try testing.expectEqualStrings("baz", try stem("/foo/bar/baz.c"));
    try testing.expectEqualStrings("baz", try stem("/foo/bar/baz.c/"));
    try testing.expectEqualStrings("baz", try stem("/foo/bar/baz.c."));
    try testing.expectEqualStrings("baz", try stem("/foo/bar/baz.c./"));
}

pub fn extension(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const raw_extension = std.fs.path.extension(path);
    const lower_extension = try std.ascii.allocLowerString(allocator, raw_extension);
    return std.mem.trimLeft(u8, lower_extension, ".");
}
