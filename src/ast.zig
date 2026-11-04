const lib = @import("root.zig");
const std = @import("std");

const Identifier = lib.Identifier;
const Constant = lib.Constant;
const Type = lib.types.Type;
const Span = lib.Span;
const StorageClass = lib.types.StorageClass;

pub const Program = struct { declarations: []Declaration };

pub const IncDec = enum { increment, decrement };
pub const UnaryOperator = enum { bitwise_not, negate, not };
pub const BinaryOperator = enum {
    add,
    sub,
    mul,
    div,
    rem,
    lshift,
    rshift,
    bit_and,
    bit_xor,
    bit_or,
    @"and",
    @"or",
    eq,
    ne,
    lt,
    le,
    gt,
    ge,
    assign,
    add_assign,
    sub_assign,
    mul_assign,
    div_assign,
    rem_assign,
    bit_and_assign,
    bit_xor_assign,
    bit_or_assign,
    lshift_assign,
    rshift_assign,

    pub fn isCompoundAssign(self: BinaryOperator) bool {
        return switch (self) {
            .add_assign, .sub_assign, .mul_assign, .div_assign, .rem_assign, .bit_and_assign, .bit_xor_assign, .bit_or_assign, .lshift_assign, .rshift_assign => true,
            else => false,
        };
    }
};

pub const Expr = struct {
    tag: Tag,
    span: Span,

    pub const Tag = union(enum) {
        variable: Identifier,
        literal: Constant,
        cast: struct { target_type: Type, expr: *Expr },
        unary: struct { op: UnaryOperator, expr: *Expr },
        binary: struct { op: BinaryOperator, lhs: *Expr, rhs: *Expr },
        assignment: struct { target: *Expr, value: *Expr },
        prefix: struct { op: IncDec, expr: *Expr },
        postfix: struct { op: IncDec, expr: *Expr },
        conditional: struct { cond: *Expr, if_true: *Expr, if_false: *Expr },
        call: struct { name: Identifier, args: []*Expr },
    };
};

pub const Block = []BlockItem;

pub const Declaration = union(enum) { function: FunctionDeclaration, variable: VariableDeclaration };

pub const FunctionParameter = struct {
    name: Identifier,
    span: Span,
    ty: Type,
};

pub const FunctionDeclaration = struct {
    name: Identifier,
    params: []FunctionParameter,
    body: ?Block,
    span: Span,
    name_span: Span,
    storage_class: StorageClass,
    return_type: Type,
};

pub const VariableDeclaration = struct {
    name: Identifier,
    init: ?*Expr,
    span: Span,
    storage_class: StorageClass,
    ty: Type,
};

pub const BlockItem = union(enum) {
    stmt: *Stmt,
    decl: Declaration,
};

pub const ForInit = union(enum) {
    decl: VariableDeclaration,
    expr: *Expr,
    none,
};

pub const Switch = struct {
    pub const CaseSet = std.AutoHashMap(Constant, Span);

    value: *Expr,
    body: *Stmt,
    label: Identifier,

    case_set: CaseSet,
    cases: []SwitchCase,
    default_case: ?Identifier,
};

pub const SwitchCase = struct { ident: Identifier, value: Constant };

pub const Stmt = struct {
    tag: Tag,
    span: Span,

    pub const Tag = union(enum) {
        @"return": *Expr,
        expr: *Expr,
        @"if": struct { cond: *Expr, if_true: *Stmt, if_false: ?*Stmt },
        null,
        goto: Identifier,
        label: struct { name: Identifier, body: *Stmt },
        compound: Block,
        @"break": ?Identifier,
        @"continue": ?Identifier,
        @"while": struct { cond: *Expr, body: *Stmt, label: Identifier },
        do_while: struct { body: *Stmt, cond: *Expr, label: Identifier },
        @"for": struct {
            init: ForInit,
            cond: ?*Expr,
            post: ?*Expr,
            body: *Stmt,
            label: Identifier,
        },
        @"switch": Switch,
        case: struct {
            value: Constant,
            label: Identifier,
            header_span: Span,
            stmt: *Stmt,
        },
        default_case: struct {
            label: Identifier,
            header_span: Span,
            stmt: *Stmt,
        },
    };
};

