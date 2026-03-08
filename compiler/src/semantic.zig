const std = @import("std");
const ast = @import("ast.zig");

const Node     = ast.Node;
const NodeKind = ast.NodeKind;
const AshType  = ast.AshType;
const TypeKind = ast.TypeKind;

pub const SemanticError = error{
    UndefinedVariable, UndefinedFunction, TypeMismatch,
    DuplicateDeclaration, WrongArgCount, NotCallable,
    OutOfMemory, InvalidOperation,
};

const FuncSig = struct {
    name:        []const u8,
    param_types: []AshType,
    return_type: AshType,
};

const StructInfo = struct {
    name:   []const u8,
    fields: []ast.StructFieldData,
};

const Scope = struct {
    symbols: std.StringHashMapUnmanaged(AshType),
    parent:  ?*Scope,

    fn init() Scope { return .{ .symbols = .{}, .parent = null }; }
    fn deinit(self: *Scope, a: std.mem.Allocator) void { self.symbols.deinit(a); }
    fn define(self: *Scope, a: std.mem.Allocator, name: []const u8, t: AshType) !void {
        try self.symbols.put(a, name, t);
    }
    fn lookup(self: *Scope, name: []const u8) ?AshType {
        if (self.symbols.get(name)) |t| return t;
        if (self.parent) |p| return p.lookup(name);
        return null;
    }
    fn update(self: *Scope, name: []const u8, t: AshType) bool {
        if (self.symbols.getPtr(name)) |ptr| { ptr.* = t; return true; }
        if (self.parent) |p| return p.update(name, t);
        return false;
    }
};

