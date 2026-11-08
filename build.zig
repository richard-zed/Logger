const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("Logger", .{
        .root_source_file = b.path("src/Logger.zig"),
        .target = target,
        .optimize = optimize,
    });

    const strfz= b.dependency("strfz", .{ .target = target, .optimize = optimize});
    mod.addImport("strfz", strfz.module("strfz"));

    const tests = b.addTest(.{ .root_module = mod });
    const run = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run the test suite");
    test_step.dependOn(&run.step);
}
