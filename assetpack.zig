// TODO: allow mapping a command over each file

pub fn main() !void {
    var debug_alloc: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_alloc.deinit();
    const allocator = debug_alloc.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    _ = args.skip();
    const input_path = args.next() orelse usage();
    const output_path = args.next() orelse usage();

    const output_filename = std.fs.path.basename(output_path);
    const output_dir_path = std.fs.path.dirname(output_path) orelse ".";

    var stack: std.ArrayListUnmanaged(struct {
        iter: std.fs.Dir.Iterator,
        out: std.fs.Dir,
        level: u32,
        path: []const u8,

        pub fn deinit(frame: *@This(), alloc: std.mem.Allocator) void {
            frame.iter.dir.close();
            frame.out.close();
            alloc.free(frame.path);
        }
    }) = .empty;
    defer {
        for (stack.items) |*frame| {
            frame.deinit(allocator);
        }
        stack.deinit(allocator);
    }

    {
        var in = std.fs.cwd().openDir(input_path, .{ .iterate = true }) catch |err| {
            std.log.err("unable to open input directory '{s}'", .{input_path});
            return err;
        };
        errdefer in.close();

        var out = std.fs.cwd().makeOpenPath(output_dir_path, .{}) catch |err| {
            std.log.err("unable to create output directory '{s}'", .{output_dir_path});
            return err;
        };
        errdefer out.close();

        const path = try allocator.dupe(u8, "./");
        errdefer allocator.free(path);

        try stack.append(allocator, .{
            .iter = in.iterateAssumeFirstIteration(),
            .out = out,
            .level = 0,
            .path = path,
        });
    }

    const outfile = try stack.getLast().out.createFile(output_filename, .{});
    defer outfile.close();
    var out_writer_buf: [4096]u8 = undefined;
    var out_writer_impl = if (writergate)
        outfile.writerStreaming(&out_writer_buf)
    else
        std.io.bufferedWriter(outfile.writer());

    const out_writer = if (writergate)
        &out_writer_impl.interface
    else
        out_writer_impl.writer();

    while (stack.items.len > 0) {
        const frame = &stack.items[stack.items.len - 1];
        const entry = try frame.iter.next() orelse {
            if (frame.level > 0) {
                if (writergate) {
                    try out_writer.splatByteAll(' ', (frame.level - 1) * 4);
                } else {
                    try out_writer.writeByteNTimes(' ', (frame.level - 1) * 4);
                }
                try out_writer.writeAll("};\n");
            }
            frame.deinit(allocator);
            stack.items.len -= 1;
            continue;
        };

        if (entry.kind == .directory) {
            var in = try frame.iter.dir.openDir(entry.name, .{ .iterate = true });
            errdefer in.close();

            var out = try frame.out.makeOpenPath(entry.name, .{});
            errdefer out.close();

            const path = try std.mem.concat(allocator, u8, &.{ frame.path, entry.name, "/" });
            errdefer allocator.free(path);

            if (writergate) {
                try out_writer.splatByteAll(' ', frame.level * 4);
            } else {
                try out_writer.writeByteNTimes(' ', frame.level * 4);
            }

            if (writergate) {
                try out_writer.print("pub const {f} = struct {{\n", .{
                    std.zig.fmtId(entry.name),
                });
            } else {
                try out_writer.print("pub const {} = struct {{\n", .{
                    std.zig.fmtId(entry.name),
                });
            }

            try stack.append(allocator, .{
                .iter = in.iterateAssumeFirstIteration(),
                .out = out,
                .level = frame.level + 1,
                .path = path,
            });
        } else {
            try frame.iter.dir.copyFile(entry.name, frame.out, entry.name, .{});

            if (writergate) {
                try out_writer.splatByteAll(' ', frame.level * 4);
            } else {
                try out_writer.writeByteNTimes(' ', frame.level * 4);
            }

            if (writergate) {
                try out_writer.print("pub const {f} = @embedFile(\"{f}{f}\");\n", .{
                    std.zig.fmtId(entry.name),
                    std.zig.fmtString(frame.path),
                    std.zig.fmtString(entry.name),
                });
            } else {
                try out_writer.print("pub const {} = @embedFile(\"{}{}\");\n", .{
                    std.zig.fmtId(entry.name),
                    std.zig.fmtEscapes(frame.path),
                    std.zig.fmtEscapes(entry.name),
                });
            }
        }
    }

    if (writergate) {
        try out_writer.flush();
    } else {
        try out_writer_impl.flush();
    }
}

fn usage() noreturn {
    std.debug.print("Usage: assetpack INPUT_DIR OUTPUT_ZIG_FILE\n", .{});
    std.process.exit(1);
}

// Compatibility across writergate
const writergate = @TypeOf(std.io.Writer) == type;

const std = @import("std");
