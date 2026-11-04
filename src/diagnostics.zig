const std = @import("std");
const lib = @import("root.zig");
const Span = lib.Span;
const ansi = lib.ansi;

const Diagnostic = @This();

pub const Store = struct {
    diagnostics: std.ArrayList(Diagnostic),
    gpa: std.mem.Allocator,

    pub fn init(gpa: std.mem.Allocator) Store {
        return .{
            .diagnostics = std.ArrayList(Diagnostic).empty,
            .gpa = gpa,
        };
    }

    pub fn add(self: *Store, diagnostic: Diagnostic) !void {
        try self.diagnostics.append(self.gpa, diagnostic);
    }

    pub fn addMessage(self: *Store, stage: Diagnostic.Stage, message: []const u8, span: Span) !void {
        const diagnostic = Diagnostic{
            .stage = stage,
            .message = message,
            .labels = &[_]Diagnostic.Label{},
            .span = span,
        };
        try self.add(diagnostic);
    }

    pub fn deinit(self: *Store) void {
        self.diagnostics.deinit(self.gpa);
    }
};

stage: Stage,
span: Span,
message: []const u8,
labels: []const Label,

pub const Stage = enum { lex, parse, resolve, typecheck, const_eval, codegen };

const Label = struct {
    span: Span,
    message: []const u8,
};

// returns the index of the last entry <= needle
fn binarySearch(items: []const usize, needle: usize) usize {
    if (items.len == 0) return 0;

    var min: usize = 0;
    var max: usize = items.len - 1;
    var result: usize = 0;

    while (min <= max) {
        const mid = min + (max - min) / 2;

        if (items[mid] <= needle) {
            result = mid;
            min = mid + 1;
        } else if (mid == 0) {
            break;
        } else {
            max = mid - 1;
        }
    }

    return result;
}

fn lastCharOfLine(file: *const lib.File, line_index: usize) usize {
    if (line_index + 1 < file.linemap.items.len) {
        return file.linemap.items[line_index + 1] - 1;
    } else {
        return file.source.len - 1;
    }
}

fn firstCharOfLine(file: *const lib.File, line_index: usize) usize {
    if (file.linemap.items.len == 0) {
        return 0;
    } else {
        return file.linemap.items[line_index];
    }
}

fn printSpanSource(out: *std.Io.Writer, span: Span, file: ?lib.File) !void {
    if (file) |f| {
        const start = @min(span.start, f.source.len);
        const end = start + @min(span.end -| start, f.source.len - start);

        const start_line = binarySearch(f.linemap.items, start);
        const end_line = @max(binarySearch(f.linemap.items, end), start_line);

        const start_line_first_char = firstCharOfLine(&f, start_line);
        const start_line_last_char = lastCharOfLine(&f, start_line);
        const end_line_first_char = firstCharOfLine(&f, end_line);
        const end_line_last_char = lastCharOfLine(&f, end_line);

        try out.print("    --> {s}:{d}:{d}\n", .{ f.name, start_line + 1, start - start_line_first_char });
        try out.print("{d: >4} |  {s}{s}{s}", .{ start_line + 1, f.source[start_line_first_char..start], ansi.fg.underline.red, f.source[start..@max(start, @min(start_line_last_char, end))] });

        if (end_line > start_line + 1) {
            for (start_line + 1..end_line) |i| {
                const line_first_char = f.linemap.items[i];
                const line_last_char = lastCharOfLine(&f, i);
                try out.print("{d:0>4} |  {s}\n", .{ i + 1, f.source[line_first_char..line_last_char] });
            }
        }

        if (end_line != start_line) {
            try out.print("{d:0>4} |  {s}{s}{s}", .{ end_line, f.source[end_line_first_char..end], ansi.reset, f.source[end..end_line_last_char] });
        } else {
            try out.print("{s}{s}", .{ ansi.reset, f.source[end..end_line_last_char] });
        }
    } else {
        try out.writeAll("Could not load source for this file");
    }
}

pub fn print(self: *const Diagnostic, state: *const lib.State, out: *std.Io.Writer) !void {
    try out.writeAll(ansi.fg.bold.red);

    try out.writeAll(switch (self.stage) {
        .lex => "error(lexing): ",
        .parse => "error(parsing): ",
        .resolve => "error(resolving): ",
        .typecheck => "error(typechecking): ",
        .const_eval => "error(const evaluation): ",
        .codegen => "error(code generation): ",
    });

    try out.writeAll(ansi.fg.high_intensity.bold.white);
    try out.writeAll(self.message);
    try out.writeAll("\n");
    try out.writeAll(ansi.reset);

    const file = state.files.get(self.span.file_id);
    try printSpanSource(out, self.span, file);
    try out.writeAll("\n\n");
}

test "binarySearch" {
    const Expectation = struct {
        items: []const usize,
        needle: usize,
        expected: usize,
    };

    const expectations = [_]Expectation{
        .{ .items = &[5]usize{ 1, 2, 3, 4, 5 }, .needle = 3, .expected = 2 },
        .{ .items = &[5]usize{ 1, 2, 3, 4, 5 }, .needle = 6, .expected = 4 },
        .{ .items = &[5]usize{ 1, 2, 3, 4, 5 }, .needle = 0, .expected = 0 },
        .{ .items = &[5]usize{ 1, 2, 3, 4, 5 }, .needle = 2, .expected = 1 },
        .{ .items = &[5]usize{ 1, 2, 3, 4, 5 }, .needle = 4, .expected = 3 },
        .{ .items = &[_]usize{ 0, 10, 25, 31, 44, 88, 100 }, .needle = 20, .expected = 1 },
        .{ .items = &[_]usize{ 0, 10, 25, 31, 44, 88, 100 }, .needle = 30, .expected = 2 },
        .{ .items = &[_]usize{ 0, 10, 25, 31, 44, 88, 100 }, .needle = 31, .expected = 3 },
        .{ .items = &[_]usize{ 0, 10, 25, 31, 44, 88, 100 }, .needle = 50, .expected = 4 },
        .{ .items = &[_]usize{ 0, 10, 25, 31, 44, 88, 100 }, .needle = 150, .expected = 6 },
    };

    for (expectations) |e| {
        const result = binarySearch(e.items, e.needle);
        try std.testing.expectEqual(e.expected, result);
    }
}
