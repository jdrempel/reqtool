const std = @import("std");
const util = @import("util/root.zig");
const string = util.string;
const types = util.types;

const print = std.debug.print;
const StrArrayList = std.ArrayList([]const u8);

const stripSpaces = " \r\n\t";
const stripBrackets = "[]";
const stripQuotes = "\'\"";

const classNdl = "ODF";
const effectNdl = "Effect";
const modelNdl = "Geometry";
const textureNdl = "Texture";

const classStr = "class";
const configStr = "config";
const modelStr = "model";
const textureStr = "texture";

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
        const reader = file.reader();

        var dependencies = std.StringHashMap(StrArrayList).init(self.allocator);
        var currentSection: []u8 = undefined;
        var maybeLine = try reader.readUntilDelimiterOrEofAlloc(self.allocator, '\n', 2048);
        while (maybeLine) |line| : (maybeLine = try reader.readUntilDelimiterOrEofAlloc(self.allocator, '\n', 2048)) {
            var keyValuePair = std.mem.splitScalar(u8, line, '=');
            const key = std.mem.trim(u8, keyValuePair.first(), stripSpaces);
            if (std.mem.startsWith(u8, key, "[")) {
                currentSection = try self.allocator.dupe(u8, std.mem.trim(u8, key, stripBrackets));
                continue;
            }

            // Ignore the stuff in GameObjectClass or InstanceProperties
            if (std.mem.eql(u8, currentSection, "GameObjectClass") or std.mem.eql(u8, currentSection, "InstanceProperties")) continue;

            // If there somehow isn't anything after the '=', skip this line
            if (!types.optArrayToBool(u8, keyValuePair.peek())) continue;

            // Figure out which db section this entry belongs under (AFAIK it can be class, config, model, or texture)
            var destination: []u8 = undefined;
            if (string.stringContains(key, classNdl)) {
                destination = try self.allocator.dupe(u8, classStr);
            } else if (string.stringContains(key, effectNdl)) {
                destination = try self.allocator.dupe(u8, configStr);
            } else if (string.stringContains(key, modelNdl)) {
                destination = try self.allocator.dupe(u8, modelStr);
            } else if (string.stringContains(key, textureNdl)) {
                destination = try self.allocator.dupe(u8, textureStr);
            } else continue;

            const valueRaw = std.mem.trim(u8, keyValuePair.next().?, stripSpaces ++ stripQuotes);
            if (valueRaw.len == 0) continue;

            var valueIter = std.mem.splitScalar(u8, valueRaw, ' ');
            const value = valueIter.first();

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
