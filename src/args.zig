const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");

const BinaryFormat = enum { mach, elf };
const WordSize = enum { u32, u64 };

const Self = @This();

input_path: []const u8,
output_path: []const u8,
assembly_path: []const u8,
ir_path: []const u8,
ir_extra_path: []const u8,
ast_path: []const u8,
tokens_path: []const u8,

lex_only: bool,
parse_only: bool,
validate_only: bool,
tacky_only: bool,
codegen_only: bool,
dont_assemble: bool,
keep_intermediates: bool,

no_bounds_checks: bool,
wrap_overflow: bool,
no_float_checks: bool,

generate_object: bool,

pub fn default() Self {
    return .{
        .input_path = "",
        .output_path = "",
        .assembly_path = "output/asm.s",
        .ir_path = "output/tacky",
        .ir_extra_path = "output/tacky_extra",
        .ast_path = "output/ast",
        .tokens_path = "output/tokens",

        .lex_only = false,
        .parse_only = false,
        .validate_only = false,
        .tacky_only = false,
        .codegen_only = false,
        .dont_assemble = false,
        .keep_intermediates = false,

        .no_bounds_checks = false,
        .wrap_overflow = false,
        .no_float_checks = false,

        .generate_object = true,
    };
}

const NamedArg = enum {
    help,
    output_path,
    lex_only,
    parse_only,
    validate_only,
    tacky_only,
    codegen_only,
    dont_assemble,
    keep_intermediates,
    generate_object,
    no_bounds_checks,
    wrap_overflow,
    no_float_checks,
};

const table = [_]struct { []const u8, NamedArg }{
    .{ "--help", .help },
    .{ "-h", .help },
    .{ "--output", .output_path },
    .{ "--lex", .lex_only },
    .{ "--parse", .parse_only },
    .{ "--validate", .validate_only },
    .{ "--tacky", .tacky_only },
    .{ "--codegen", .codegen_only },
    .{ "-S", .dont_assemble },
    .{ "--keep-intermediates", .keep_intermediates },
    .{ "-K", .keep_intermediates },
    .{ "-o", .generate_object },
    .{ "--object", .generate_object },
    .{ "--no-bounds-checks", .no_bounds_checks },
    .{ "--wrap-overflow", .wrap_overflow },
    .{ "--no-float-checks", .no_float_checks },
};

fn printHelp(writer: anytype) !void {
    try writer.writeAll("Usage: cc2 [options] <input file>\n");
    try writer.writeAll("Options:\n");
    try writer.writeAll("  --help, -h                     Show this help message\n");
    try writer.writeAll("  --output <file>                Specify output file path\n");
    try writer.writeAll("  --keep-intermediates, -K       Keep intermediate files\n");
    try writer.writeAll("  --lex                          Only lex the input file\n");
    try writer.writeAll("  --parse                        Only parse the input file\n");
    try writer.writeAll("  --validate                     Only validate the input file\n");
    try writer.writeAll("  --tacky                        Only tacky the input file\n");
    try writer.writeAll("  --codegen                      Only generate code for the input file\n");
    try writer.writeAll("  -S                             Do not assemble the generated code\n");
    try writer.writeAll("  -o, --object                   Generate object file instead of executable\n");
    try writer.writeAll("  --no-bounds-checks             Disable bounds checks\n");
    try writer.writeAll("  --wrap-overflow                Enable wrap-around on integer overflow\n");
    try writer.writeAll("  --no-float-checks              Disable floating-point checks\n");
}

pub fn parse(in: std.process.Args, gpa: std.mem.Allocator, stdout: *std.Io.Writer, stderr: *std.Io.Writer) error{ InvalidArgs, OutOfMemory, HelpRequested }!Self {
    var args = Self.default();
    var has_input_path = false;

    var iter = try in.iterateAllocator(gpa);
    defer iter.deinit();

    _ = iter.skip(); // skip program name

    while (iter.next()) |arg| {
        var action: ?NamedArg = null;
        inline for (table) |entry| {
            if (std.mem.eql(u8, arg, entry[0])) action = entry[1];
        }

        if (action == null) {
            if (arg[0] == '-') {
                stderr.print("evilc: unrecognized argument '{s}'\n", .{arg}) catch {};
                _ = Self.printHelp(stderr) catch {};
                return error.InvalidArgs;
            } else {
                args.input_path = arg;
                has_input_path = true;
            }
            continue;
        }

        switch (action.?) {
            .output_path => args.output_path = iter.next() orelse return error.InvalidArgs,
            .lex_only => args.lex_only = true,
            .parse_only => args.parse_only = true,
            .validate_only => args.validate_only = true,
            .tacky_only => args.tacky_only = true,
            .codegen_only => args.codegen_only = true,
            .dont_assemble => args.dont_assemble = true,
            .keep_intermediates => args.keep_intermediates = true,
            .generate_object => args.generate_object = true,
            .no_bounds_checks => args.no_bounds_checks = true,
            .wrap_overflow => args.wrap_overflow = true,
            .no_float_checks => args.no_float_checks = true,
            .help => {
                _ = Self.printHelp(stdout) catch {};
                return error.HelpRequested;
            },
        }
    }

    if (!has_input_path) {
        Self.printHelp(stdout) catch {};
        return error.InvalidArgs;
    }

    return args;
}
