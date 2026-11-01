const std = @import("std");
const isDigit = std.ascii.isDigit;
const isAlphabetic = std.ascii.isAlphabetic;
const isWhitespace = std.ascii.isWhitespace;
const toLower = std.ascii.toLower;

const lib = @import("root.zig");
const Constant = lib.Constant;
const Identifier = lib.Identifier;
const Span = lib.Span;

pub fn lex(input: []const u8, file_id: lib.FileId, state: *lib.State) !Lexer.TokenList {
    var lexer = Lexer.new(input, file_id, state);
    return lexer.run();
}

pub const Token = struct {
    span: Span,
    tag: Tag,

    pub fn fmt(self: Token, writer: anytype, state: *lib.State) !void {
        try writer.print("{d:0>3}..{d:0>3}: ", .{ self.span.start, self.span.end });
        switch (self.tag) {
            .ident => |i| try writer.print("identifier({s})", .{state.identifiers.get(i).?}),
            .literal => |c| try c.fmt(writer),
            else => try writer.print("{s}", .{@tagName(self.tag)}),
        }
    }

    pub const Tag = union(enum) {
        ident: Identifier,
        literal: Constant,

        int,
        long,
        void,
        float,
        double,
        signed,
        unsigned,

        inf_float,
        inf_double,
        nan_float,
        nan_double,

        open_paren,
        close_paren,
        open_brace,
        close_brace,
        semicolon,
        tilde,
        hyphen,
        plus,
        asterisk,
        slash,
        percent,
        ampersand,
        caret,
        pipe,
        lshift,
        rshift,
        bang,
        ampersand_ampersand,
        pipe_pipe,
        equal_equal,
        bang_equal,
        less_than,
        less_equal,
        greater_than,
        greater_equal,
        question_mark,
        colon,
        comma,

        equal,
        add_equal,
        sub_equal,
        mul_equal,
        div_equal,
        rem_equal,
        bit_and_equal,
        bit_xor_equal,
        bit_or_equal,
        lshift_equal,
        rshift_equal,
        increment,
        decrement,

        @"return",
        @"if",
        goto,
        do,
        @"while",
        @"for",
        @"switch",
        case,
        default,
        @"break",
        @"continue",
        static,
        @"extern",

        eof,
    };
};

const keywords = std.StaticStringMap(Token.Tag).initComptime(.{
    .{ "float", .float },
    .{ "double", .double },
    .{ "int", .int },
    .{ "long", .long },
    .{ "signed", .signed },
    .{ "unsigned", .unsigned },
    .{ "void", .void },
    .{ "return", .@"return" },
    .{ "if", .@"if" },
    .{ "goto", .goto },
    .{ "do", .do },
    .{ "if", .@"if" },
    .{ "while", .@"while" },
    .{ "for", .@"for" },
    .{ "switch", .@"switch" },
    .{ "case", .case },
    .{ "default", .default },
    .{ "break", .@"break" },
    .{ "continue", .@"continue" },
    .{ "static", .static },
    .{ "extern", .@"extern" },
    .{ "Inf_float", .inf_float },
    .{ "Inf_double", .inf_double },
    .{ "NaN_float", .nan_float },
    .{ "NaN_double", .nan_double },
});

const operators = std.StaticStringMap(Token.Tag).initComptime(.{
    .{ "(", .open_paren },
    .{ ")", .close_paren },
    .{ "{", .open_brace },
    .{ "}", .close_brace },
    .{ ";", .semicolon },
    .{ "~", .tilde },
    .{ "-", .hyphen },
    .{ "+", .plus },
    .{ "*", .asterisk },
    .{ "/", .slash },
    .{ "%", .percent },
    .{ "&", .ampersand },
    .{ "^", .caret },
    .{ "|", .pipe },
    .{ "<<", .lshift },
    .{ ">>", .rshift },
    .{ "!", .bang },
    .{ "&&", .ampersand_ampersand },
    .{ "||", .pipe_pipe },
    .{ "==", .equal_equal },
    .{ "!=", .bang_equal },
    .{ "<", .less_than },
    .{ "<=", .less_equal },
    .{ ">", .greater_than },
    .{ ">=", .greater_equal },
    .{ "?", .question_mark },
    .{ ":", .colon },
    .{ ",", .comma },

    .{ "=", .equal },
    .{ "+=", .add_equal },
    .{ "-=", .sub_equal },
    .{ "*=", .mul_equal },
    .{ "/=", .div_equal },
    .{ "%=", .rem_equal },
    .{ "&=", .bit_and_equal },
    .{ "^=", .bit_xor_equal },
    .{ "|=", .bit_or_equal },
    .{ "<<=", .lshift_equal },
    .{ ">>=", .rshift_equal },
    .{ "++", .increment },
    .{ "--", .decrement },
});

