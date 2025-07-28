pub const Dir = struct {
    map: PathMap,
    offset: usize,
    children: usize,

    /// Retrieve an asset by file path.
    pub inline fn file(d: Dir, path: []const u8) error{ FileNotFound, IsDir }![:0]const u8 {
        switch ((try d.entry(path)).data) {
            .dir => return error.IsDir,
            .file => |result| return result,
        }
    }

    /// Get a subdirectory by path.
    pub inline fn dir(d: Dir, path: []const u8) error{ FileNotFound, NotDir }!Dir {
        switch ((try d.entry(path)).data) {
            .dir => |result| return result,
            .file => return error.NotDir,
        }
    }

    pub inline fn entry(d: Dir, path: []const u8) error{FileNotFound}!Dir.Entry {
        const range: PathMap.Range = .{
            .start = d.offset,
            .len = d.children,
        };
        const ent = if (isComptimeKnown(.{ d, path }))
            comptime try d.map.getEntry(range, path)
        else
            try d.map.getEntry(range, path);
        return ent.toDirEntry(d.map);
    }

    pub inline fn iterate(d: Dir) Iterator {
        return .{
            .map = d.map,
            .index = d.offset,
            .end = d.offset + d.children,
        };
    }

    pub const Entry = struct {
        name: []const u8,
        data: union(enum) {
            dir: Dir,
            file: [:0]const u8,
        },
    };

    pub const Iterator = struct {
        map: PathMap,
        index: usize,
        end: usize,

        /// Returns the number of remaining entries in the iterator.
        pub fn count(it: @This()) usize {
            return it.end - it.index;
        }

        pub fn empty(it: @This()) bool {
            return it.index >= it.end;
        }

        pub fn next(it: *@This()) ?Dir.Entry {
            const ent = it.peek() orelse return null;
            it.index += 1;
            return ent;
        }

        pub fn peek(it: *@This()) ?Dir.Entry {
            if (it.empty()) return null;
            return it.map.entries[it.index].toDirEntry(it.map);
        }
    };
};

inline fn isComptimeKnown(value: anytype) bool {
    return @typeInfo(@TypeOf(.{value})).@"struct".fields[0].is_comptime;
}
inline fn comptimeOrNull(value: anytype) ?@TypeOf(value) {
    return if (isComptimeKnown(value)) value else null;
}

const PathMap = struct {
    entries: [*]const Entry,

    const Range = struct { start: usize, len: usize };
    const Entry = struct {
        tagged_name: [*:0]const u8,
        data: Data,
        const Data = union {
            file: [:0]const u8,
            dir: Range,
        };
        const Kind = enum { file, dir };

        fn toDirEntry(entry: Entry, map: PathMap) Dir.Entry {
            return .{
                .name = entry.name(),
                .data = switch (entry.kind()) {
                    .file => .{ .file = entry.data.file },
                    .dir => .{ .dir = .{
                        .map = map,
                        .offset = entry.data.dir.start,
                        .children = entry.data.dir.len,
                    } },
                },
            };
        }

        fn kind(entry: Entry) Kind {
            return @enumFromInt(entry.tagged_name[0]);
        }
        fn name(entry: Entry) []const u8 {
            return std.mem.span(entry.tagged_name[1..]);
        }

        pub fn dir(comptime dir_name: [:0]const u8, offset: usize, children: usize) Entry {
            comptime std.debug.assert(std.mem.indexOfScalar(u8, dir_name, '/') == null);
            return .{
                .tagged_name = .{@intFromEnum(Kind.dir)} ++ dir_name,
                .data = .{ .dir = .{ .start = offset, .len = children } },
            };
        }

        pub fn file(comptime file_name: [:0]const u8, bytes: [:0]const u8) Entry {
            comptime std.debug.assert(std.mem.indexOfScalar(u8, file_name, '/') == null);
            return .{
                .tagged_name = .{@intFromEnum(Kind.file)} ++ file_name,
                .data = .{ .file = bytes },
            };
        }
    };

    fn getEntry(map: PathMap, root_range: Range, path: []const u8) !Entry {
        std.debug.assert(!std.mem.startsWith(u8, path, "/")); // path must be relative

        var range = root_range;
        var path_offset: usize = 0;
        while (true) {
            const end = if (std.mem.indexOfScalarPos(u8, path, path_offset, '/')) |sep| sep else path.len;
            const index = range.start + (std.sort.binarySearch(
                Entry,
                map.entries[range.start..][0..range.len],
                @as([]const u8, path[path_offset..end]),
                searchCompare,
            ) orelse return error.FileNotFound);

            const entry = map.entries[index];
            if (end >= path.len) {
                return entry;
            }

            switch (entry.kind()) {
                .dir => {
                    range = entry.data.dir;
                    path_offset = end + 1;
                },
                .file => return error.FileNotFound,
            }
        }
    }

    fn searchCompare(target: []const u8, entry: Entry) std.math.Order {
        return std.mem.order(u8, target, entry.name());
    }
};

const std = @import("std");
