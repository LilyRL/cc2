const std = @import("std");
const Io = std.Io;

const lib = @import("cc2");

pub fn main(init: std.process.Init) !u8 {
    const gpa = init.gpa;
    const arena = init.arena;
    const io = init.io;

    var out_buffer: [4096]u8 = undefined;
    var buffered_out = Io.File.stdout().writer(io, &out_buffer);
    const stdout = &buffered_out.interface;
    defer stdout.flush() catch {};

    var err_buffer: [1024]u8 = undefined;
    var buffered_err = Io.File.stderr().writer(io, &err_buffer);
    const stderr = &buffered_err.interface;
    defer stderr.flush() catch {};

    var file_buffer: [4096]u8 = undefined;

    const args = lib.CompilerArgs.parse(init.minimal.args, gpa, stdout, stderr) catch |e| {
        if (e == error.OutOfMemory) {
            stderr.print("out of memory\n", .{}) catch {};
        }
        return 1;
    };

    if (args.keep_intermediates) {
        Io.Dir.cwd().createDir(io, "output", .default_dir) catch |e| switch (e) {
            error.PathAlreadyExists => {},
            else => stderr.print("failed to create output directory: {}\n", .{e}) catch {},
        };
    }

    var state = lib.State.init(gpa, arena.allocator());
    defer state.deinit();

    const src = try preprocess_source(args.input_path, arena.allocator(), io, stderr);
    const file_id = try state.createFile(src, args.input_path);
    var tokens = state.lex(file_id) catch |e| switch (e) {
        error.Invalid => {
            for (state.diagnostics.diagnostics.items) |diagnostic| {
                try diagnostic.print(&state, stdout);
            }
            return 1;
        },
        else => {
            stderr.print("failed to lex file: {}\n", .{e}) catch {};
            return 1;
        },
    };
    defer tokens.deinit(gpa);

    if (args.keep_intermediates) {
        var output_file = try Io.Dir.cwd().createFile(io, args.tokens_path, .{});
        defer output_file.close(io);
        var output_writer = output_file.writer(io, &file_buffer);
        defer output_writer.interface.flush() catch {};

        for (tokens.items) |token| {
            try token.fmt(&output_writer.interface, &state);
            try output_writer.interface.writeAll("\n");
        }
    }

    if (args.lex_only) {
        for (tokens.items) |token| {
            try token.fmt(stdout, &state);
            try stdout.writeAll("\n");
        }
        return 0;
    }

    const program = lib.parse(tokens.items, file_id, &state) catch |e| switch (e) {
        error.Invalid => {
            for (state.diagnostics.diagnostics.items) |diagnostic| {
                try diagnostic.print(&state, stdout);
            }
            return 1;
        },
        else => {
            stderr.print("failed to parse file: {}\n", .{e}) catch {};
            return 1;
        },
    };

    const formatter = lib.ast.Formatter{ .state = state };
    try formatter.formatProgram(
        program,
        stdout,
    );

    return 0;
}

fn preprocess_source(input_path: []const u8, alloc: std.mem.Allocator, io: std.Io, stderr: *std.Io.Writer) ![]const u8 {
    const res = std.process.run(alloc, io, .{ .argv = &[_][]const u8{ "gcc", "-E", "-P", input_path } }) catch |e| {
        stderr.print("failed to run preprocessor: {}\n", .{e}) catch {};
        return error.PreprocessorFailed;
    };

    const is_success = switch (res.term) {
        .exited => |code| code == 0,
        else => false,
    };

    if (!is_success) {
        stderr.print("GCC preprocess step failed:\n{s}", .{res.stderr}) catch {};
        return error.PreprocessorFailed;
    }

    return res.stdout;
}