pub const Lexer = struct {
    source: []const u8,
    current: usize,
    start: usize,
    tokens: TokenList,
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    identifiers: *Identifier.Interner,
    diagnostics: *lib.Diagnostics,
    file_id: lib.FileId,

    const Self = @This();
    const TokenList = std.ArrayList(Token);

    fn new(input: []const u8, file_id: lib.FileId, state: *lib.State) Self {
        return .{
            .source = input,
            .current = 0,
            .start = 0,
            .tokens = TokenList.empty,
            .gpa = state.gpa,
            .arena = state.arena.allocator(),
            .identifiers = &state.identifiers,
            .diagnostics = &state.diagnostics,
            .file_id = file_id,
        };
    }

    fn pushToken(self: *Self, token: Token) !void {
        try self.tokens.append(self.gpa, token);
    }

    fn run(self: *Self) !TokenList {
        errdefer self.tokens.deinit(self.gpa);

        while (self.next()) |char| {
            self.start = self.current - 1;
            try self.nextChar(char);
        }

        try self.pushToken(.{ .span = self.newSpan(self.current, self.current), .tag = .eof });

        return self.tokens;
    }

    fn addDiagnostic(self: *Self, message: []const u8, span: Span) !void {
        try self.diagnostics.*.addMessage(.lex, message, span);
    }

    fn printDiagnostic(self: *Self, comptime fmt: []const u8, args: anytype, span: Span) !void {
        const str = try std.fmt.allocPrint(self.arena, fmt, args);
        try self.addDiagnostic(str, span);
    }

    fn unexpectedCharacter(self: *Self, char: u8) !void {
        const message = try std.fmt.allocPrint(self.arena, "Unexpected character: {c}", .{char});
        try self.addDiagnostic(message, self.newSpan(self.start, self.current));
    }

    fn newSpan(self: *Self, start: usize, end: usize) Span {
        return Span.new(start, end, self.file_id);
    }

    fn currentSpan(self: *Self) Span {
        return self.newSpan(self.start, self.current);
    }

    fn currentCharSpan(self: *Self) Span {
        return self.newSpan(self.current - 1, self.current);
    }

    fn nextChar(self: *Self, char: u8) !void {
        if (isWhitespace(char)) {
            return;
        } else if (isIdentifierStart(char)) {
            try self.lexIdentOrKeyword();
        } else if (isDigit(char) or char == '.') {
            try self.lexNumber();
        } else {
            try self.lexOperator();
        }
    }

    fn lexIdentOrKeyword(self: *Self) !void {
        while (self.peek()) |c| {
            if (!isIdentifierBody(c)) break;
            self.current += 1;
        }

        const span = self.newSpan(self.start, self.current);
        const text = self.source[self.start..self.current];

        if (keywords.get(text)) |tag| {
            try self.pushToken(.{
                .span = span,
                .tag = tag,
            });
        } else {
            const ident = try self.identifiers.intern(text);
            try self.pushToken(.{
                .span = span,
                .tag = .{ .ident = ident },
            });
        }
    }

    fn lexNumber(self: *Self) !void {
        self.current = self.current - 1;

        if (self.peek() != null) {
            switch (self.peek().?) {
                'x', 'X', 'o', 'O', 'b', 'B' => {
                    const base: u8 = switch (self.next().?) {
                        'x', 'X' => 16,
                        'o', 'O' => 8,
                        'b', 'B' => 2,
                        else => unreachable,
                    };

                    self.consumeWhile(isDigit);
                    const suffix_start = self.current;

                    const candidate_types = try self.consumeSuffix(false, false);
                    return self.lexInteger(suffix_start, base, candidate_types);
                },
                else => {},
            }
        }

        var is_float = false;

        self.consumeWhile(isDigit);
        if (self.isFractionSeparator()) {
            self.current += 1;
            is_float = true;
            self.consumeWhile(isDigit);
        }

        if (self.consumeOneOf(&[_]u8{ 'e', 'E' })) {
            is_float = true;
            _ = self.consumeOneOf(&[_]u8{ '+', '-' });

            if (!self.consumeAtLeast1(isDigit)) {
                try self.addDiagnostic("missing exponent", self.currentCharSpan());
                return error.Invalid;
            }

            if (self.consumeAtLeast1(isDot)) {
                try self.addDiagnostic("unexpected '.' in exponent", self.currentCharSpan());
                return error.Invalid;
            }
        }

        const suffix_start = self.current;
        const candidate_types = try self.consumeSuffix(true, is_float);

        if (is_float) {
            return self.lexFloat(suffix_start, candidate_types[0]); // always only one candidate float type
        } else {
            return self.lexInteger(suffix_start, 10, candidate_types);
        }
    }

    fn consumeSuffix(self: *Self, is_decimal: bool, is_float: bool) ![]const Constant.Type {
        const suffix_start = self.current;
        self.consumeWhile(isIdentifierStart);
        if (self.current != suffix_start) {
            self.consumeWhile(isIdentifierBody);
        }

        const suffix = self.source[suffix_start..self.current];
        const candidate_types = classify_number(suffix, is_decimal, is_float) catch |e| switch (e) {
            error.invalid_float_suffix => {
                try self.addDiagnostic("invalid float suffix", self.newSpan(suffix_start, self.current));
                return error.Invalid;
            },
            error.invalid_int_suffix => {
                try self.addDiagnostic("invalid integer suffix", self.newSpan(suffix_start, self.current));
                return error.Invalid;
            },
            error.bad_suffix => {
                try self.addDiagnostic("bad suffix", self.newSpan(suffix_start, self.current));
                return error.Invalid;
            },
        };

        return candidate_types;
    }

    fn lexFloat(self: *Self, suffix_start: usize, ty: Constant.Type) !void {
        const span = self.newSpan(self.start, suffix_start);
        const text = self.source[self.start..suffix_start];

        const constant = switch (ty) {
            .float => Constant{ .float = std.fmt.parseFloat(f32, text) catch {
                try self.addDiagnostic("invalid characters in float literal", span);
                return error.Invalid;
            } },
            .double => Constant{ .double = std.fmt.parseFloat(f64, text) catch {
                try self.addDiagnostic("invalid characters in float literal", span);
                return error.Invalid;
            } },
            else => unreachable,
        };

        try self.pushToken(.{
            .span = span,
            .tag = .{ .literal = constant },
        });
    }

    fn lexInteger(self: *Self, suffix_start: usize, base: u8, candidate_types: []const Constant.Type) !void {
        const digits = self.source[self.start..suffix_start];
        const magnitude = std.fmt.parseInt(u128, digits, base) catch {
            try self.addDiagnostic("integer literal is too large", self.newSpan(self.start, suffix_start));
            return error.Invalid;
        };

        const literal_span = self.newSpan(self.start, self.current);

        var constant: ?Constant = null;
        for (candidate_types) |ty| {
            if (max_value_of_type(ty) >= magnitude) {
                constant = switch (ty) {
                    .int => Constant{ .int = @intCast(magnitude) },
                    .uint => Constant{ .uint = @intCast(magnitude) },
                    .long => Constant{ .long = @intCast(magnitude) },
                    .ulong => Constant{ .ulong = @intCast(magnitude) },
                    else => unreachable,
                };
                break;
            }
        }

        if (constant == null) {
            try self.addDiagnostic("integer literal is too large for any type", literal_span);
            return error.Invalid;
        }

        try self.pushToken(.{ .span = literal_span, .tag = .{ .literal = constant.? } });
    }

    fn lexOperator(self: *Self) !void {
        inline for (1..4) |n| {
            const length = 4 - n;
            if (self.operatorAt(length)) |tag| {
                self.current = self.start + length;
                try self.pushToken(.{ .span = self.newSpan(self.start, self.current), .tag = tag });
                return;
            }
        }

        self.current = self.start + 1;
        try self.unexpectedCharacter(self.source[self.start]);
        return error.Invalid;
    }

    fn operatorAt(self: *Self, comptime length: usize) ?Token.Tag {
        const text = self.source[self.start..@min(self.start + length, self.source.len)];
        return operators.get(text);
    }

    fn consumeChar(self: *Self, expected: u8) bool {
        if (self.peek()) |c| {
            if (c == expected) {
                self.current += 1;
                return true;
            }
        }
        return false;
    }

    fn consumeOneOf(self: *Self, expected: []const u8) bool {
        if (self.peek()) |c| {
            for (expected) |e| {
                if (c == e) {
                    self.current += 1;
                    return true;
                }
            }
        }
        return false;
    }

    fn consumeWhile(self: *Self, predicate: fn (u8) bool) void {
        while (self.peek()) |c| {
            if (!predicate(c)) break;
            self.current += 1;
        }
    }

    fn consumeAtLeast1(self: *Self, predicate: fn (u8) bool) bool {
        var consumed = false;
        while (self.peek()) |c| {
            if (!predicate(c)) break;
            self.current += 1;
            consumed = true;
        }
        return consumed;
    }

    fn currentChar(self: *Self) ?u8 {
        if (self.current >= self.source.len) {
            return null;
        }
        return self.source[self.current];
    }

    fn peek(self: *Self) ?u8 {
        return self.currentChar();
    }

    fn isFractionSeparator(self: *Self) bool {
        return self.current + 1 < self.source.len and
            self.source[self.current] == '.';
    }

    fn next(self: *Self) ?u8 {
        if (self.current >= self.source.len) {
            return null;
        }
        const c = self.source[self.current];
        self.current += 1;
        return c;
    }
};

