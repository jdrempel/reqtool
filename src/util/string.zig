const std = @import("std");

fn wrapString(string: []const u8, wrapper: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    return try std.mem.concat(allocator, u8, &[_][]const u8{ wrapper, string, wrapper });
}

pub fn quoteString(string: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    return try wrapString(string, "\"", allocator);
}

pub fn stringContains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.containsAtLeast(u8, haystack, 1, needle);
}
