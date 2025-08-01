// TODO: allow mapping a command over each file

pub fn main() !void {
    var debug_alloc: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_alloc.deinit();
    const gpa = debug_alloc.allocator();

    var args = try std.process.argsWithAllocator(gpa);
    defer args.deinit();
    _ = args.skip();
    const input_path = args.next() orelse usage("missing input path");
    const output_dir_path = args.next() orelse usage("missing input path prefix");
    const index_file_path = args.next() orelse usage("missing output path");
    const options_json = args.next() orelse usage("missing options");
    if (args.skip()) usage("too many arguments");

    const options_parsed = try std.json.parseFromSlice(Options, gpa, options_json, .{});
    defer options_parsed.deinit();
    const opts = options_parsed.value;

    // Collects a list of all file and directory paths in the input tree.
    // Directory names end with a trailing slash.
    const Entry = struct {
        path: []const u8,
        children: usize,
        depth: usize,
    };
    var entries: std.ArrayListUnmanaged(Entry) = .{};
    var entry_arena: std.heap.ArenaAllocator = .init(gpa);
    defer {
        entries.deinit(gpa);
        entry_arena.deinit();
    }

    {
        var stack: std.ArrayListUnmanaged(struct {
            iter: std.fs.Dir.Iterator,
            out: std.fs.Dir,
            entry: usize,

            pub fn deinit(frame: *@This()) void {
                frame.iter.dir.close();
                frame.out.close();
            }
        }) = .empty;
        defer {
            for (stack.items) |*frame| {
                frame.deinit();
            }
            stack.deinit(gpa);
        }

        // Open input/output dirs
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

            try stack.append(gpa, .{
                .iter = in.iterateAssumeFirstIteration(),
                .out = out,
                .entry = entries.items.len,
            });
            try entries.append(gpa, .{ .path = "", .depth = 0, .children = 0 });
        }

        // Walk and copy input tree
        while (stack.items.len > 0) {
            const frame = &stack.items[stack.items.len - 1];
            const entry = try frame.iter.next() orelse {
                frame.deinit();
                stack.items.len -= 1;
                continue;
            };

            const parent = &entries.items[frame.entry];
            parent.children += 1;
            const path = try std.mem.concat(entry_arena.allocator(), u8, &.{
                parent.path,
                entry.name,
                if (entry.kind == .directory) "/" else "",
            });
            try entries.append(gpa, .{
                .path = path,
                .depth = stack.items.len - 1,
                .children = 0,
            });

            if (entry.kind == .directory) {
                var in = try frame.iter.dir.openDir(entry.name, .{ .iterate = true });
                errdefer in.close();

                var out = try frame.out.makeOpenPath(entry.name, .{});
                errdefer out.close();

                try stack.append(gpa, .{
                    .iter = in.iterateAssumeFirstIteration(),
                    .out = out,
                    .entry = entries.items.len - 1,
                });
            } else {
                try frame.iter.dir.copyFile(entry.name, frame.out, entry.name, .{});
            }
        }
    }

    // Generate index file
    var source_data = if (writergate)
        std.Io.Writer.Allocating.init(gpa)
    else
        std.ArrayList(u8).init(gpa);
    defer source_data.deinit();
    var source = if (writergate)
        &source_data.writer
    else
        source_data.writer();

    try source.writeAll("// This file was autogenerated by assetpack\n");

    if (opts.asset_namespace) |ns| {
        try source.print(fmt.pub_const ++ " = struct {{", .{
            std.zig.fmtId(ns),
        });
    }

    {
        // Sort entries by path, with files before directories
        std.mem.sortUnstable(Entry, entries.items, {}, struct {
            fn less(_: void, a: Entry, b: Entry) bool {
                const a_is_dir = std.mem.endsWith(u8, a.path, "/");
                const b_is_dir = std.mem.endsWith(u8, b.path, "/");
                if (a_is_dir == b_is_dir) {
                    return std.mem.lessThan(u8, a.path, b.path);
                } else {
                    return b_is_dir;
                }
            }
        }.less);

        // Compute relative path
        const path_prefix = try std.fs.path.relative(
            gpa,
            std.fs.path.dirname(index_file_path) orelse ".",
            output_dir_path,
        );
        defer gpa.free(path_prefix);

        // Ensure we don't escape the module root
        if (std.mem.startsWith(u8, path_prefix, "../")) {
            std.log.err("output directory not a subdirectory of output module root", .{});
            return error.InvalidOutputDirectory;
        }
        std.debug.assert(std.mem.indexOf(u8, path_prefix, "/../") == null);

        var prev_path: []const u8 = "";
        std.debug.assert(entries.items[0].path.len == 0); // root is always first
        for (entries.items[1..]) |entry| {
            if (std.mem.endsWith(u8, entry.path, "/")) {
                break; // dirs come after files, so we're done
            }

            const byte_diff = std.mem.indexOfDiff(u8, entry.path, prev_path).?;
            const diff = if (entry.path[byte_diff] == '/')
                byte_diff
            else if (std.mem.lastIndexOfScalar(u8, entry.path[0..byte_diff], '/')) |sep|
                sep + 1
            else
                0;

            // Close old dir namespaces
            for (0..std.mem.count(u8, prev_path[diff..], "/")) |_| {
                try source.writeAll("};");
            }

            // Open new dir namespaces
            var pos = diff;
            while (std.mem.indexOfScalarPos(u8, entry.path, pos, '/')) |sep| : (pos = sep + 1) {
                try source.print(fmt.pub_const ++ " = struct {{", .{
                    std.zig.fmtId(entry.path[pos..sep]),
                });
            }

            // Write file
            try source.print(fmt.pub_const ++ " = " ++ fmt.embedfile, .{
                std.zig.fmtId(entry.path[pos..]),
                fmt.zigString(path_prefix),
                fmt.zigString(entry.path),
            });

            prev_path = entry.path;
        }

        // Close remaining dir namespaces
        for (0..std.mem.count(u8, prev_path, "/")) |_| {
            try source.writeAll("};");
        }
    }

    // Close asset namespace
    if (opts.asset_namespace != null) {
        try source.writeAll("};");
    }

    // Write additional namespaces
    const asset_namespace = if (opts.asset_namespace) |ns|
        try std.fmt.allocPrint(gpa, fmt.f, .{std.zig.fmtId(ns)})
    else
        try gpa.dupe(u8, "@This()");
    defer gpa.free(asset_namespace);

    if (opts.root_dir_decl) |ns| {
        // Convert to breadth-first traversal order
        std.mem.sort(Entry, entries.items, {}, struct {
            fn less(_: void, a: Entry, b: Entry) bool {
                return a.depth < b.depth;
            }
        }.less);

        std.debug.assert(entries.items[0].path.len == 0); // root
        try source.print(
            fmt.pub_const ++
                \\: @import("assetpack").Dir = .{{
                \\.offset = 0,
                \\.children = {},
                \\.map = .{{ .entries = &.{{
            ,
            .{ std.zig.fmtId(ns), entries.items[0].children },
        );

        // Write path map
        var start: usize = entries.items[0].children;
        for (entries.items[1..]) |entry| {
            const name = std.fs.path.basenamePosix(entry.path);
            if (entry.path.len == 0 or std.mem.endsWith(u8, entry.path, "/")) {
                try source.print("\n.dir(\"" ++ fmt.f ++ "\", {}, {}),", .{
                    fmt.zigString(name),
                    start,
                    entry.children,
                });
                start += entry.children;
            } else {
                try source.print("\n.file(\"" ++ fmt.f ++ "\", {s}", .{
                    fmt.zigString(name),
                    asset_namespace,
                });
                var it = std.mem.splitScalar(u8, entry.path, '/');
                while (it.next()) |el| {
                    try source.print("." ++ fmt.f, .{std.zig.fmtId(el)});
                }
                try source.writeAll("),");
            }
        }
        try source.writeAll("\n} }, };");
    }

    if (opts.expose_types) {
        try source.writeAll(
            \\
            \\pub const Dir = @import("assetpack").Dir;
            \\
        );
    }

    // Write index file
    const source_slice = try source_data.toOwnedSliceSentinel(0);
    defer gpa.free(source_slice);
    var ast: std.zig.Ast = try .parse(gpa, source_slice, .zig);
    defer ast.deinit(gpa);

    if (ast.errors.len > 0) {
        try std.zig.printAstErrorsToStderr(gpa, ast, "<generated>", .auto);
        var lines = std.mem.splitScalar(u8, source_slice, '\n');
        var line_num: usize = 1;
        while (lines.next()) |line| : (line_num += 1) {
            std.debug.print("{: >4}: {s}\n", .{ line_num, line });
        }
        std.debug.print("\n", .{});
        std.process.fatal("Generated invalid code. This is a bug in assetpack.", .{});
    }

    if (writergate) {
        var out_file = try std.fs.cwd().createFile(index_file_path, .{});
        var out_buf: [4096]u8 = undefined;
        var out = out_file.writer(&out_buf);
        try ast.render(gpa, &out.interface, .{});
        try out.interface.flush();
    } else {
        const rendered = try ast.render(gpa);
        defer gpa.free(rendered);
        try std.fs.cwd().writeFile(.{
            .sub_path = index_file_path,
            .data = rendered,
        });
    }
}

fn usage(err_msg: []const u8) noreturn {
    std.debug.print("Usage: assetpack INPUT_DIR OUTPUT_DIR OUTPUT_ZIG_FILE OPTIONS_JSON", .{});
    std.log.err("{s}", .{err_msg});
    std.process.exit(1);
}

// Compatibility across writergate
const writergate = @TypeOf(std.io.Writer) == type;

const fmt = struct {
    const f = if (writergate) "{f}" else "{}";
    const pub_const = "\npub const " ++ f;
    const embedfile = "@embedFile(\"" ++ f ++ "/" ++ f ++ "\");";

    const zigString = if (writergate)
        std.zig.fmtString
    else
        std.zig.fmtEscapes;
};

const std = @import("std");
const Options = @import("Options.zig");
