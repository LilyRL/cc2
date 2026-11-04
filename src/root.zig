const std = @import("std");
const Io = std.Io;

pub const Constant = @import("constant.zig").Constant;
pub const Identifier = @import("identifier.zig");
pub const Diagnostic = @import("diagnostics.zig");
pub const CompilerArgs = @import("args.zig");
pub const Diagnostics = Diagnostic.Store;
pub const File = @import("file.zig");
pub const FileId = File.FileId;
pub const Files = File.Store;
pub const Token = @import("lexer.zig").Token;

pub const lex = @import("lexer.zig").lex;
pub const parse = @import("parser.zig").parse;

pub const ast = @import("ast.zig");
pub const types = @import("types.zig");
pub const ansi = @import("ansi.zig");
pub const utils = @import("utils.zig");

pub const State = struct {
    identifiers: Identifier.Interner,
    arena: std.mem.Allocator,
    gpa: std.mem.Allocator,
    files: Files,
    diagnostics: Diagnostics,

    pub fn init(gpa: std.mem.Allocator, arena: std.mem.Allocator) State {
        return .{
            .identifiers = Identifier.Interner.init(arena, gpa),
            .arena = arena,
            .gpa = gpa,
            .files = Files.init(gpa),
            .diagnostics = Diagnostics.init(gpa),
        };
    }

    pub fn lex(self: *State, file_id: FileId) !std.ArrayList(Token) {
        const file = self.files.get(file_id) orelse return error.file_not_found;
        const source = file.source;
        const tokens = try @import("lexer.zig").lex(source, file_id, self);
        return tokens;
    }

    pub fn createFile(self: *State, text: []const u8, path: []const u8) !FileId {
        const name = try self.arena.dupe(u8, path);
        const file_object = try self.files.newFile(name, text);
        try self.files.add(file_object);
        return file_object.id;
    }

    pub fn openFile(self: *State, path: []const u8, io: std.Io) !FileId {
        const cwd = std.Io.Dir.cwd();
        var file = try cwd.openFile(io, path, .{ .mode = .read_only });
        const length = try file.length(io);
        var buf = try self.arena.alloc(u8, length);
        var file_reader = file.reader(io, buf);
        try file_reader.interface.readSliceAll(buf[0..]);

        return self.createFile(buf, path);
    }

    pub fn deinit(self: *State) void {
        self.diagnostics.deinit();
        self.identifiers.deinit();
        self.files.deinit();
    }
};

pub const Span = struct {
    file_id: FileId,
    start: u64,
    end: u64,

    pub fn new(start: u64, end: u64, file_id: FileId) Span {
        return .{ .start = start, .end = end, .file_id = file_id };
    }
};
