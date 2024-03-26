pub fn optArrayToBool(comptime T: type, optArray: ?[]const T) bool {
    const array: []const T = optArray orelse return false;
    return array.len != 0;
}
