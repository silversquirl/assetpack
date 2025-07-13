pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .imports = &.{
            .{ .name = "assets", .module = assetpack.pack(b, b.path("assets")) },
        },
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "example",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    b.step("run", "Run the example executable").dependOn(&run.step);
}

const std = @import("std");
const assetpack = @import("assetpack");
