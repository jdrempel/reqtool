const std = @import("std");
const util = @import("util/root.zig");
const string = util.string;
const types = util.types;

const print = std.debug.print;
const StrArrayList = std.ArrayList([]const u8);

const spaces = " \r\n\t";
const brackets = "[]";
const quotes = "\'\"";

const class_ndl = "ODF";
const effect_ndl = "Effect";
const model_ndl = "Geometry";
const texture_ndl = "Texture";

const class_str = "class";
const config_str = "config";
const model_str = "model";
const texture_str = "texture";

pub const OdfParser = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    pub fn parse(self: *Self, path: []const u8) !std.StringHashMap(StrArrayList) {
        const file = try std.fs.openFileAbsolute(path, .{});
        defer file.close();
        const reader = file.reader();

        var dependencies = std.StringHashMap(StrArrayList).init(self.allocator);
        var current_section: []u8 = undefined;
        var maybe_line = try reader.readUntilDelimiterOrEofAlloc(self.allocator, '\n', 2048);
        while (maybe_line) |line| : (maybe_line = try reader.readUntilDelimiterOrEofAlloc(self.allocator, '\n', 2048)) {
            // Split the line into key and value
            var key_value = std.mem.splitScalar(u8, line, '=');
            const key = std.mem.trim(u8, key_value.first(), spaces);
            if (std.mem.startsWith(u8, key, "[")) {
                current_section = try self.allocator.dupe(u8, std.mem.trim(u8, key, brackets));
                continue;
            }

            // Ignore the stuff in GameObjectClass or InstanceProperties
            if (std.mem.eql(u8, current_section, "GameObjectClass") or
                std.mem.eql(u8, current_section, "InstanceProperties"))
                continue;

            // If there somehow isn't anything after the '=', skip this line
            if (!types.optArrayToBool(u8, key_value.peek())) continue;

            // Figure out which db section this entry belongs under (AFAIK it can be class, config, model, or texture)
            var destination: []u8 = undefined;
            if (string.stringContains(key, class_ndl)) {
                destination = try self.allocator.dupe(u8, class_str);
            } else if (string.stringContains(key, effect_ndl)) {
                destination = try self.allocator.dupe(u8, config_str);
            } else if (string.stringContains(key, model_ndl)) {
                destination = try self.allocator.dupe(u8, model_str);
            } else if (string.stringContains(key, texture_ndl)) {
                destination = try self.allocator.dupe(u8, texture_str);
            } else continue;

            // Remove extra spaces and quotes, and if there's nothing left, skip this line
            const raw_value = std.mem.trim(u8, key_value.next().?, spaces ++ quotes);
            if (raw_value.len == 0) continue;

            // If the value is a group of items, only take the first one
            var value_iter = std.mem.splitScalar(u8, raw_value, ' ');
            const value = value_iter.first();

            // Add the value under the list for the appropriate section
            if (dependencies.getPtr(destination)) |section| {
                try section.*.append(value);
            } else {
                var section = StrArrayList.init(self.allocator);
                try section.append(value);
                try dependencies.put(destination, section);
            }
        }

        return dependencies;
    }
};
