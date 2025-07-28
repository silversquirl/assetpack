pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("assetpack", .{
        .root_source_file = b.path("lib/assetpack.zig"),
    });

    const exe = b.addExecutable(.{
        .name = "assetpack",
        .root_module = b.createModule(.{
            .root_source_file = b.path("packer/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);
}

pub fn pack(
    b: *std.Build,
    dir: std.Build.LazyPath,
    opts: Options,
) *std.Build.Module {
    const copy = b.addWriteFiles();
    const copied_dir = copy.addCopyDirectory(dir, "assets", .{});

    const dep = b.dependencyFromBuildZig(@This(), .{});
    const run = b.addRunArtifact(dep.artifact("assetpack"));
    run.addDirectoryArg(copied_dir);
    _ = run.addOutputDirectoryArg("assets");
    const index_file = run.addOutputFileArg("_assetpack_index.zig");

    const jsonStringify = if (@hasDecl(std.json, "Stringify"))
        std.json.Stringify.valueAlloc
    else
        std.json.stringifyAlloc;
    run.addArg(jsonStringify(b.allocator, opts, .{}) catch @panic("OOM"));

    return b.createModule(.{
        .root_source_file = index_file,
        .imports = &.{
            .{ .name = "assetpack", .module = dep.module("assetpack") },
        },
    });
}

const std = @import("std");
const Options = @import("packer/Options.zig");
