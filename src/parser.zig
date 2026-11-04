const lib = @import("root.zig");
const std = @import("std");

const Token = lib.Token;
const Identifier = lib.Identifier;
const ast = lib.ast;
const Expr = ast.Expr;
const Stmt = ast.Stmt;
const Span = lib.Span;
const sliceContains = lib.utils.sliceContains;

pub const Error = error{ Invalid, OutOfMemory };
const MAX_SPECIFIERS_IN_TYPE = 3;

pub fn parse(tokens: []const Token, file_id: lib.FileId, state: *lib.State) Error!ast.Program {
    var parser = Parser.new(tokens, file_id, state);
    return parser.run();
}

const Parser = struct {
    tokens: []const Token,
    i: usize,
    arena: std.mem.Allocator,
    gpa: std.mem.Allocator,
    diagnostics: *lib.Diagnostics,
    file_id: lib.FileId,
    identifiers: *lib.Identifier.Interner,

    const Self = @This();

    fn new(tokens: []const Token, file_id: lib.FileId, state: *lib.State) Self {
        return Self{
            .tokens = tokens,
            .i = 0,
            .arena = state.arena,
            .gpa = state.gpa,
            .diagnostics = &state.diagnostics,
            .file_id = file_id,
            .identifiers = &state.identifiers,
        };
    }

    fn run(self: *Self) Error!ast.Program {
        var declarations = std.ArrayList(ast.Declaration).empty;
        defer declarations.deinit(self.gpa);
        while (self.peek() != null) {
            const decl = try self.parseDeclaration();
            try declarations.append(self.gpa, decl);
        }

        return ast.Program{
            .declarations = try self.copyToArena(ast.Declaration, declarations),
        };
    }

    fn parseStmt(self: *Self) Error!*Stmt {
        const start = (try self.peekOrError()).span.start;
        if (self.next()) |token| {
            switch (token.tag) {
                .open_brace => {
                    self.goBack();
                    const block = try self.parseBlock();
                    const span = self.newSpan(start, self.prev().span.end);
                    return self.newStmt(.{ .compound = block }, span);
                },
                .ident => {
                    if (self.peek()) |peeked| {
                        if (peeked.tag == .colon) {
                            self.goBack();
                            const name = try self.consumeIdent();
                            _ = self.next();
                            const body = try self.parseStmt();
                            const span = self.newSpan(start, body.span.end);

                            return self.newStmt(.{ .label = .{ .name = name, .body = body } }, span);
                        }
                    }

                    self.goBack();
                    const expr = try self.parseExpr(0);
                    try self.consume(.semicolon);
                    return self.newStmt(.{ .expr = expr }, expr.span);
                },
                .goto => {
                    const name = try self.consumeIdent();
                    try self.consume(.semicolon);
                    const span = self.newSpan(start, self.prev().span.end);
                    return self.newStmt(.{ .goto = name }, span);
                },
                .@"if" => {
                    try self.consume(.open_paren);
                    const cond = try self.parseExpr(0);
                    try self.consume(.close_paren);
                    const if_true = try self.parseStmt();

                    const if_false = if (self.consumeIfPresent(.@"else"))
                        try self.parseStmt()
                    else
                        null;

                    const end = self.prev().span.end;
                    const span = self.newSpan(start, end);
                    return self.newStmt(.{ .@"if" = .{ .cond = cond, .if_true = if_true, .if_false = if_false } }, span);
                },
                .@"return" => {
                    const return_val = if ((try self.peekOrError()).tag == .semicolon)
                        @panic("void type unimplemented")
                        // try self.newExpr(.{ .literal = .void }, self.currentCharSpan())
                    else
                        try self.parseExpr(0);
                    try self.consume(.semicolon);
                    const span = self.newSpan(start, self.prev().span.end);
                    return self.newStmt(.{ .@"return" = return_val }, span);
                },
                .semicolon => {
                    return self.newStmt(.{ .null = {} }, token.span);
                },
                .@"break" => {
                    try self.consume(.semicolon);
                    const span = self.newSpan(start, self.prev().span.end);
                    return self.newStmt(.{ .@"break" = null }, span);
                },
                .@"continue" => {
                    try self.consume(.semicolon);
                    const span = self.newSpan(start, self.prev().span.end);
                    return self.newStmt(.{ .@"continue" = null }, span);
                },
                .@"while" => {
                    try self.consume(.open_paren);
                    const cond = try self.parseExpr(0);
                    try self.consume(.close_paren);
                    const body = try self.parseStmt();
                    const span = self.newSpan(start, self.prev().span.end);
                    return self.newStmt(.{
                        .@"while" = .{
                            .cond = cond,
                            .body = body,
                            .label = try self.identifiers.random("while"),
                        },
                    }, span);
                },
                .do => {
                    const body = try self.parseStmt();
                    try self.consume(.@"while");
                    try self.consume(.open_paren);
                    const cond = try self.parseExpr(0);
                    try self.consume(.close_paren);
                    try self.consume(.semicolon);

                    const span = self.newSpan(start, self.prev().span.end);
                    return self.newStmt(.{
                        .do_while = .{
                            .cond = cond,
                            .body = body,
                            .label = try self.identifiers.random("do_while"),
                        },
                    }, span);
                },
                .@"for" => {
                    try self.consume(.open_paren);
                    const init = try self.parseForInit();
                    const condition = try self.parseExprOrNothing();
                    try self.consume(.semicolon);
                    const post = try self.parseExprOrNothing();
                    try self.consume(.close_paren);

                    const body = try self.parseStmt();
                    const span = self.newSpan(start, self.prev().span.end);

                    return self.newStmt(.{
                        .@"for" = .{
                            .init = init,
                            .cond = condition,
                            .post = post,
                            .body = body,
                            .label = try self.identifiers.random("for"),
                        },
                    }, span);
                },
                .@"switch" => {
                    try self.consume(.open_paren);
                    const value = try self.parseExpr(0);
                    try self.consume(.close_paren);
                    const body = try self.parseStmt();
                    const span = self.newSpan(start, self.prev().span.end);

                    return self.newStmt(.{
                        .@"switch" = .{
                            .value = value,
                            .body = body,
                            .label = try self.identifiers.random("switch"),

                            .case_set = ast.Switch.CaseSet.init(self.gpa),
                            .cases = &[0]ast.SwitchCase{},
                            .default_case = null,
                        },
                    }, span);
                },
                .case => {
                    const constant = try self.consumeLiteral();
                    try self.consume(.colon);
                    const header_end = self.prev().span.end;
                    const stmt = try self.parseStmt();
                    const span = self.newSpan(start, stmt.span.end);

                    return self.newStmt(.{
                        .case = .{
                            .value = constant,
                            .stmt = stmt,
                            .header_span = self.newSpan(start, header_end),
                            .label = try self.identifiers.random("case"),
                        },
                    }, span);
                },
                .default => {
                    try self.consume(.colon);
                    const header_end = self.prev().span.end;
                    const stmt = try self.parseStmt();
                    const span = self.newSpan(start, stmt.span.end);

                    return self.newStmt(.{
                        .default_case = .{
                            .stmt = stmt,
                            .header_span = self.newSpan(start, header_end),
                            .label = try self.identifiers.random("default_case"),
                        },
                    }, span);
                },
                else => {
                    self.goBack();
                    const expr = try self.parseExpr(0);
                    try self.consume(.semicolon);
                    return self.newStmt(.{ .expr = expr }, expr.span);
                },
            }
        } else {
            self.addDiagnostic("unexpected end of file, expected statement", self.currentSpan());
            return Error.Invalid;
        }
    }

    fn parseBlock(self: *Self) Error!ast.Block {
        try self.consume(.open_brace);
        const statements = try self.parseBlockItems();
        try self.consume(.close_brace);

        return statements;
    }

    fn parseBlockItems(self: *Self) Error![]ast.BlockItem {
        var items = std.ArrayList(ast.BlockItem).empty;
        defer items.deinit(self.gpa);

        while (self.peek()) |peeked| {
            if (peeked.tag == .close_brace) {
                break;
            }

            try items.append(self.gpa, try self.parseBlockItem());
        }

        return self.copyToArena(ast.BlockItem, items);
    }

    fn parseBlockItem(self: *Self) Error!ast.BlockItem {
        const peeked = try self.peekOrError();
        if (isSpecifier(peeked.tag)) {
            const decl = try self.parseDeclaration();
            return ast.BlockItem{ .decl = decl };
        } else {
            const stmt = try self.parseStmt();
            return ast.BlockItem{ .stmt = stmt };
        }
    }

    fn parseDeclaration(self: *Self) Error!ast.Declaration {
        const start = (try self.peekOrError()).span.start;
        const meta = try self.consumeTypeAndStorageClass();
        const name_span = (try self.peekOrError()).span;
        const name = try self.consumeIdent();

        switch ((try self.peekOrError()).tag) {
            // variable
            .equal, .semicolon => {
                var init: ?*Expr = null;
                if (self.consumeIfPresent(.equal)) {
                    init = (try self.parseExpr(0));
                }

                try self.consume(.semicolon);
                const span = self.newSpan(start, self.prev().span.end);

                return ast.Declaration{ .variable = .{ .init = init, .name = name, .span = span, .storage_class = meta.storage_class, .ty = meta.ty } };
            },
            // function
            .open_paren => {
                _ = try self.nextOrError();
                const params = try self.parseParamList();
                try self.consume(.close_paren);

                var body: ?[]ast.BlockItem = null;
                if ((try self.peekOrError()).tag == .open_brace) {
                    body = try self.parseBlock();
                } else {
                    try self.consume(.semicolon);
                }

                const span = self.newSpan(start, self.prev().span.end);

                return ast.Declaration{ .function = .{
                    .name = name,
                    .params = params,
                    .body = body,
                    .span = span,
                    .name_span = name_span,
                    .storage_class = meta.storage_class,
                    .return_type = meta.ty,
                } };
            },
            else => {
                const found = try self.peekOrError();
                const message = try std.fmt.allocPrint(self.arena, "unexpected token: {}, expected '=', ';', '('", .{found.tag});
                self.addDiagnostic(message, found.span);
                return Error.Invalid;
            },
        }
    }

    fn parseExpr(self: *Self, min_precidence: usize) Error!*Expr {
        var lhs = try self.parseAtom();

        while (self.peek()) |peeked| {
            if (peeked.tag == .question_mark and CONDITIONAL_PRECEDENCE > min_precidence) {
                _ = self.next();
                const mhs = try self.parseExpr(0);
                try self.consume(.colon);
                const rhs = try self.parseExpr(CONDITIONAL_PRECEDENCE);
                const span = self.newSpan(lhs.span.start, rhs.span.end);
                lhs = try self.newExpr(.{ .conditional = .{ .cond = lhs, .if_true = mhs, .if_false = rhs } }, span);
            } else if (tokenToBinaryOperator(peeked)) |op| {
                if (binopPrecedence(op) < min_precidence) {
                    break;
                }

                _ = try self.nextOrError();

                if (op.isCompoundAssign()) {
                    const rhs = try self.parseExpr(binopPrecedence(op));
                    lhs = try self.compoundAssign(op, lhs, rhs);
                } else if (op == .assign) {
                    const rhs = try self.parseExpr(binopPrecedence(op));
                    const span = self.newSpan(lhs.span.start, rhs.span.end);
                    lhs = try self.newExpr(.{ .assignment = .{ .target = lhs, .value = rhs } }, span);
                } else {
                    const rhs = try self.parseExpr(binopPrecedence(op) + 1);
                    const span = self.newSpan(lhs.span.start, rhs.span.end);
                    lhs = try self.newExpr(.{ .binary = .{ .op = op, .lhs = lhs, .rhs = rhs } }, span);
                }
            } else {
                break;
            }
        }

        return lhs;
    }

    fn parseAtom(self: *Self) Error!*Expr {
        const next_token = try self.nextOrError();
        switch (next_token.tag) {
            .ident => |i| {
                if (self.peek()) |peeked_token| {
                    var expr: *Expr = undefined;

                    if (peeked_token.tag == .open_paren) {
                        _ = try self.nextOrError();
                        const args = try self.parseArguementList();
                        try self.consume(.close_paren);
                        const span = self.newSpan(next_token.span.start, self.prev().span.end);

                        expr = try self.newExpr(.{ .call = .{ .args = args, .name = i } }, span);
                    } else {
                        expr = try self.newExpr(.{ .variable = i }, next_token.span);
                    }

                    return self.postfix(expr);
                }
            },
            .open_paren => {
                const open = next_token.span.start;

                var expr: *Expr = undefined;
                if (self.isTypeNext()) {
                    const ty = try self.consumeType();
                    try self.consume(.close_paren);
                    const inner_expr = try self.parseExpr(0);
                    const close = self.prev().span.end;
                    expr = try self.newExpr(.{ .cast = .{ .target_type = ty, .expr = inner_expr } }, self.newSpan(open, close));
                } else {
                    const inner_expr = try self.parseExpr(0);
                    try self.consume(.close_paren);
                    const close = self.prev().span.end;
                    inner_expr.span = self.newSpan(open, close);
                    expr = inner_expr;
                }

                return self.postfix(expr);
            },
            .literal => |c| {
                const span = next_token.span;
                const expr = try self.newExpr(.{ .literal = c }, span);
                // it doesnt make sense to have a postfix operator on a constant, but we look for it anyway,
                // so that if this is done, we give a more useful error like "invalid lvalue", instead of "unexpected characters"
                return self.postfix(expr);
            },
            .inf_double => {
                const expr = try self.newExpr(.{ .literal = .{ .double = std.math.inf(f64) } }, next_token.span);
                return self.postfix(expr);
            },
            .inf_float => {
                const expr = try self.newExpr(.{ .literal = .{ .float = std.math.inf(f32) } }, next_token.span);
                return self.postfix(expr);
            },
            .nan_double => {
                const expr = try self.newExpr(.{ .literal = .{ .double = std.math.nan(f64) } }, next_token.span);
                return self.postfix(expr);
            },
            .nan_float => {
                const expr = try self.newExpr(.{ .literal = .{ .float = std.math.nan(f32) } }, next_token.span);
                return self.postfix(expr);
            },
            .hyphen => return self.unary(.negate),
            .bang => return self.unary(.not),
            .tilde => return self.unary(.bitwise_not),
            .increment => return self.prefixIncDec(.increment),
            .decrement => return self.prefixIncDec(.decrement),
            else => {
                const span = self.currentSpan();
                if (self.current()) |found| {
                    const message = std.fmt.allocPrint(self.arena, "unexpected token: {}, expected expression", .{found.tag}) catch "unexpected token";
                    self.addDiagnostic(message, span);
                } else {
                    self.addDiagnostic("unexpected end of file, expected expression", span);
                }

                return Error.Invalid;
            },
        }

        unreachable;
    }

    fn consumeTypeAndStorageClass(self: *Self) Error!TypeAndStorageClass {
        const start = self.currentSpan().start;
        var num_specifiers: usize = 0;
        var specifiers: [MAX_SPECIFIERS_IN_TYPE + 1]Specifier = undefined;

        while (self.peek()) |peeked| {
            const specifier = tokenToSpecifier(peeked.tag) orelse break;

            if (num_specifiers >= (MAX_SPECIFIERS_IN_TYPE + 1)) {
                self.addDiagnostic("too many specifiers for a type. no valid type has this many specifiers", self.newSpan(start, peeked.span.end));
                return Error.Invalid;
            }

            specifiers[num_specifiers] = specifier;
            num_specifiers += 1;

            _ = self.next();
        }

        const span = self.newSpan(start, self.currentSpan().end);
        return self.parseTypeAndStorageClass(specifiers[0..num_specifiers], span);
    }

    const TypeAndStorageClass = struct {
        ty: lib.types.Type,
        storage_class: lib.types.StorageClass,
    };
    fn parseTypeAndStorageClass(self: *Self, specifiers: []Specifier, span: Span) Error!TypeAndStorageClass {
        var types = std.ArrayList(Specifier).empty;
        var storage_classes = std.ArrayList(Specifier).empty;
        defer types.deinit(self.gpa);
        defer storage_classes.deinit(self.gpa);

        for (specifiers) |specifier| {
            switch (specifier) {
                .int, .long, .unsigned, .signed, .float, .double => {
                    try types.append(self.gpa, specifier);
                },
                .static, .@"extern" => {
                    try storage_classes.append(self.gpa, specifier);
                },
                .void => {
                    @panic("void type unimplemented");
                },
            }
        }

        const ty = try self.parseTypeList(types.items, span);

        if (storage_classes.items.len > 1) {
            self.addDiagnostic("multiple storage class specifiers are not allowed", span);
            return Error.Invalid;
        }

        const storage_class = if (storage_classes.items.len == 1)
            switch (storage_classes.items[0]) {
                .static => lib.types.StorageClass.static,
                .@"extern" => lib.types.StorageClass.@"extern",
                else => unreachable,
            }
        else
            lib.types.StorageClass.none;

        return TypeAndStorageClass{
            .ty = ty,
            .storage_class = storage_class,
        };
    }

    fn prefixIncDec(self: *Self, op: ast.IncDec) Error!*Expr {
        const start = self.currentSpan().start;
        const expr = try self.parseAtom();
        const span = self.newSpan(start, expr.span.end);
        return self.newExpr(.{ .prefix = .{ .op = op, .expr = expr } }, span);
    }

    fn unary(self: *Self, operator: ast.UnaryOperator) Error!*Expr {
        const start = self.currentSpan().start;
        const expr = try self.parseAtom();
        const span = self.newSpan(start, expr.span.end);
        return self.newExpr(.{ .unary = .{ .op = operator, .expr = expr } }, span);
    }

    fn postfix(self: *Self, expr: *Expr) Error!*Expr {
        var new_expr = expr;

        while (self.peek()) |tok| {
            const op = switch (tok.tag) {
                .increment => ast.IncDec.increment,
                .decrement => ast.IncDec.decrement,
                else => break,
            };

            _ = self.next();

            const span = self.newSpan(expr.span.start, tok.span.end);
            new_expr = try self.newExpr(.{ .postfix = .{ .op = op, .expr = new_expr } }, span);
        }

        return new_expr;
    }

    fn parseExprOrNothing(self: *Self) Error!?*Expr {
        if (self.peek()) |peeked| {
            switch (peeked.tag) {
                .semicolon, .close_paren => return null,
                else => return self.parseExpr(0),
            }
        } else {
            self.addDiagnostic("unexpected end of file", self.currentSpan());
            return Error.Invalid;
        }
    }

    fn parseParamList(self: *Self) Error![]ast.FunctionParameter {
        if ((try self.peekOrError()).tag == .void) {
            _ = self.next();
            return &[0]ast.FunctionParameter{};
        } else {
            var params = std.ArrayList(ast.FunctionParameter).empty;
            defer params.deinit(self.gpa);

            var i: usize = 0;
            while (self.peek()) |peeked| {
                if (peeked.tag == .close_paren) {
                    break;
                }

                if (i != 0) {
                    try self.consume(.comma);
                }

                const ty = try self.consumeType();
                const name = try self.consumeIdent();
                const span = self.newSpan(peeked.span.start, self.currentSpan().end);
                try params.append(self.gpa, .{ .span = span, .name = name, .ty = ty });

                i += 1;
            }

            if (i == 0) {
                self.addDiagnostic("expected at least one parameter, or void", self.currentSpan());
                return Error.Invalid;
            }

            return self.copyToArena(ast.FunctionParameter, params);
        }
    }

    fn parseArguementList(self: *Self) Error![]*Expr {
        if (self.peek()) |t| {
            if (t.tag == .close_paren) {
                return &[0]*Expr{};
            }
        }

        var args = std.ArrayList(*Expr).empty;
        defer args.deinit(self.gpa);

        const first_expr = try self.parseExpr(0);
        try args.append(self.gpa, first_expr);

        while (self.peek()) |tok| {
            if (tok.tag == .close_paren) {
                break;
            }

            try self.consume(.comma);
            const expr = try self.parseExpr(0);
            try args.append(self.gpa, expr);
        }

        return self.copyToArena(*Expr, args);
    }

    fn parseVariableDeclaration(self: *Self) Error!ast.VariableDeclaration {
        const decl = try self.parseDeclaration();

        switch (decl) {
            .variable => |v| return v,
            .function => |f| {
                self.addDiagnostic("expected variable declaration, found function declaration", f.span);
                return Error.Invalid;
            },
        }
    }

    fn parseForInit(self: *Self) Error!ast.ForInit {
        if (self.peek()) |peeked| {
            if (peeked.tag == .semicolon) {
                _ = self.next().?;
                return .none;
            }

            if (isSpecifier(peeked.tag)) {
                const decl = try self.parseVariableDeclaration();
                return .{ .decl = decl };
            } else {
                const expr = try self.parseExpr(0);
                try self.consume(.semicolon);
                return .{ .expr = expr };
            }
        } else {
            self.addDiagnostic("unexpected end of file, expected for loop initializer", self.currentSpan());
            return Error.Invalid;
        }
    }

    fn consumeLiteral(self: *Self) Error!lib.Constant {
        const token = try self.nextOrError();
        switch (token.tag) {
            .literal => |lit| return lit,
            .inf_double => return .{ .double = std.math.inf(f64) },
            .inf_float => return .{ .float = std.math.inf(f32) },
            .nan_double => return .{ .double = std.math.nan(f64) },
            .nan_float => return .{ .float = std.math.nan(f32) },
            else => {
                self.addDiagnostic("unexpected token, expected constant", token.span);
                return Error.Invalid;
            },
        }
    }

    fn newExpr(self: *Self, tag: Expr.Tag, span: Span) Error!*Expr {
        const expr = try self.arena.create(Expr);
        expr.* = Expr{
            .tag = tag,
            .span = span,
        };
        return expr;
    }

    fn newStmt(self: *Self, tag: Stmt.Tag, span: Span) Error!*Stmt {
        const stmt = try self.arena.create(Stmt);
        stmt.* = Stmt{
            .tag = tag,
            .span = span,
        };
        return stmt;
    }

    fn compoundAssign(self: *Self, op: ast.BinaryOperator, target: *Expr, value: *Expr) Error!*Expr {
        const lowered_op: ast.BinaryOperator = switch (op) {
            .add_assign => .add,
            .sub_assign => .sub,
            .mul_assign => .mul,
            .div_assign => .div,
            .rem_assign => .rem,
            .bit_and_assign => .bit_and,
            .bit_xor_assign => .bit_xor,
            .bit_or_assign => .bit_or,
            .lshift_assign => .lshift,
            .rshift_assign => .rshift,
            else => std.debug.panic("invalid compound assign operator: {}", .{op}),
        };

        const span = self.newSpan(target.span.start, value.span.end);
        const binary_expr = try self.newExpr(.{ .binary = .{ .op = lowered_op, .lhs = target, .rhs = value } }, span);
        return self.newExpr(.{ .assignment = .{ .target = target, .value = binary_expr } }, span);
    }

    fn current(self: *Self) ?Token {
        if (self.i >= self.tokens.len) return null;
        return self.tokens[self.i];
    }

    fn next(self: *Self) ?Token {
        const token = self.current() orelse return null;
        self.i += 1;
        return token;
    }

    fn goBack(self: *Self) void {
        if (self.i > 0) {
            self.i -= 1;
        }
    }

    fn nextOrError(self: *Self) Error!Token {
        const token = self.current() orelse {
            self.addDiagnostic("unexpected end of file", self.currentSpan());
            return Error.Invalid;
        };
        self.i += 1;
        return token;
    }

    fn prev(self: *Self) Token {
        return self.tokens[self.i - 1];
    }

    fn peek(self: *Self) ?Token {
        return self.current();
    }

    fn peekOrError(self: *Self) Error!Token {
        return self.current() orelse {
            self.addDiagnostic("unexpected end of file", self.currentSpan());
            return Error.Invalid;
        };
    }

    fn doublePeek(self: *Self) ?Token {
        if (self.i + 1 >= self.tokens.len) return null;
        return self.tokens[self.i + 1];
    }

    fn consumeIfPresent(self: *Self, tag: Token.Tag) bool {
        if (self.peek()) |peeked| {
            if (std.meta.activeTag(peeked.tag) == std.meta.activeTag(tag)) {
                _ = self.next();
                return true;
            }
        }

        return false;
    }

    fn consume(self: *Self, expected: Token.Tag) Error!void {
        if (self.peek()) |peeked| {
            if (std.meta.activeTag(peeked.tag) == std.meta.activeTag(expected)) {
                _ = self.next();
            } else {
                self.addExpectedTokenDiagnostic(expected);
                return Error.Invalid;
            }
        } else {
            self.addDiagnostic("enexpected end of file", self.currentSpan());
            return Error.Invalid;
        }
    }

    fn consumeType(self: *Self) Error!lib.types.Type {
        const start = self.currentSpan().start;
        var num_specifiers: usize = 0;
        var specifiers: [MAX_SPECIFIERS_IN_TYPE]Specifier = undefined;

        while (self.peek()) |peeked| {
            const specifier = tokenToSpecifier(peeked.tag) orelse break;

            if (specifier == .static or specifier == .@"extern") {
                self.addDiagnostic("storage class specifiers are not supported here", self.newSpan(start, peeked.span.end));
                return Error.Invalid;
            }

            if (num_specifiers >= MAX_SPECIFIERS_IN_TYPE) {
                self.addDiagnostic("too many specifiers for a type. no valid type has this many specifiers", self.newSpan(start, self.currentSpan().end));
                return Error.Invalid;
            }

            specifiers[num_specifiers] = specifier;
            num_specifiers += 1;

            _ = self.next();
        }

        const span = self.newSpan(start, self.currentSpan().end);
        return self.parseTypeList(specifiers[0..num_specifiers], span);
    }

    fn consumeIdent(self: *Self) Error!Identifier {
        const token = try self.peekOrError();
        switch (token.tag) {
            .ident => |ident| {
                _ = self.next();
                return ident;
            },
            else => {
                self.addExpectedTokenDiagnostic(.{ .ident = undefined });
                return Error.Invalid;
            },
        }
    }

    // types list must not include storage classes
    fn parseTypeList(self: *Self, types: []Specifier, span: Span) Error!lib.types.Type {
        if (types.len > MAX_SPECIFIERS_IN_TYPE) {
            self.addDiagnostic("too many types for a type. no valid type has this many types", span);
            return Error.Invalid;
        }

        if (types.len == 0) {
            self.addDiagnostic("expected type", self.currentCharSpan());
            return Error.Invalid;
        }

        if (types.len == 1) {
            switch (types[0]) {
                .int, .signed => return .int,
                .unsigned => return .uint,
                .long => return .long,
                .float => return .float,
                .double => return .double,
                .void => @panic("void type unimplemented!"),
                .static, .@"extern" => unreachable,
            }
        } else {
            if (lib.utils.bruteForceDuplicateCheck(Specifier, types)) {
                self.addDiagnostic("duplicate type specifier", span);
                return Error.Invalid;
            }

            if (types[0] == types[1]) {
                self.addDiagnostic("duplicate type specifier", span);
                return Error.Invalid;
            }

            for (types) |s| {
                switch (s) {
                    .float, .double => {
                        self.addDiagnostic("float and double cannot be combined with other type types", span);
                        return Error.Invalid;
                    },
                    else => {},
                }
            }

            if (sliceContains(Specifier, types, .unsigned) and
                sliceContains(Specifier, types, .signed))
            {
                self.addDiagnostic("signed and unsigned cannot be combined", span);
                return Error.Invalid;
            }

            if (sliceContains(Specifier, types, .unsigned) and
                sliceContains(Specifier, types, .long))
            {
                return .ulong;
            } else if (sliceContains(Specifier, types, .unsigned)) {
                return .uint;
            } else if (sliceContains(Specifier, types, .long)) {
                return .long;
            } else {
                return .int;
            }
        }
    }

    fn currentSpan(self: *Self) lib.Span {
        if (self.current()) |curr| {
            return curr.span;
        } else {
            const last_span = self.tokens[self.tokens.len - 1].span;
            return self.newSpan(last_span.end - 1, last_span.end);
        }
    }

    fn currentCharSpan(self: *Self) lib.Span {
        const span = self.currentSpan();
        return self.newSpan(span.end - 1, span.end);
    }

    fn newSpan(self: *Self, start: usize, end: usize) lib.Span {
        return lib.Span{
            .file_id = self.file_id,
            .start = start,
            .end = end,
        };
    }

    fn addExpectedTokenDiagnostic(self: *Self, expected: Token.Tag) void {
        const message = std.fmt.allocPrint(self.arena, "unexpected token, expected: {}", .{expected}) catch return;
        const span = self.currentSpan();
        self.addDiagnostic(message, span);
    }

    fn addDiagnostic(self: *Self, message: []const u8, span: Span) void {
        self.diagnostics.addMessage(.parse, message, span) catch {};
    }

    fn isTypeNext(self: *Self) bool {
        if (self.peek()) |peeked| {
            return isSpecifier(peeked.tag);
        }
        return false;
    }

    fn copyToArena(self: *const Self, T: type, list: std.ArrayList(T)) Error![]T {
        const slice = try self.arena.alloc(T, list.items.len);
        std.mem.copyForwards(T, slice, list.items);
        return slice;
    }
};

