pub fn main() !void {
    const stdout = if (writergate)
        std.fs.File.stdout()
    else
        std.io.getStdOut();

    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = if (writergate)
        stdout.writerStreaming(&stdout_buf)
    else
        std.io.bufferedWriter(stdout.writer());

    const out: Writer = if (writergate)
        &stdout_writer.interface
    else
        stdout_writer.writer().any();

    try out.writeAll(".\n");
    var indent: std.BoundedArray(u8, 128) = .{};
    try writeTree(assets, &indent, out);
    if (writergate) {
        try out.flush();
    } else {
        try stdout_writer.flush();
    }
}

fn writeTree(tree: type, indent: *std.BoundedArray(u8, 128), out: Writer) !void {
    const direct_indent = "|- ";
    const last_direct_indent = "`- ";
    const nested_indent = "|  ";
    const last_nested_indent = "   ";

    const indent_len = direct_indent.len;
    std.debug.assert(indent_len == last_direct_indent.len);
    std.debug.assert(indent_len == nested_indent.len);
    std.debug.assert(indent_len == last_nested_indent.len);

    const indent_start = indent.len;
    try indent.resize(indent.len + indent_len);
    defer indent.len = indent_start;
    const this_indent = indent.buffer[indent_start..indent.len];

    const decls = @typeInfo(tree).@"struct".decls;
    inline for (decls, 0..) |decl, i| {
        if (i < decls.len - 1) {
            @memcpy(this_indent, direct_indent);
        } else {
            @memcpy(this_indent, last_direct_indent);
        }
        try out.writeAll(indent.constSlice());

        const child = @field(tree, decl.name);
        switch (@TypeOf(child)) {
            type => {
                try out.print("{s}\n", .{decl.name});

                if (i < decls.len - 1) {
                    @memcpy(this_indent, nested_indent);
                } else {
                    @memcpy(this_indent, last_nested_indent);
                }

                try writeTree(child, indent, out);
            },
            else => if (writergate) {
                try out.print("{s}  '{f}'\n", .{ decl.name, std.zig.fmtChar(child) });
            } else {
                try out.print("{s}  '{'}'\n", .{ decl.name, std.zig.fmtEscapes(child) });
            },
        }
    }
}

// Compatibility across writergate
const writergate = @TypeOf(std.io.Writer) == type;
const Writer = if (writergate) *std.io.Writer else std.io.AnyWriter;

const std = @import("std");
const assets = @import("assets");