pub const Analyzer = struct {
    allocator: std.mem.Allocator,
    filename:  []const u8,
    functions: std.StringHashMapUnmanaged(FuncSig),
    structs:   std.StringHashMapUnmanaged(StructInfo),
    enums:     std.StringHashMapUnmanaged([][]const u8),
    had_error: bool,

    pub fn init(allocator: std.mem.Allocator, filename: []const u8) Analyzer {
        return .{ .allocator = allocator, .filename = filename,
                  .functions = .{}, .structs = .{}, .enums = .{}, .had_error = false };
    }
    pub fn deinit(self: *Analyzer) void {
        self.functions.deinit(self.allocator);
        self.structs.deinit(self.allocator);
        self.enums.deinit(self.allocator);
    }

    fn err(self: *Analyzer, line: u32, col: u32, comptime fmt: []const u8, args: anytype) void {
        self.had_error = true;
        std.debug.print("{s}:{}:{}: error: " ++ fmt ++ "\n",
            .{ self.filename, line, col } ++ args);
    }

    fn reg(self: *Analyzer, name: []const u8, params: []const TypeKind, ret: TypeKind) !void {
        var pt = try self.allocator.alloc(AshType, params.len);
        for (params, 0..) |p, i| pt[i] = AshType{ .kind = p };
        try self.functions.put(self.allocator, name, FuncSig{
            .name = name, .param_types = pt, .return_type = AshType{ .kind = ret },
        });
    }

    pub fn analyze(self: *Analyzer, program: *Node) !void {
        // ── built-in functions always available ───────────────────────────
        try self.reg("print",        &.{.Unknown}, .Void);
        try self.reg("len",          &.{.Unknown}, .Int);
        try self.reg("str",          &.{.Unknown}, .String);
        try self.reg("vec_new",      &.{},         .Unknown);
        try self.reg("push",         &.{.Unknown,.Unknown}, .Void);
        try self.reg("pop",          &.{.Unknown},          .Unknown);
        try self.reg("vec_get",      &.{.Unknown,.Int},     .Unknown);
        try self.reg("vec_set",      &.{.Unknown,.Int,.Unknown}, .Void);
        try self.reg("vec_len",      &.{.Unknown}, .Int);
        try self.reg("vec_clear",    &.{.Unknown}, .Void);
        try self.reg("vec_contains", &.{.Unknown,.Unknown}, .Bool);

        const pd = &program.data.program;

        // ── register structs & enums ──────────────────────────────────────
        for (pd.structs) |s| {
            const sd = &s.data.struct_decl;
            try self.structs.put(self.allocator, sd.name,
                StructInfo{ .name = sd.name, .fields = sd.fields });
        }
        for (pd.enums) |e| {
            const ed = &e.data.enum_decl;
            try self.enums.put(self.allocator, ed.name, ed.variants);
        }

        // ── first pass: register ALL user functions by signature ──────────
        // This is what lets functions be defined in any order.
        for (pd.functions) |func| {
            const fd = &func.data.function_decl;
            var pts: std.ArrayListUnmanaged(AshType) = .{};
            for (fd.params) |p| try pts.append(self.allocator, p.data.param_decl.param_type);
            try self.functions.put(self.allocator, fd.name, FuncSig{
                .name        = fd.name,
                .param_types = try pts.toOwnedSlice(self.allocator),
                .return_type = fd.return_type orelse AshType{ .kind = .Void },
            });
        }

        // ── stdlib: gate behind imports ───────────────────────────────────
        for (pd.imports) |imp| {
            const path = imp.data.import_decl.path;
            if (std.mem.eql(u8, path, "io")) {
                try self.reg("io.input",   &.{.String},        .String);
                try self.reg("input",      &.{.String},        .String);
                try self.reg("read_file",  &.{.String},        .String);
                try self.reg("write_file", &.{.String,.String}, .Void);
            } else if (std.mem.eql(u8, path, "string")) {
                try self.reg("str_len",     &.{.String},           .Int);
                try self.reg("str_upper",   &.{.String},           .String);
                try self.reg("str_lower",   &.{.String},           .String);
                try self.reg("str_concat",  &.{.String,.String},   .String);
                try self.reg("str_slice",   &.{.String,.Int,.Int}, .String);
                try self.reg("str_contains",&.{.String,.String},   .Bool);
                try self.reg("parse_int",   &.{.String},           .Int);
                try self.reg("parse_float", &.{.String},           .Float);
            } else if (std.mem.eql(u8, path, "math")) {
                try self.reg("sqrt",  &.{.Float},         .Float);
                try self.reg("pow",   &.{.Float,.Float},  .Float);
                try self.reg("abs",   &.{.Unknown},       .Unknown);
                try self.reg("floor", &.{.Float},         .Float);
                try self.reg("ceil",  &.{.Float},         .Float);
                try self.reg("round", &.{.Float},         .Float);
                try self.reg("sin",   &.{.Float},         .Float);
                try self.reg("cos",   &.{.Float},         .Float);
                try self.reg("tan",   &.{.Float},         .Float);
                try self.reg("log",   &.{.Float},         .Float);
                try self.reg("log2",  &.{.Float},         .Float);
                try self.reg("min",   &.{.Unknown,.Unknown},          .Unknown);
                try self.reg("max",   &.{.Unknown,.Unknown},          .Unknown);
                try self.reg("clamp", &.{.Unknown,.Unknown,.Unknown}, .Unknown);
            } else if (std.mem.eql(u8, path, "os")) {
                try self.reg("exit",   &.{.Int},    .Void);
                try self.reg("getenv", &.{.String}, .String);
                try self.reg("argc",   &.{},        .Int);
                try self.reg("argv",   &.{.Int},    .String);
            }
        }

        // ── global scope: enum variants ───────────────────────────────────
        var global = Scope.init();
        defer global.deinit(self.allocator);
        var eit = self.enums.iterator();
        while (eit.next()) |entry| {
            for (entry.value_ptr.*) |variant| {
                const key = try std.fmt.allocPrint(self.allocator, "{s}.{s}",
                    .{ entry.key_ptr.*, variant });
                try global.define(self.allocator, key, AshType{ .kind = .Int });
            }
        }

        // ── second pass: analyze every function body ───────────────────────
        for (pd.functions) |func| try self.analyzeFunction(func, &global);
    }

    fn analyzeFunction(self: *Analyzer, func: *Node, parent: *Scope) !void {
        const fd = &func.data.function_decl;
        var scope = Scope.init();
        scope.parent = parent;
        defer scope.deinit(self.allocator);
        for (fd.params) |p|
            try scope.define(self.allocator, p.data.param_decl.name,
                             p.data.param_decl.param_type);
        _ = try self.analyzeBlock(fd.body, &scope);
    }

    fn analyzeBlock(self: *Analyzer, block: *Node, scope: *Scope) !AshType {
        for (block.data.block.stmts) |s| try self.analyzeStmt(s, scope);
        return AshType{ .kind = .Void };
    }

    fn analyzeStmt(self: *Analyzer, stmt: *Node, scope: *Scope) SemanticError!void {
        switch (stmt.kind) {
            .VarDecl => {
                const vd = &stmt.data.var_decl;
                const init_t = try self.analyzeExpr(vd.init_expr, scope);
                const t = vd.var_type orelse init_t;
                try scope.define(self.allocator, vd.name, t);
                stmt.resolved_type = t;
            },
            .ConstDecl => {
                const cd = &stmt.data.const_decl;
                const init_t = try self.analyzeExpr(cd.init_expr, scope);
                const t = cd.const_type orelse init_t;
                try scope.define(self.allocator, cd.name, t);
                stmt.resolved_type = t;
            },
            .MultiVarDecl => {
                // x, y := func_returning_tuple()
                const mv = &stmt.data.multi_var_decl;
                const init_t = try self.analyzeExpr(mv.init_expr, scope);
                if (init_t.kind == .Tuple) {
                    const tt = init_t.tuple_types orelse &[_]AshType{};
                    for (mv.names, 0..) |name, i| {
                        const member_t = if (i < tt.len) tt[i] else AshType{ .kind = .Unknown };
                        try scope.define(self.allocator, name, member_t);
                    }
                } else {
                    // Single-value destructure — just bind all names to the same type
                    for (mv.names) |name|
                        try scope.define(self.allocator, name, init_t);
                }
                stmt.resolved_type = init_t;
            },
            .AssignStmt => {
                const as = &stmt.data.assign_stmt;
                _ = try self.analyzeExpr(as.value, scope);
                _ = try self.analyzeExpr(as.target, scope);
            },
            .CompoundAssignStmt => {
                const ca = &stmt.data.compound_assign_stmt;
                _ = try self.analyzeExpr(ca.value, scope);
                _ = try self.analyzeExpr(ca.target, scope);
            },
            .ExprStmt => {
                const expr = stmt.data.expr_stmt.expr;
                _ = try self.analyzeExpr(expr, scope);
                // Propagate vec element type when we see push(v, x)
                if (expr.kind == .CallExpr) {
                    const ce = &expr.data.call_expr;
                    if (std.mem.eql(u8, ce.callee, "push") and ce.args.len == 2) {
                        const vec_arg = ce.args[0];
                        const val_arg = ce.args[1];
                        if (vec_arg.kind == .IdentExpr) {
                            const vname = vec_arg.data.ident_expr.name;
                            const vt = val_arg.resolved_type orelse AshType{ .kind = .Unknown };
                            if (vt.kind != .Unknown) {
                                const ep = try self.allocator.create(AshType); ep.* = vt;
                                _ = scope.update(vname, AshType{ .kind = .Vec, .elem_type = ep });
                            }
                        }
                    }
                }
            },
            .ReturnStmt => {
                if (stmt.data.return_stmt.value) |v| _ = try self.analyzeExpr(v, scope);
            },
            .IfStmt => {
                const is = &stmt.data.if_stmt;
                _ = try self.analyzeExpr(is.condition, scope);
                _ = try self.analyzeBlock(is.then_block, scope);
                if (is.else_block) |eb| {
                    if (eb.kind == .IfStmt) try self.analyzeStmt(eb, scope)
                    else _ = try self.analyzeBlock(eb, scope);
                }
            },
            .ForRangeStmt => {
                const fr = &stmt.data.for_range_stmt;
                _ = try self.analyzeExpr(fr.start, scope);
                _ = try self.analyzeExpr(fr.end, scope);
                var ls = Scope.init(); ls.parent = scope; defer ls.deinit(self.allocator);
                try ls.define(self.allocator, fr.var_name, AshType{ .kind = .Int });
                _ = try self.analyzeBlock(fr.body, &ls);
            },
            .ForEachStmt => {
                const fe = &stmt.data.for_each_stmt;
                const iter_t = try self.analyzeExpr(fe.iterable, scope);
                const elem_t: AshType = if (iter_t.elem_type) |et| et.* else AshType{ .kind = .Unknown };
                var ls = Scope.init(); ls.parent = scope; defer ls.deinit(self.allocator);
                try ls.define(self.allocator, fe.var_name, elem_t);
                _ = try self.analyzeBlock(fe.body, &ls);
            },
            .WhileStmt => {
                const ws = &stmt.data.while_stmt;
                _ = try self.analyzeExpr(ws.condition, scope);
                _ = try self.analyzeBlock(ws.body, scope);
            },
            .BreakStmt, .ContinueStmt => {},
            .SwitchStmt => {
                const ss = &stmt.data.switch_stmt;
                _ = try self.analyzeExpr(ss.subject, scope);
                for (ss.cases) |case| {
                    if (case.value) |v| _ = try self.analyzeExpr(v, scope);
                    for (case.body) |s| try self.analyzeStmt(s, scope);
                }
            },
            else => {},
        }
    }

    fn analyzeExpr(self: *Analyzer, expr: *Node, scope: *Scope) SemanticError!AshType {
        const t: AshType = switch (expr.kind) {
            .IntLiteral    => AshType{ .kind = .Int },
            .FloatLiteral  => AshType{ .kind = .Float },
            .StringLiteral => AshType{ .kind = .String },
            .BoolLiteral   => AshType{ .kind = .Bool },

            .IdentExpr => blk: {
                const name = expr.data.ident_expr.name;
                if (scope.lookup(name)) |found| break :blk found;
                self.err(expr.line, expr.col, "undefined variable '{s}'", .{name});
                return SemanticError.UndefinedVariable;
            },

            .FieldExpr => blk: {
                const fe = &expr.data.field_expr;
                // Check if this is an enum variant access: EnumName.Variant
                // The object is an IdentExpr whose name matches a known enum.
                if (fe.object.kind == .IdentExpr) {
                    const obj_name = fe.object.data.ident_expr.name;
                    if (self.enums.contains(obj_name)) {
                        // Mark the object IdentExpr as an Enum type (suppress "undefined variable")
                        fe.object.resolved_type = AshType{ .kind = .Enum, .name = obj_name };
                        // Look up "EnumName.Variant" in scope
                        const key = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ obj_name, fe.field });
                        defer self.allocator.free(key);
                        if (scope.lookup(key)) |found| break :blk found;
                        // Variant exists in enum even if not in scope map — return Int
                        break :blk AshType{ .kind = .Int };
                    }
                }
                // Normal field access on a struct instance
                const obj_t = try self.analyzeExpr(fe.object, scope);
                if (obj_t.kind == .Struct or obj_t.kind == .Unknown) {
                    if (self.structs.get(obj_t.name orelse "")) |si| {
                        for (si.fields) |f| {
                            if (std.mem.eql(u8, f.name, fe.field)) break :blk f.field_type;
                        }
                    }
                }
                break :blk AshType{ .kind = .Unknown };
            },

            .StructLiteral => blk: {
                const sl = &expr.data.struct_literal;
                for (sl.fields) |f| _ = try self.analyzeExpr(f.value, scope);
                break :blk AshType{ .kind = .Struct, .name = sl.type_name };
            },

            .TupleExpr => blk: {
                var types = try self.allocator.alloc(AshType, expr.data.tuple_expr.elements.len);
                for (expr.data.tuple_expr.elements, 0..) |elem, i|
                    types[i] = try self.analyzeExpr(elem, scope);
                break :blk AshType{ .kind = .Tuple, .tuple_types = types };
            },

            .BinaryExpr => blk: {
                const be = &expr.data.binary_expr;
                const lt = try self.analyzeExpr(be.left, scope);
                const rt = try self.analyzeExpr(be.right, scope);
                switch (be.op) {
                    .Eq, .Ne, .Lt, .Gt, .Le, .Ge, .And, .Or =>
                        break :blk AshType{ .kind = .Bool },
                    .Add => {
                        // String + anything  or  anything + String  => String
                        if (lt.kind == .String or rt.kind == .String)
                            break :blk AshType{ .kind = .String };
                        if (lt.kind == .Float or rt.kind == .Float)
                            break :blk AshType{ .kind = .Float };
                        break :blk AshType{ .kind = .Int };
                    },
                    else => break :blk if (lt.kind == .Float or rt.kind == .Float)
                        AshType{ .kind = .Float } else AshType{ .kind = .Int },
                }
            },

            .UnaryExpr => blk: {
                const ut = try self.analyzeExpr(expr.data.unary_expr.operand, scope);
                break :blk ut;
            },

            .CallExpr => blk: {
                const ce = &expr.data.call_expr;
                for (ce.args) |arg| _ = try self.analyzeExpr(arg, scope);

                // Build lookup key: "module.func" or "func"
                const key = if (ce.module.len > 0)
                    try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ ce.module, ce.callee })
                else
                    ce.callee;
                defer if (ce.module.len > 0) self.allocator.free(key);

                // Look up: try "module.func", then bare "func"
                const sig_opt = self.functions.get(key) orelse
                    (if (ce.module.len > 0) self.functions.get(ce.callee) else null);

                if (sig_opt) |sig| {
                    // Arg-count check (skip for variadic builtins that take .Unknown params)
                    var is_variadic = false;
                    for (sig.param_types) |pt| if (pt.kind == .Unknown) { is_variadic = true; break; };
                    if (!is_variadic and ce.args.len != sig.param_types.len) {
                        self.err(expr.line, expr.col, "'{s}' expects {} args, got {}",
                            .{ ce.callee, sig.param_types.len, ce.args.len });
                        return SemanticError.WrongArgCount;
                    }
                    // Refine pop/vec_get from the vec's elem type
                    if (sig.return_type.kind == .Unknown and ce.args.len >= 1 and
                        (std.mem.eql(u8, ce.callee, "pop") or std.mem.eql(u8, ce.callee, "vec_get")))
                    {
                        const vt = ce.args[0].resolved_type orelse AshType{ .kind = .Unknown };
                        if (vt.elem_type) |et| break :blk et.*;
                    }
                    break :blk sig.return_type;
                }
                // Unregistered function — tolerate it (could be recursive call resolved later)
                break :blk AshType{ .kind = .Unknown };
            },

            .ArrayLiteral => blk: {
                var et = AshType{ .kind = .Unknown };
                for (expr.data.array_literal.elements) |elem| et = try self.analyzeExpr(elem, scope);
                const ep = try self.allocator.create(AshType); ep.* = et;
                break :blk AshType{ .kind = .Vec, .elem_type = ep };
            },

            .FixedArrayLiteral => blk: {
                var et = AshType{ .kind = .Unknown };
                const elems = expr.data.fixed_array_literal.elements;
                for (elems) |elem| et = try self.analyzeExpr(elem, scope);
                const ep = try self.allocator.create(AshType); ep.* = et;
                break :blk AshType{ .kind = .Array, .elem_type = ep, .array_size = elems.len };
            },

            .IndexExpr => blk: {
                const ie = &expr.data.index_expr;
                const at = try self.analyzeExpr(ie.array, scope);
                _ = try self.analyzeExpr(ie.index, scope);
                if ((at.kind == .Vec or at.kind == .Array) and at.elem_type != null)
                    break :blk at.elem_type.?.*;
                break :blk AshType{ .kind = .Unknown };
            },

            else => AshType{ .kind = .Unknown },
        };
        expr.resolved_type = t;
        return t;
    }
};
