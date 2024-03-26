const std = @import("std");
const testing = std.testing;

fn optArrayToBool(comptime T: type, optArray: ?[]const T) bool {
    const array: []const T = optArray orelse return false;
    return array.len != 0;
}

pub fn stem(path: []const u8, allocator: std.mem.Allocator) std.fmt.AllocPrintError![]const u8 {
    var components = std.mem.splitScalar(u8, path, '/');
    var latestComponent = components.first();
    while (optArrayToBool(u8, components.peek())) {
        latestComponent = components.next().?;
    }
    var pieces = std.mem.splitScalar(u8, latestComponent, '.');
    var latestPiece = pieces.first();
    while (pieces.next()) |piece| {
        if (!optArrayToBool(u8, pieces.peek())) break;
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