// ////////////////////////////////////////////////////////////////////////////
//                              Debug formatting                             //
///////////////////////////////////////////////////////////////////////////////

pub const Formatter = struct {
    state: lib.State,

    const Self = @This();
    const Writer = std.Io.Writer;

    const Error = std.Io.Writer.Error;

    pub fn formatConstant(constant: Constant, writer: *Writer) Error!void {
        switch (constant) {
            .int => |n| try writer.print("const.int({d})", .{n}),
            .uint => |n| try writer.print("const.uint({d})", .{n}),
            .long => |n| try writer.print("const.long({d})", .{n}),
            .ulong => |n| try writer.print("const.ulong({d})", .{n}),
            .float => |n| try writer.print("const.float({d})", .{n}),
            .double => |n| try writer.print("const.double({d})", .{n}),
        }
    }

    pub fn formatExpression(self: *const Self, expr: *const Expr, writer: *Writer) Error!void {
        switch (expr.tag) {
            .variable => |i| try writer.print("ident({s})", .{self.state.identifiers.get(i).?}),
            .literal => |c| try formatConstant(c, writer),
            .cast => |c| {
                try writer.writeAll("(");
                try self.formatExpression(c.expr, writer);
                try writer.print(") as {}", .{c.target_type});
            },
            .unary => |u| {
                try writer.writeAll("(");
                try formatUnaryOperator(u.op, writer);
                try self.formatExpression(u.expr, writer);
                try writer.writeAll(")");
            },
            .binary => |b| {
                try writer.writeAll("(");
                try self.formatExpression(b.lhs, writer);
                try writer.writeAll(" ");
                try formatBinaryOperator(b.op, writer);
                try writer.writeAll(" ");
                try self.formatExpression(b.rhs, writer);
                try writer.writeAll(")");
            },
            .assignment => |a| {
                try self.formatExpression(a.target, writer);
                try writer.writeAll(" = ");
                try self.formatExpression(a.value, writer);
            },
            .prefix => |p| {
                try formatIncDec(p.op, writer);
                try writer.writeAll("(");
                try self.formatExpression(p.expr, writer);
                try writer.writeAll(")");
            },
            .postfix => |p| {
                try writer.writeAll("(");
                try self.formatExpression(p.expr, writer);
                try formatIncDec(p.op, writer);
                try writer.writeAll(")");
            },
            .conditional => |c| {
                try writer.writeAll("(");
                try self.formatExpression(c.cond, writer);
                try writer.writeAll(" ? ");
                try self.formatExpression(c.if_true, writer);
                try writer.writeAll(" : ");
                try self.formatExpression(c.if_false, writer);
                try writer.writeAll(")");
            },
            .call => |c| {
                try writer.writeAll(self.state.identifiers.get(c.name).?);
                try writer.writeAll("(");
                for (c.args, 0..) |arg, i| {
                    if (i != 0) try writer.writeAll(", ");
                    try self.formatExpression(arg, writer);
                }
                try writer.writeAll(")");
            },
        }
    }

    pub fn formatIncDec(op: IncDec, writer: *Writer) !void {
        try writer.writeAll(switch (op) {
            .increment => "++",
            .decrement => "--",
        });
    }

    pub fn formatUnaryOperator(op: UnaryOperator, writer: *Writer) !void {
        try writer.writeAll(switch (op) {
            .bitwise_not => "~",
            .negate => "-",
            .not => "!",
        });
    }

    pub fn formatBinaryOperator(op: BinaryOperator, writer: *Writer) !void {
        try writer.writeAll(switch (op) {
            .add => "+",
            .sub => "-",
            .mul => "*",
            .div => "/",
            .rem => "%",
            .lshift => "<<",
            .rshift => ">>",
            .bit_and => "&",
            .bit_xor => "^",
            .bit_or => "|",
            .@"and" => "&&",
            .@"or" => "||",
            .eq => "==",
            .ne => "!=",
            .lt => "<",
            .le => "<=",
            .gt => ">",
            .ge => ">=",
            .assign => "=",
            .add_assign => "+=",
            .sub_assign => "-=",
            .mul_assign => "*=",
            .div_assign => "/=",
            .rem_assign => "%=",
            .bit_and_assign => "&=",
            .bit_xor_assign => "^=",
            .bit_or_assign => "|=",
            .lshift_assign => "<<=",
            .rshift_assign => ">>=",
        });
    }

    pub fn formatType(ty: Type, writer: *Writer) !void {
        try writer.writeAll(switch (ty) {
            .int => "int",
            .long => "long",
            .uint => "uint",
            .ulong => "ulong",
            .float => "float",
            .double => "double",
            .function => "function",
        });
    }

    pub fn formatStatement(self: *const Self, stmt: *const Stmt, writer: *Writer, indentation: usize) Error!void {
        if (stmt.tag == .label) {
            try indent(writer, indentation - 1);
        } else {
            try indent(writer, indentation);
        }

        switch (stmt.tag) {
            .@"return" => |expr| {
                try writer.writeAll("return ");
                try self.formatExpression(expr, writer);
                try writer.writeAll(";\n");
            },
            .expr => |expr| {
                try self.formatExpression(expr, writer);
                try writer.writeAll(";\n");
            },
            .null => {
                try writer.writeAll(";\n");
            },
            .goto => |l| {
                try writer.print("goto {s}", .{self.state.identifiers.get(l).?});
                try writer.writeAll(";\n");
            },
            .label => |i| {
                try writer.print("{s}:", .{self.state.identifiers.get(i.name).?});
                try writer.writeAll(";\n");
                try self.formatStatement(i.body, writer, indentation);
            },
            .compound => |block| {
                try self.formatBlock(block, writer, indentation);
            },
            .@"break" => |i| {
                try writer.writeAll("break ");

                if (i) |ident| {
                    if (self.state.identifiers.get(ident)) |str| {
                        try writer.writeAll(str);
                    }
                }

                try writer.writeAll(";\n");
            },
            .@"continue" => |i| {
                try writer.writeAll("continue ");

                if (i) |ident| {
                    if (self.state.identifiers.get(ident)) |str| {
                        try writer.writeAll(str);
                    }
                }

                try writer.writeAll(";\n");
            },
            .@"while" => |w| {
                try writer.writeAll("while (");
                try self.formatExpression(w.cond, writer);
                try writer.writeAll(") \n");
                try self.formatStatement(w.body, writer, indentation);
            },
            .do_while => |d| {
                try writer.writeAll("do \n");
                try self.formatStatement(d.body, writer, indentation);
                try writer.writeAll(" while (");
                try self.formatExpression(d.cond, writer);
                try writer.writeAll(");\n");
            },
            .@"for" => |f| {
                try writer.writeAll("for (");
                switch (f.init) {
                    .decl => |decl| {
                        try self.formatVariableDeclaration(decl, writer, 0);
                    },
                    .expr => |expr| {
                        try self.formatExpression(expr, writer);
                    },
                    .none => {},
                }
                try writer.writeAll("; ");
                if (f.cond) |cond| {
                    try self.formatExpression(cond, writer);
                }
                try writer.writeAll("; ");
                if (f.post) |post| {
                    try self.formatExpression(post, writer);
                }
                try writer.writeAll(") \n");
                try self.formatStatement(f.body, writer, indentation);
            },
            .@"switch" => |s| {
                try writer.writeAll("switch (");
                try self.formatExpression(s.value, writer);
                try writer.writeAll(") \n");
                try self.formatStatement(s.body, writer, indentation);
            },
            .case => |c| {
                try writer.writeAll("case ");
                try formatConstant(c.value, writer);
                try writer.writeAll(";\n");
                try self.formatStatement(c.stmt, writer, indentation + 1);
            },
            .default_case => |d| {
                try writer.writeAll("default:\n");
                try self.formatStatement(d.stmt, writer, indentation + 1);
            },
            .@"if" => |i| {
                try writer.writeAll("if (");
                try self.formatExpression(i.cond, writer);
                try writer.writeAll(") \n");
                try self.formatStatement(i.if_true, writer, indentation);
                if (i.if_false) |if_false| {
                    try writer.writeAll(" else \n");
                    try self.formatStatement(if_false, writer, indentation);
                }
            },
        }
    }

    pub fn formatProgram(self: *const Self, program: Program, writer: *Writer) !void {
        for (program.declarations) |decl| {
            try self.formatDeclaration(decl, writer, 0);
            try writer.writeAll("\n");
        }
    }

    pub fn formatDeclaration(self: *const Self, decl: Declaration, writer: *Writer, indentation: usize) !void {
        switch (decl) {
            .function => |f| {
                try self.formatFunctionDeclaration(f, writer, indentation);
            },
            .variable => |v| {
                try self.formatVariableDeclaration(v, writer, indentation);
                try writer.writeAll(";\n");
            },
        }
    }

    pub fn formatFunctionDeclaration(self: *const Self, func: FunctionDeclaration, writer: *Writer, indentation: usize) !void {
        try indent(writer, indentation);
        try formatType(func.return_type, writer);
        try writer.writeAll(" ");
        try writer.writeAll(self.state.identifiers.get(func.name).?);
        try writer.writeAll("(");
        for (func.params, 0..) |param, i| {
            if (i != 0) try writer.writeAll(", ");
            try self.formatFunctionParameter(param, writer);
        }
        try writer.writeAll(") ");

        if (func.body) |body| {
            try self.formatBlock(body, writer, 0);
        }
    }

    pub fn formatBlock(self: *const Self, block: Block, writer: *Writer, indentation: usize) Error!void {
        try writer.writeAll("{\n");
        for (block) |block_item| {
            try self.formatBlockItem(block_item, writer, indentation + 1);
        }
        try indent(writer, indentation);
        try writer.writeAll("}\n");
    }

    pub fn formatBlockItem(self: *const Self, block_item: BlockItem, writer: *Writer, indentation: usize) Error!void {
        switch (block_item) {
            .stmt => |stmt| {
                try self.formatStatement(stmt, writer, indentation);
            },
            .decl => |decl| {
                switch (decl) {
                    .variable => |v| {
                        try self.formatVariableDeclaration(v, writer, indentation);
                    },
                    .function => |f| {
                        try self.formatFunctionDeclaration(f, writer, indentation);
                    },
                }
                try writer.writeAll(";\n");
            },
        }
    }

    pub fn formatFunctionParameter(self: *const Self, param: FunctionParameter, writer: *Writer) !void {
        try formatType(param.ty, writer);
        try writer.writeAll(" ");
        try writer.writeAll(self.state.identifiers.get(param.name).?);
    }

    fn indent(writer: *Writer, indentation: usize) !void {
        for (0..indentation) |_| {
            try writer.writeAll("    ");
        }
    }

    pub fn formatVariableDeclaration(self: *const Self, var_decl: VariableDeclaration, writer: *Writer, indentation: usize) !void {
        try indent(writer, indentation);
        try formatType(var_decl.ty, writer);
        try writer.writeAll(" ");
        try writer.writeAll(self.state.identifiers.get(var_decl.name).?);
        if (var_decl.init) |init_expr| {
            try writer.writeAll(" = ");
            try self.formatExpression(init_expr, writer);
        }
    }
};
