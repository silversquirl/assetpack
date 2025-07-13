pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "assetpack",
        .root_module = b.createModule(.{
            .root_source_file = b.path("assetpack.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);
}

pub fn pack(b: *std.Build, dir: std.Build.LazyPath) *std.Build.Module {
    const dep = b.dependencyFromBuildZig(@This(), .{});
    const run = b.addRunArtifact(dep.artifact("assetpack"));
    run.addDirectoryArg(dir);
    const index_file = run.addOutputFileArg("_assetpack_index.zig");
    return b.createModule(.{ .root_source_file = index_file });
}

const std = @import("std");
