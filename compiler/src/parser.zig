const std = @import("std");
const lexer = @import("lexer.zig");
const ast   = @import("ast.zig");

const TokenKind  = lexer.TokenKind;
const Token      = lexer.Token;
const Node       = ast.Node;
const NodeKind   = ast.NodeKind;
const NodeData   = ast.NodeData;
const AshType    = ast.AshType;
const TypeKind   = ast.TypeKind;
const BinaryOp   = ast.BinaryOp;
const UnaryOp    = ast.UnaryOp;
const CompoundOp = ast.CompoundOp;

pub const ParseError = error{ UnexpectedToken, UnexpectedEof, OutOfMemory };

pub const Parser = struct {
    tokens:    []Token,
    pos:       usize,
    allocator: std.mem.Allocator,
    filename:  []const u8,

    pub fn init(allocator: std.mem.Allocator, tokens: []Token, filename: []const u8) Parser {
        return .{ .tokens = tokens, .pos = 0, .allocator = allocator, .filename = filename };
    }

    // ── token helpers ──────────────────────────────────────────────────────

    // peek() skips newlines so the rest of the parser doesn't have to think about them
    fn peek(self: *Parser) Token {
        var i = self.pos;
        while (i < self.tokens.len) : (i += 1)
            if (self.tokens[i].kind != .Newline) return self.tokens[i];
        return self.tokens[self.tokens.len - 1];
    }
    // peekRaw() sees newlines, used only where newlines are structurally significant
    fn peekRaw(self: *Parser) Token {
        if (self.pos >= self.tokens.len) return self.tokens[self.tokens.len - 1];
        return self.tokens[self.pos];
    }
    fn advance(self: *Parser) Token {
        while (self.pos < self.tokens.len) {
            const t = self.tokens[self.pos];
            self.pos += 1;
            if (t.kind != .Newline) return t;
        }
        return self.tokens[self.tokens.len - 1];
    }
    fn skipNewlines(self: *Parser) void {
        while (self.pos < self.tokens.len and self.tokens[self.pos].kind == .Newline)
            self.pos += 1;
    }
    fn check(self: *Parser, kind: TokenKind) bool { return self.peek().kind == kind; }
    fn match(self: *Parser, kind: TokenKind) bool {
        if (self.check(kind)) { _ = self.advance(); return true; }
        return false;
    }
    fn expect(self: *Parser, kind: TokenKind) ParseError!Token {
        const t = self.peek();
        if (t.kind != kind) {
            std.debug.print("{s}:{}:{}: error: expected {s}, got '{s}'\n",
                .{ self.filename, t.line, t.col, @tagName(kind), t.text });
            return ParseError.UnexpectedToken;
        }
        return self.advance();
    }
    fn newNode(self: *Parser, kind: NodeKind, line: u32, col: u32, data: NodeData) ParseError!*Node {
        const n = try self.allocator.create(Node);
        n.* = .{ .kind = kind, .line = line, .col = col, .data = data };
        return n;
    }

    // ── program ────────────────────────────────────────────────────────────

    pub fn parseProgram(self: *Parser) ParseError!*Node {
        self.skipNewlines();
        var imports:   std.ArrayListUnmanaged(*Node) = .{};
        var functions: std.ArrayListUnmanaged(*Node) = .{};
        var structs:   std.ArrayListUnmanaged(*Node) = .{};
        var enums:     std.ArrayListUnmanaged(*Node) = .{};

        while (!self.check(.Eof)) {
            self.skipNewlines();
            if (self.check(.Eof)) break;
            switch (self.peek().kind) {
                .Import => try self.parseImports(&imports),
                .Fn     => try functions.append(self.allocator, try self.parseFunction()),
                .Struct => try structs.append(self.allocator, try self.parseStructDecl()),
                .Enum   => try enums.append(self.allocator, try self.parseEnumDecl()),
                else => {
                    const t = self.peek();
                    std.debug.print("{s}:{}:{}: error: unexpected '{s}' at top level\n",
                        .{ self.filename, t.line, t.col, t.text });
                    return ParseError.UnexpectedToken;
                },
            }
        }
        return self.newNode(.Program, 1, 1, NodeData{ .program = .{
            .imports   = try imports.toOwnedSlice(self.allocator),
            .functions = try functions.toOwnedSlice(self.allocator),
            .structs   = try structs.toOwnedSlice(self.allocator),
            .enums     = try enums.toOwnedSlice(self.allocator),
        }});
    }

    // ── imports ────────────────────────────────────────────────────────────

    fn importNameToken(self: *Parser) ?Token {
        const t = self.peek();
        switch (t.kind) {
            .Identifier, .TypeString, .TypeInt, .TypeFloat, .TypeBool => {
                _ = self.advance(); return t;
            },
            else => return null,
        }
    }

    fn parseImports(self: *Parser, out: *std.ArrayListUnmanaged(*Node)) ParseError!void {
        const tok = try self.expect(.Import);
        const first = self.importNameToken() orelse {
            std.debug.print("{s}:{}:{}: error: expected module name after 'import'\n",
                .{ self.filename, tok.line, tok.col });
            return ParseError.UnexpectedToken;
        };
        try out.append(self.allocator, try self.newNode(.ImportDecl, tok.line, tok.col,
            NodeData{ .import_decl = .{ .path = first.text }}));
        // import a, b, c  on one line
        while (self.peekRaw().kind == .Comma) {
            _ = self.advance();
            const extra = self.importNameToken() orelse return ParseError.UnexpectedToken;
            try out.append(self.allocator, try self.newNode(.ImportDecl, tok.line, tok.col,
                NodeData{ .import_decl = .{ .path = extra.text }}));
        }
    }

    // ── struct / enum ──────────────────────────────────────────────────────

    fn parseStructDecl(self: *Parser) ParseError!*Node {
        const tok = try self.expect(.Struct);
        const name = (try self.expect(.Identifier)).text;
        _ = try self.expect(.LBrace);
        self.skipNewlines();
        var fields: std.ArrayListUnmanaged(ast.StructFieldData) = .{};
        while (!self.check(.RBrace) and !self.check(.Eof)) {
            self.skipNewlines();
            if (self.check(.RBrace)) break;
            const fname = (try self.expect(.Identifier)).text;
            _ = try self.expect(.Colon);
            const ftype = try self.parseType();
            try fields.append(self.allocator, .{ .name = fname, .field_type = ftype });
            self.skipNewlines();
        }
        _ = try self.expect(.RBrace);
        return self.newNode(.StructDecl, tok.line, tok.col,
            NodeData{ .struct_decl = .{ .name = name, .fields = try fields.toOwnedSlice(self.allocator) }});
    }

    fn parseEnumDecl(self: *Parser) ParseError!*Node {
        const tok = try self.expect(.Enum);
        const name = (try self.expect(.Identifier)).text;
        _ = try self.expect(.LBrace);
        self.skipNewlines();
        var variants: std.ArrayListUnmanaged([]const u8) = .{};
        while (!self.check(.RBrace) and !self.check(.Eof)) {
            self.skipNewlines();
            if (self.check(.RBrace)) break;
            const v = (try self.expect(.Identifier)).text;
            try variants.append(self.allocator, v);
            _ = self.match(.Comma);
            self.skipNewlines();
        }
        _ = try self.expect(.RBrace);
        return self.newNode(.EnumDecl, tok.line, tok.col,
            NodeData{ .enum_decl = .{ .name = name, .variants = try variants.toOwnedSlice(self.allocator) }});
    }

    // ── types ──────────────────────────────────────────────────────────────

    // parseType: int | float | bool | string | vec[T] | TypeName
    // Also used for individual elements of a tuple return list.
    fn parseType(self: *Parser) ParseError!AshType {
        const t = self.advance();
        var base: AshType = switch (t.kind) {
            .TypeInt    => AshType{ .kind = .Int },
            .TypeFloat  => AshType{ .kind = .Float },
            .TypeBool   => AshType{ .kind = .Bool },
            .TypeString => AshType{ .kind = .String },
            .Identifier => blk: {
                if (std.mem.eql(u8, t.text, "vec")) {
                    _ = try self.expect(.LBracket);
                    const et = try self.parseType();
                    _ = try self.expect(.RBracket);
                    const ep = try self.allocator.create(AshType); ep.* = et;
                    return AshType{ .kind = .Vec, .elem_type = ep };
                }
                break :blk AshType{ .kind = .Struct, .name = t.text };
            },
            else => {
                std.debug.print("{s}:{}:{}: error: expected type, got '{s}'\n",
                    .{ self.filename, t.line, t.col, t.text });
                return ParseError.UnexpectedToken;
            },
        };
        // T[] → fixed array
        if (self.peek().kind == .LBracket) {
            _ = self.advance(); _ = try self.expect(.RBracket);
            const ep = try self.allocator.create(AshType); ep.* = base;
            base = AshType{ .kind = .Array, .elem_type = ep };
        }
        return base;
    }

    // parseReturnType: either a single type, or (T1, T2, ...) tuple
    fn parseReturnType(self: *Parser) ParseError!AshType {
        if (self.check(.LParen)) {
            _ = self.advance();
            var types: std.ArrayListUnmanaged(AshType) = .{};
            while (!self.check(.RParen) and !self.check(.Eof)) {
                try types.append(self.allocator, try self.parseType());
                if (!self.match(.Comma)) break;
            }
            _ = try self.expect(.RParen);
            const tt = try types.toOwnedSlice(self.allocator);
            return AshType{ .kind = .Tuple, .tuple_types = tt };
        }
        return self.parseType();
    }

    // ── function ───────────────────────────────────────────────────────────

    fn parseFunction(self: *Parser) ParseError!*Node {
        const tok  = try self.expect(.Fn);
        const name = (try self.expect(.Identifier)).text;
        _ = try self.expect(.LParen);
        var params: std.ArrayListUnmanaged(*Node) = .{};
        while (!self.check(.RParen) and !self.check(.Eof)) {
            try params.append(self.allocator, try self.parseParam());
            if (!self.match(.Comma)) break;
        }
        _ = try self.expect(.RParen);
        var return_type: ?AshType = null;
        if (self.check(.Colon)) { _ = self.advance(); return_type = try self.parseReturnType(); }
        const body = try self.parseBlock();
        return self.newNode(.FunctionDecl, tok.line, tok.col, NodeData{ .function_decl = .{
            .name        = name,
            .params      = try params.toOwnedSlice(self.allocator),
            .return_type = return_type,
            .body        = body,
        }});
    }

    fn parseParam(self: *Parser) ParseError!*Node {
        const name_tok = try self.expect(.Identifier);
        _ = try self.expect(.Colon);
        const param_type = try self.parseType();
        return self.newNode(.ParamDecl, name_tok.line, name_tok.col,
            NodeData{ .param_decl = .{ .name = name_tok.text, .param_type = param_type }});
    }

    // ── block & statements ─────────────────────────────────────────────────

    fn parseBlock(self: *Parser) ParseError!*Node {
        const tok = try self.expect(.LBrace);
        self.skipNewlines();
        var stmts: std.ArrayListUnmanaged(*Node) = .{};
        while (!self.check(.RBrace) and !self.check(.Eof)) {
            self.skipNewlines();
            if (self.check(.RBrace)) break;
            try stmts.append(self.allocator, try self.parseStatement());
            self.skipNewlines();
        }
        _ = try self.expect(.RBrace);
        return self.newNode(.Block, tok.line, tok.col,
            NodeData{ .block = .{ .stmts = try stmts.toOwnedSlice(self.allocator) }});
    }

    fn parseStatement(self: *Parser) ParseError!*Node {
        const t = self.peek();
        switch (t.kind) {
            .Return   => return self.parseReturn(),
            .If       => return self.parseIf(),
            .For      => return self.parseFor(),
            .While    => return self.parseWhile(),
            .Switch   => return self.parseSwitch(),
            .Const    => return self.parseConst(),
            .Break    => { _ = self.advance(); return self.newNode(.BreakStmt,    t.line, t.col, NodeData{ .break_stmt = .{} }); },
            .Continue => { _ = self.advance(); return self.newNode(.ContinueStmt, t.line, t.col, NodeData{ .continue_stmt = .{} }); },
            .Identifier => return self.parseIdentStatement(),
            else => {
                const expr = try self.parseExpr();
                return self.newNode(.ExprStmt, expr.line, expr.col,
                    NodeData{ .expr_stmt = .{ .expr = expr }});
            },
        }
    }

    // const name [:Type] = expr
    fn parseConst(self: *Parser) ParseError!*Node {
        const tok = try self.expect(.Const);
        const name = (try self.expect(.Identifier)).text;
        var const_type: ?AshType = null;
        if (self.check(.Colon)) { _ = self.advance(); const_type = try self.parseType(); }
        _ = try self.expect(.Assign);
        const init_expr = try self.parseExpr();
        return self.newNode(.ConstDecl, tok.line, tok.col, NodeData{ .const_decl = .{
            .name = name, .init_expr = init_expr, .const_type = const_type,
        }});
    }

    // All statements that start with an identifier.
    // Handles: x, y := …  |  x := …  |  x: T = …  |  x = …  |  x += …  |  x -= …
    //          x[i] = …   |  x.f = …  |  expression-statement
    fn parseIdentStatement(self: *Parser) ParseError!*Node {
        const ident_tok = self.peek();

        // ── look one token ahead (after the identifier) ──────────────────
        // We need to peek past the identifier to decide which form this is.
        // Strategy: save pos, read ident, then check next raw token.
        const saved = self.pos;
        _ = self.advance(); // consume the identifier (newline-skipping)
        const next = self.peek();

        // ── x, y [, z]* := call() ────────────────────────────────────────
        // The raw token after x is a comma.
        if (self.peekRaw().kind == .Comma) {
            var names: std.ArrayListUnmanaged([]const u8) = .{};
            try names.append(self.allocator, ident_tok.text);
            while (self.peekRaw().kind == .Comma) {
                _ = self.advance(); // skip comma (and any newlines before next name)
                const n = try self.expect(.Identifier);
                try names.append(self.allocator, n.text);
            }
            _ = try self.expect(.ColonAssign);
            const init_expr = try self.parseExpr();
            return self.newNode(.MultiVarDecl, ident_tok.line, ident_tok.col, NodeData{ .multi_var_decl = .{
                .names     = try names.toOwnedSlice(self.allocator),
                .init_expr = init_expr,
            }});
        }

        // ── x := expr ────────────────────────────────────────────────────
        if (next.kind == .ColonAssign) {
            _ = self.advance();
            const init_expr = try self.parseExpr();
            return self.newNode(.VarDecl, ident_tok.line, ident_tok.col, NodeData{ .var_decl = .{
                .name = ident_tok.text, .init_expr = init_expr, .var_type = null,
            }});
        }

        // ── x: Type = expr ───────────────────────────────────────────────
        if (next.kind == .Colon) {
            _ = self.advance();
            const vtype = try self.parseType();
            _ = try self.expect(.Assign);
            const init_expr = try self.parseExpr();
            return self.newNode(.VarDecl, ident_tok.line, ident_tok.col, NodeData{ .var_decl = .{
                .name = ident_tok.text, .init_expr = init_expr, .var_type = vtype,
            }});
        }

        // ── x = expr ─────────────────────────────────────────────────────
        if (next.kind == .Assign) {
            _ = self.advance();
            const value = try self.parseExpr();
            const target = try self.newNode(.IdentExpr, ident_tok.line, ident_tok.col,
                NodeData{ .ident_expr = .{ .name = ident_tok.text }});
            return self.newNode(.AssignStmt, ident_tok.line, ident_tok.col,
                NodeData{ .assign_stmt = .{ .target = target, .value = value }});
        }

        // ── x += expr  /  x -= expr ───────────────────────────────────────
        if (next.kind == .PlusAssign or next.kind == .MinusAssign) {
            const op: CompoundOp = if (next.kind == .PlusAssign) .AddAssign else .SubAssign;
            _ = self.advance();
            const value = try self.parseExpr();
            const target = try self.newNode(.IdentExpr, ident_tok.line, ident_tok.col,
                NodeData{ .ident_expr = .{ .name = ident_tok.text }});
            return self.newNode(.CompoundAssignStmt, ident_tok.line, ident_tok.col,
                NodeData{ .compound_assign_stmt = .{ .target = target, .value = value, .op = op }});
        }

        // ── x[i] = expr ──────────────────────────────────────────────────
        if (next.kind == .LBracket) {
            _ = self.advance();
            const index = try self.parseExpr();
            _ = try self.expect(.RBracket);
            if (self.check(.Assign)) {
                _ = self.advance();
                const value = try self.parseExpr();
                const arr = try self.newNode(.IdentExpr, ident_tok.line, ident_tok.col,
                    NodeData{ .ident_expr = .{ .name = ident_tok.text }});
                const target = try self.newNode(.IndexExpr, ident_tok.line, ident_tok.col,
                    NodeData{ .index_expr = .{ .array = arr, .index = index }});
                return self.newNode(.AssignStmt, ident_tok.line, ident_tok.col,
                    NodeData{ .assign_stmt = .{ .target = target, .value = value }});
            }
            // Wasn't an assignment — fall back to expression statement
            self.pos = saved;
            const expr = try self.parseExpr();
            return self.newNode(.ExprStmt, expr.line, expr.col, NodeData{ .expr_stmt = .{ .expr = expr }});
        }

        // ── x.field = expr ───────────────────────────────────────────────
        if (next.kind == .Dot) {
            _ = self.advance();
            const field_tok = try self.expect(.Identifier);
            if (self.check(.Assign)) {
                _ = self.advance();
                const value = try self.parseExpr();
                const obj = try self.newNode(.IdentExpr, ident_tok.line, ident_tok.col,
                    NodeData{ .ident_expr = .{ .name = ident_tok.text }});
                const target = try self.newNode(.FieldExpr, ident_tok.line, ident_tok.col,
                    NodeData{ .field_expr = .{ .object = obj, .field = field_tok.text }});
                return self.newNode(.AssignStmt, ident_tok.line, ident_tok.col,
                    NodeData{ .assign_stmt = .{ .target = target, .value = value }});
            }
            // Not an assignment — parse full expression from start
            self.pos = saved;
            const expr = try self.parseExpr();
            return self.newNode(.ExprStmt, expr.line, expr.col, NodeData{ .expr_stmt = .{ .expr = expr }});
        }

        // ── fallback: expression statement ───────────────────────────────
        self.pos = saved;
        const expr = try self.parseExpr();
        return self.newNode(.ExprStmt, expr.line, expr.col, NodeData{ .expr_stmt = .{ .expr = expr }});
    }

    fn parseReturn(self: *Parser) ParseError!*Node {
        const tok = try self.expect(.Return);
        var value: ?*Node = null;
        // Only parse a value if we're not at end-of-statement
        if (!self.check(.Newline) and !self.check(.RBrace) and !self.check(.Eof)) {
            const first = try self.parseExpr();
            // return a, b  →  TupleExpr
            if (self.peekRaw().kind == .Comma) {
                var elems: std.ArrayListUnmanaged(*Node) = .{};
                try elems.append(self.allocator, first);
                while (self.peekRaw().kind == .Comma) {
                    _ = self.advance();
                    try elems.append(self.allocator, try self.parseExpr());
                }
                value = try self.newNode(.TupleExpr, tok.line, tok.col,
                    NodeData{ .tuple_expr = .{ .elements = try elems.toOwnedSlice(self.allocator) }});
            } else {
                value = first;
            }
        }
        return self.newNode(.ReturnStmt, tok.line, tok.col,
            NodeData{ .return_stmt = .{ .value = value }});
    }

    fn parseIf(self: *Parser) ParseError!*Node {
        const tok = try self.expect(.If);
        const cond = try self.parseExpr();
        const then_block = try self.parseBlock();
        var else_block: ?*Node = null;
        if (self.check(.Else)) {
            _ = self.advance();
            self.skipNewlines();
            else_block = if (self.check(.If)) try self.parseIf() else try self.parseBlock();
        }
        return self.newNode(.IfStmt, tok.line, tok.col, NodeData{ .if_stmt = .{
            .condition  = cond,
            .then_block = then_block,
            .else_block = else_block,
        }});
    }

    fn parseFor(self: *Parser) ParseError!*Node {
        const tok     = try self.expect(.For);
        const var_tok = try self.expect(.Identifier);
        _ = try self.expect(.In);
        const start_or_iter = try self.parseExpr();
        if (self.check(.DotDot)) {
            _ = self.advance();
            const end  = try self.parseExpr();
            const body = try self.parseBlock();
            return self.newNode(.ForRangeStmt, tok.line, tok.col, NodeData{ .for_range_stmt = .{
                .var_name = var_tok.text, .start = start_or_iter, .end = end, .body = body,
            }});
        }
        const body = try self.parseBlock();
        return self.newNode(.ForEachStmt, tok.line, tok.col, NodeData{ .for_each_stmt = .{
            .var_name = var_tok.text, .iterable = start_or_iter, .body = body,
        }});
    }

    fn parseWhile(self: *Parser) ParseError!*Node {
        const tok  = try self.expect(.While);
        const cond = try self.parseExpr();
        const body = try self.parseBlock();
        return self.newNode(.WhileStmt, tok.line, tok.col,
            NodeData{ .while_stmt = .{ .condition = cond, .body = body }});
    }

    fn parseSwitch(self: *Parser) ParseError!*Node {
        const tok     = try self.expect(.Switch);
        const subject = try self.parseExpr();
        _ = try self.expect(.LBrace);
        self.skipNewlines();
        var cases: std.ArrayListUnmanaged(ast.SwitchCaseData) = .{};
        while (!self.check(.RBrace) and !self.check(.Eof)) {
            self.skipNewlines();
            if (self.check(.RBrace)) break;
            var case_val: ?*Node = null;
            if (self.check(.Case)) {
                _ = self.advance();
                case_val = try self.parseExpr();
            } else if (self.check(.Default)) {
                _ = self.advance();
            } else break;
            _ = try self.expect(.Arrow); // =>
            var body: std.ArrayListUnmanaged(*Node) = .{};
            if (self.check(.LBrace)) {
                _ = self.advance(); self.skipNewlines();
                while (!self.check(.RBrace) and !self.check(.Eof)) {
                    self.skipNewlines();
                    if (self.check(.RBrace)) break;
                    try body.append(self.allocator, try self.parseStatement());
                    self.skipNewlines();
                }
                _ = try self.expect(.RBrace);
            } else {
                try body.append(self.allocator, try self.parseStatement());
            }
            try cases.append(self.allocator, .{
                .value = case_val,
                .body  = try body.toOwnedSlice(self.allocator),
            });
            self.skipNewlines();
        }
        _ = try self.expect(.RBrace);
        return self.newNode(.SwitchStmt, tok.line, tok.col, NodeData{ .switch_stmt = .{
            .subject = subject,
            .cases   = try cases.toOwnedSlice(self.allocator),
        }});
    }

    // ── expressions ────────────────────────────────────────────────────────

    fn parseExpr(self: *Parser) ParseError!*Node { return self.parseOr(); }

    fn parseOr(self: *Parser) ParseError!*Node {
        var left = try self.parseAnd();
        while (self.check(.Or)) {
            _ = self.advance();
            const right = try self.parseAnd();
            left = try self.newNode(.BinaryExpr, left.line, left.col,
                NodeData{ .binary_expr = .{ .op = .Or, .left = left, .right = right }});
        }
        return left;
    }
    fn parseAnd(self: *Parser) ParseError!*Node {
        var left = try self.parseEquality();
        while (self.check(.And)) {
            _ = self.advance();
            const right = try self.parseEquality();
            left = try self.newNode(.BinaryExpr, left.line, left.col,
                NodeData{ .binary_expr = .{ .op = .And, .left = left, .right = right }});
        }
        return left;
    }
    fn parseEquality(self: *Parser) ParseError!*Node {
        var left = try self.parseComparison();
        while (self.check(.Eq) or self.check(.Ne)) {
            const op: BinaryOp = if (self.advance().kind == .Eq) .Eq else .Ne;
            const right = try self.parseComparison();
            left = try self.newNode(.BinaryExpr, left.line, left.col,
                NodeData{ .binary_expr = .{ .op = op, .left = left, .right = right }});
        }
        return left;
    }
    fn parseComparison(self: *Parser) ParseError!*Node {
        var left = try self.parseAddSub();
        while (self.check(.Lt) or self.check(.Gt) or self.check(.Le) or self.check(.Ge)) {
            const op_tok = self.advance();
            const op: BinaryOp = switch (op_tok.kind) {
                .Lt => .Lt, .Gt => .Gt, .Le => .Le, .Ge => .Ge, else => unreachable,
            };
            const right = try self.parseAddSub();
            left = try self.newNode(.BinaryExpr, left.line, left.col,
                NodeData{ .binary_expr = .{ .op = op, .left = left, .right = right }});
        }
        return left;
    }
    fn parseAddSub(self: *Parser) ParseError!*Node {
        var left = try self.parseMulDiv();
        while (self.check(.Plus) or self.check(.Minus)) {
            const op: BinaryOp = if (self.advance().kind == .Plus) .Add else .Sub;
            const right = try self.parseMulDiv();
            left = try self.newNode(.BinaryExpr, left.line, left.col,
                NodeData{ .binary_expr = .{ .op = op, .left = left, .right = right }});
        }
        return left;
    }
    fn parseMulDiv(self: *Parser) ParseError!*Node {
        var left = try self.parseUnary();
        while (self.check(.Star) or self.check(.Slash) or self.check(.Percent)) {
            const op_tok = self.advance();
            const op: BinaryOp = switch (op_tok.kind) {
                .Star => .Mul, .Slash => .Div, .Percent => .Mod, else => unreachable,
            };
            const right = try self.parseUnary();
            left = try self.newNode(.BinaryExpr, left.line, left.col,
                NodeData{ .binary_expr = .{ .op = op, .left = left, .right = right }});
        }
        return left;
    }
    fn parseUnary(self: *Parser) ParseError!*Node {
        // Unary minus
        if (self.check(.Minus)) {
            const tok = self.advance();
            return self.newNode(.UnaryExpr, tok.line, tok.col,
                NodeData{ .unary_expr = .{ .op = .Neg, .operand = try self.parseUnary() }});
        }
        // ![...] fixed-array literal
        if (self.check(.Not)) {
            const saved = self.pos;
            const tok = self.peek();
            _ = self.advance();
            if (self.check(.LBracket)) {
                _ = self.advance();
                var elems: std.ArrayListUnmanaged(*Node) = .{};
                while (!self.check(.RBracket) and !self.check(.Eof)) {
                    try elems.append(self.allocator, try self.parseExpr());
                    if (!self.match(.Comma)) break;
                }
                _ = try self.expect(.RBracket);
                return self.newNode(.FixedArrayLiteral, tok.line, tok.col,
                    NodeData{ .fixed_array_literal = .{ .elements = try elems.toOwnedSlice(self.allocator) }});
            }
            self.pos = saved;
            const not_tok = self.advance();
            return self.newNode(.UnaryExpr, not_tok.line, not_tok.col,
                NodeData{ .unary_expr = .{ .op = .Not, .operand = try self.parseUnary() }});
        }
        return self.parsePostfix();
    }
    fn parsePostfix(self: *Parser) ParseError!*Node {
        var base = try self.parsePrimary();
        while (true) {
            if (self.check(.LBracket)) {
                const tok = self.advance();
                const index = try self.parseExpr();
                _ = try self.expect(.RBracket);
                base = try self.newNode(.IndexExpr, tok.line, tok.col,
                    NodeData{ .index_expr = .{ .array = base, .index = index }});
            } else if (self.check(.Dot)) {
                const tok = self.advance();
                const field_tok = try self.expect(.Identifier);
                if (self.check(.LParen)) {
                    // obj.method(args) — pass obj as first arg
                    _ = self.advance();
                    var args: std.ArrayListUnmanaged(*Node) = .{};
                    try args.append(self.allocator, base);
                    while (!self.check(.RParen) and !self.check(.Eof)) {
                        try args.append(self.allocator, try self.parseExpr());
                        if (!self.match(.Comma)) break;
                    }
                    _ = try self.expect(.RParen);
                    base = try self.newNode(.CallExpr, tok.line, tok.col, NodeData{ .call_expr = .{
                        .module = "", .callee = field_tok.text,
                        .args   = try args.toOwnedSlice(self.allocator),
                    }});
                } else {
                    base = try self.newNode(.FieldExpr, tok.line, tok.col,
                        NodeData{ .field_expr = .{ .object = base, .field = field_tok.text }});
                }
            } else break;
        }
        return base;
    }

    // Look ahead past the '{' to decide if this is a struct literal.
    // A struct literal looks like:  TypeName { field: value, ... }
    // We confirm by checking that after '{' (skipping newlines) we see either:
    //   - '}' (empty struct)
    //   - Identifier followed by ':'
    // Anything else (like 'case', a number, etc.) means it's NOT a struct literal.
    fn isStructLiteralAhead(self: *Parser) bool {
        // Called after the identifier has been consumed (advance() was called).
        // self.pos is now right after the identifier in the raw token stream.
        // peek() already confirmed the next non-newline token is '{'.
        // We need to scan PAST that '{' to see what's inside.
        //
        // Step 1: find the '{' token by skipping any newlines from self.pos
        var i = self.pos;
        while (i < self.tokens.len and self.tokens[i].kind == .Newline) i += 1;
        // tokens[i] should now be '{'
        if (i >= self.tokens.len or self.tokens[i].kind != .LBrace) return false;
        i += 1; // skip past '{'
        // Step 2: skip newlines inside the brace
        while (i < self.tokens.len and self.tokens[i].kind == .Newline) i += 1;
        if (i >= self.tokens.len) return false;
        // Step 3: decide based on what we see
        const k = self.tokens[i].kind;
        if (k == .RBrace) return true;  // empty struct {}
        if (k == .Identifier) {
            // Check if the token after the identifier is ':'
            var j = i + 1;
            while (j < self.tokens.len and self.tokens[j].kind == .Newline) j += 1;
            if (j < self.tokens.len and self.tokens[j].kind == .Colon) return true;
        }
        return false;
    }

    fn parsePrimary(self: *Parser) ParseError!*Node {
        const t = self.peek();
        switch (t.kind) {
            .NumberInt => {
                _ = self.advance();
                const v = std.fmt.parseInt(i64, t.text, 10) catch 0;
                return self.newNode(.IntLiteral, t.line, t.col,
                    NodeData{ .int_literal = .{ .value = v }});
            },
            .NumberFloat => {
                _ = self.advance();
                const v = std.fmt.parseFloat(f64, t.text) catch 0.0;
                return self.newNode(.FloatLiteral, t.line, t.col,
                    NodeData{ .float_literal = .{ .value = v }});
            },
            .StringLit => {
                _ = self.advance();
                const inner = if (t.text.len >= 2) t.text[1..t.text.len-1] else t.text;
                return self.newNode(.StringLiteral, t.line, t.col,
                    NodeData{ .string_literal = .{ .value = inner }});
            },
            .True  => { _ = self.advance(); return self.newNode(.BoolLiteral, t.line, t.col, NodeData{ .bool_literal = .{ .value = true }}); },
            .False => { _ = self.advance(); return self.newNode(.BoolLiteral, t.line, t.col, NodeData{ .bool_literal = .{ .value = false }}); },
            .LBracket => {
                _ = self.advance();
                var elems: std.ArrayListUnmanaged(*Node) = .{};
                while (!self.check(.RBracket) and !self.check(.Eof)) {
                    try elems.append(self.allocator, try self.parseExpr());
                    if (!self.match(.Comma)) break;
                }
                _ = try self.expect(.RBracket);
                return self.newNode(.ArrayLiteral, t.line, t.col,
                    NodeData{ .array_literal = .{ .elements = try elems.toOwnedSlice(self.allocator) }});
            },
            .LParen => {
                _ = self.advance();
                const inner = try self.parseExpr();
                _ = try self.expect(.RParen);
                return inner;
            },
            .Identifier => {
                _ = self.advance();
                // module.func(...)  or  ident.field
                if (self.check(.Dot)) {
                    _ = self.advance();
                    const func_tok = try self.expect(.Identifier);
                    if (self.check(.LParen)) {
                        _ = self.advance();
                        var args: std.ArrayListUnmanaged(*Node) = .{};
                        while (!self.check(.RParen) and !self.check(.Eof)) {
                            try args.append(self.allocator, try self.parseExpr());
                            if (!self.match(.Comma)) break;
                        }
                        _ = try self.expect(.RParen);
                        return self.newNode(.CallExpr, t.line, t.col, NodeData{ .call_expr = .{
                            .module = t.text, .callee = func_tok.text,
                            .args   = try args.toOwnedSlice(self.allocator),
                        }});
                    }
                    const obj = try self.newNode(.IdentExpr, t.line, t.col,
                        NodeData{ .ident_expr = .{ .name = t.text }});
                    return self.newNode(.FieldExpr, t.line, t.col,
                        NodeData{ .field_expr = .{ .object = obj, .field = func_tok.text }});
                }
                // func(...)
                if (self.check(.LParen)) {
                    _ = self.advance();
                    var args: std.ArrayListUnmanaged(*Node) = .{};
                    while (!self.check(.RParen) and !self.check(.Eof)) {
                        try args.append(self.allocator, try self.parseExpr());
                        if (!self.match(.Comma)) break;
                    }
                    _ = try self.expect(.RParen);
                    return self.newNode(.CallExpr, t.line, t.col, NodeData{ .call_expr = .{
                        .module = "", .callee = t.text,
                        .args   = try args.toOwnedSlice(self.allocator),
                    }});
                }
                // TypeName { field: val, ... }  struct literal
                // Only treat Identifier { as a struct literal if what follows
                // looks like "field:" — i.e. the next two tokens after { are
                // Identifier then Colon (or immediately }).
                // This prevents "switch val {" from being parsed as a struct literal.
                if (self.check(.LBrace) and self.isStructLiteralAhead()) {
                    _ = self.advance(); self.skipNewlines();
                    var fields: std.ArrayListUnmanaged(ast.StructLiteralFieldData) = .{};
                    while (!self.check(.RBrace) and !self.check(.Eof)) {
                        self.skipNewlines();
                        if (self.check(.RBrace)) break;
                        const fname = (try self.expect(.Identifier)).text;
                        _ = try self.expect(.Colon);
                        const fval = try self.parseExpr();
                        try fields.append(self.allocator, .{ .name = fname, .value = fval });
                        _ = self.match(.Comma);
                        self.skipNewlines();
                    }
                    _ = try self.expect(.RBrace);
                    return self.newNode(.StructLiteral, t.line, t.col, NodeData{ .struct_literal = .{
                        .type_name = t.text,
                        .fields    = try fields.toOwnedSlice(self.allocator),
                    }});
                }
                // plain identifier
                return self.newNode(.IdentExpr, t.line, t.col,
                    NodeData{ .ident_expr = .{ .name = t.text }});
            },
            else => {
                std.debug.print("{s}:{}:{}: error: unexpected '{s}' in expression\n",
                    .{ self.filename, t.line, t.col, t.text });
                return ParseError.UnexpectedToken;
            },
        }
    }
};