fn isIdentifierStart(c: u8) bool {
    return isAlphabetic(c) or c == '_';
}

fn isIdentifierBody(c: u8) bool {
    return isIdentifierStart(c) or isDigit(c);
}

fn isDot(c: u8) bool {
    return c == '.';
}

const NumLiteralError = error{
    bad_suffix,
    invalid_float_suffix,
    invalid_int_suffix,
};

const NumSuffix = enum {
    none,
    long,
    unsigned,
    unsigned_long,
    float,

    fn parse(suffix: []const u8) NumLiteralError!NumSuffix {
        var has_l = false;
        var has_u = false;

        for (suffix) |c| {
            switch (toLower(c)) {
                'l' => {
                    if (has_l) return NumLiteralError.bad_suffix;
                    has_l = true;
                },
                'u' => {
                    if (has_u) return NumLiteralError.bad_suffix;
                    has_u = true;
                },
                else => return NumLiteralError.bad_suffix,
            }
        }

        if (!has_l and !has_u) {
            return .none;
        } else if (has_l and !has_u) {
            return .long;
        } else if (!has_l and has_u) {
            return .unsigned;
        } else if (has_l and has_u) {
            return .unsigned_long;
        } else {
            unreachable;
        }
    }
};

fn literal_type_candidates(suffix: NumSuffix, is_decimal: bool, is_float: bool) NumLiteralError![]const Constant.Type {
    if (is_float) {
        switch (suffix) {
            .float => return &[_]Constant.Type{.float},
            .none => return &[_]Constant.Type{.double},
            else => return error.invalid_float_suffix,
        }
    } else {
        switch (suffix) {
            .none => if (is_decimal) {
                return &[_]Constant.Type{ .int, .long };
            } else {
                return &[_]Constant.Type{ .int, .uint, .long, .ulong };
            },
            .unsigned => return &[_]Constant.Type{ .uint, .ulong },
            .long => return &[_]Constant.Type{.long},
            .unsigned_long => return &[_]Constant.Type{.ulong},
            .float => return error.invalid_int_suffix,
        }
    }
}

fn max_value_of_type(t: Constant.Type) u128 {
    const m = std.math.maxInt;

    switch (t) {
        .int => return @intCast(m(i32)),
        .uint => return @intCast(m(u32)),
        .long => return @intCast(m(i64)),
        .ulong => return @intCast(m(u64)),
        .float, .double => unreachable,
    }
}

fn classify_number(suffix: []const u8, is_decimal: bool, is_float: bool) NumLiteralError![]const Constant.Type {
    const parsed_suffix = try NumSuffix.parse(suffix);
    return literal_type_candidates(parsed_suffix, is_decimal, is_float);
}
