// TODO: allow mapping a command over each file

pub fn main() !void {
    var debug_alloc: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_alloc.deinit();
    const allocator = debug_alloc.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    _ = args.skip();
    const input_path = args.next() orelse usage("missing input path");
    const output_dir_path = args.next() orelse usage("missing input path prefix");
    const index_file_path = args.next() orelse usage("missing output path");
    if (args.skip()) usage("too many arguments");

    var path_buf: std.ArrayListUnmanaged(u8) = .{};
    defer path_buf.deinit(allocator);

    var stack: std.ArrayListUnmanaged(struct {
        iter: std.fs.Dir.Iterator,
        out: std.fs.Dir,
        name_len: usize,

        pub fn deinit(frame: *@This()) void {
            frame.iter.dir.close();
            frame.out.close();
        }
    }) = .empty;
    defer {
        for (stack.items) |*frame| {
            frame.deinit();
        }
        stack.deinit(allocator);
    }

    {
        var in = std.fs.cwd().openDir(input_path, .{ .iterate = true }) catch |err| {
            std.log.err("unable to open input directory '{s}'", .{input_path});
            return err;
        };
        errdefer in.close();

        var out = std.fs.cwd().openDir(output_dir_path, .{}) catch |err| {
            std.log.err("unable to open output directory '{s}'", .{output_dir_path});
            return err;
        };
        errdefer out.close();

        {
            // Compute relative path
            const path_prefix = try std.fs.path.relative(
                allocator,
                std.fs.path.dirname(index_file_path) orelse ".",
                output_dir_path,
            );
            errdefer allocator.free(path_prefix);

            // Ensure we don't escape the module root
            if (std.mem.startsWith(u8, path_prefix, "../")) {
                std.log.err("output directory not a subdirectory of output module root", .{});
                return error.InvalidOutputDirectory;
            }
            std.debug.assert(std.mem.indexOf(u8, path_prefix, "/../") == null);

            // Convert to posix
            std.debug.assert(path_buf.capacity == 0);
            path_buf = .fromOwnedSlice(path_prefix);
            try path_buf.append(allocator, '/');
        }

        try stack.append(allocator, .{
            .iter = in.iterateAssumeFirstIteration(),
            .out = out,
            .name_len = path_buf.items.len,
        });
    }

    const outfile = try std.fs.cwd().createFile(index_file_path, .{});
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
            if (stack.items.len > 1) {
                // Close struct
                const indent = (stack.items.len - 2) * 4;
                if (writergate) {
                    try out_writer.splatByteAll(' ', indent);
                } else {
                    try out_writer.writeByteNTimes(' ', indent);
                }
                try out_writer.writeAll("};\n");
            }
            path_buf.items.len -= frame.name_len;
            frame.deinit();
            stack.items.len -= 1;
            continue;
        };

        const indent = (stack.items.len - 1) * 4;

        if (entry.kind == .directory) {
            var in = try frame.iter.dir.openDir(entry.name, .{ .iterate = true });
            errdefer in.close();

            var out = try frame.out.makeOpenPath(entry.name, .{});
            errdefer out.close();

            try path_buf.appendSlice(allocator, entry.name);
            try path_buf.append(allocator, '/');

            if (writergate) {
                try out_writer.splatByteAll(' ', indent);
            } else {
                try out_writer.writeByteNTimes(' ', indent);
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
                .name_len = entry.name.len + 1,
            });
        } else {
            try frame.iter.dir.copyFile(entry.name, frame.out, entry.name, .{});

            if (writergate) {
                try out_writer.splatByteAll(' ', indent);
            } else {
                try out_writer.writeByteNTimes(' ', indent);
            }

            if (writergate) {
                try out_writer.print("pub const {f} = @embedFile(\"{f}{f}\");\n", .{
                    std.zig.fmtId(entry.name),
                    std.zig.fmtString(path_buf.items),
                    std.zig.fmtString(entry.name),
                });
            } else {
                try out_writer.print("pub const {} = @embedFile(\"{}{}\");\n", .{
                    std.zig.fmtId(entry.name),
                    std.zig.fmtEscapes(path_buf.items),
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

fn usage(err_msg: []const u8) noreturn {
    std.debug.print("Usage: assetpack INPUT_DIR OUTPUT_ZIG_FILE\n", .{});
    std.log.err("{s}", .{err_msg});
    std.process.exit(1);
}

// Compatibility across writergate
const writergate = @TypeOf(std.io.Writer) == type;

const std = @import("std");
