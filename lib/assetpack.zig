/// Retrieve an asset by comptime-known file path.
pub fn getFile(
    comptime assets: type,
    comptime path: []const u8,
) GetFileArrayType(assets, path) {
    return comptime getFileSlice(assets, path)[0..];
}
pub fn GetFileArrayType(comptime assets: type, comptime path: []const u8) type {
    const slice = getFileSlice(assets, path);
    return *const [slice.len:0]u8;
}

fn getFileSlice(comptime assets: type, comptime path: []const u8) [:0]const u8 {
    comptime {
        if (!std.mem.startsWith(u8, path, "/")) {
            @compileError("Asset paths must be absolute, but '" ++ path ++ "' is relative");
        }

        var it = std.mem.tokenizeScalar(u8, path, '/');
        var container: type = assets;
        var component = it.next() orelse {
            @compileError("Asset path '" ++ path ++ "' is a directory");
        };
        while (it.next()) |next_component| {
            defer component = next_component;

            if (!@hasDecl(container, component)) {
                @compileError("Asset path '" ++ path ++ "' attempts to access directory '" ++ component ++ "' which does not exist");
            }

            const next_container = @field(container, component);
            if (@TypeOf(next_container) != type) {
                @compileError("Asset path '" ++ path ++ "' attempts to access file '" ++ component ++ "' as a directory");
            }

            container = next_container;
        }

        if (!@hasDecl(container, component)) {
            @compileError("Asset path '" ++ path ++ "' does not exist");
        }
        const file = @field(container, component);
        if (@TypeOf(file) == type) {
            @compileError("Asset path '" ++ path ++ "' is a directory");
        }

        return file;
    }
}

pub fn Getters(comptime assets: type) type {
    return struct {
        pub fn file(comptime path: []const u8) GetFileArrayType(assets, path) {
            return getFile(assets, path);
        }
    };
}

const std = @import("std");