const Specifier = enum { int, long, unsigned, signed, float, double, void, static, @"extern" };

fn isSpecifier(token: Token.Tag) bool {
    return switch (token) {
        .signed => true,
        .unsigned => true,
        .int => true,
        .long => true,
        .float => true,
        .double => true,
        .@"extern" => true,
        .static => true,
        else => false,
    };
}

fn tokenToSpecifier(token: Token.Tag) ?Specifier {
    return switch (token) {
        .signed => Specifier.signed,
        .unsigned => Specifier.unsigned,
        .int => Specifier.int,
        .long => Specifier.long,
        .float => Specifier.float,
        .double => Specifier.double,
        .@"extern" => Specifier.@"extern",
        .static => Specifier.static,
        else => null,
    };
}

const CONDITIONAL_PRECEDENCE: usize = 1;
fn binopPrecedence(op: ast.BinaryOperator) usize {
    return switch (op) {
        .assign, .add_assign, .sub_assign, .mul_assign, .div_assign, .rem_assign, .bit_and_assign, .bit_or_assign, .bit_xor_assign, .lshift_assign, .rshift_assign => 0,
        .@"or" => 2,
        .@"and" => 3,
        .bit_or => 4,
        .bit_xor => 5,
        .bit_and => 6,
        .eq, .ne => 7,
        .gt, .ge, .lt, .le => 8,
        .lshift, .rshift => 9,
        .add, .sub => 10,
        .mul, .div, .rem => 11,
    };
}

fn tokenToBinaryOperator(token: Token) ?ast.BinaryOperator {
    return switch (token.tag) {
        .equal => .assign,
        .add_equal => .add_assign,
        .sub_equal => .sub_assign,
        .mul_equal => .mul_assign,
        .div_equal => .div_assign,
        .rem_equal => .rem_assign,
        .bit_and_equal => .bit_and_assign,
        .bit_or_equal => .bit_or_assign,
        .bit_xor_equal => .bit_xor_assign,
        .lshift_equal => .lshift_assign,
        .rshift_equal => .rshift_assign,
        .pipe_pipe => .@"or",
        .ampersand_ampersand => .@"and",
        .pipe => .bit_or,
        .caret => .bit_xor,
        .ampersand => .bit_and,
        .equal_equal => .eq,
        .bang_equal => .ne,
        .greater_than => .gt,
        .greater_equal => .ge,
        .less_than => .lt,
        .less_equal => .le,
        .lshift => .lshift,
        .rshift => .rshift,
        .add => .add,
        .hyphen => .sub,
        .asterisk => .mul,
        .slash => .div,
        .percent => .rem,

        else => null,
    };
}
