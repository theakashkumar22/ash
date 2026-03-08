const std = @import("std");

pub const NodeKind = enum {
    Program,
    ImportDecl,
    FunctionDecl,
    ParamDecl,
    VarDecl,
    ConstDecl,
    MultiVarDecl,    // x, y := func_returning_tuple()
    Block,
    ReturnStmt,
    IfStmt,
    ForRangeStmt,
    ForEachStmt,
    WhileStmt,
    BreakStmt,
    ContinueStmt,
    SwitchStmt,
    ExprStmt,
    AssignStmt,
    CompoundAssignStmt,
    StructDecl,
    EnumDecl,
    BinaryExpr,
    UnaryExpr,
    CallExpr,
    IndexExpr,
    FieldExpr,
    StructLiteral,
    TupleExpr,       // return a, b
    IdentExpr,
    IntLiteral,
    FloatLiteral,
    StringLiteral,
    BoolLiteral,
    ArrayLiteral,
    FixedArrayLiteral,
};

pub const TypeKind = enum {
    Int, Float, Bool, String, Void,
    Array,   // fixed  ![...]
    Vec,     // dynamic [...]
    Tuple,   // (int, string, float) multi-return
    Struct,
    Enum,
    Unknown,
};

pub const AshType = struct {
    kind: TypeKind,
    elem_type:   ?*AshType  = null, // Vec / Array element type
    tuple_types: ?[]AshType = null, // Tuple member types
    name: ?[]const u8 = null,       // Struct / Enum name
    array_size: ?usize = null,      // fixed Array: element count

    pub fn format(self: AshType, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt; _ = options;
        switch (self.kind) {
            .Int    => try writer.writeAll("int"),
            .Float  => try writer.writeAll("float"),
            .Bool   => try writer.writeAll("bool"),
            .String => try writer.writeAll("string"),
            .Void   => try writer.writeAll("void"),
            .Array  => { if (self.elem_type) |et| try writer.print("{}[]", .{et.*}) else try writer.writeAll("unknown[]"); },
            .Vec    => { if (self.elem_type) |et| try writer.print("vec<{}>", .{et.*}) else try writer.writeAll("vec<?>"); },
            .Tuple  => try writer.writeAll("tuple"),
            .Tuple  => try writer.writeAll("tuple"),
            .Struct => try writer.print("struct:{s}", .{self.name orelse "?"}),
            .Enum   => try writer.print("enum:{s}",   .{self.name orelse "?"}),
            .Unknown => try writer.writeAll("unknown"),
        }
    }
};

pub const BinaryOp   = enum { Add, Sub, Mul, Div, Mod, Eq, Ne, Lt, Gt, Le, Ge, And, Or };
pub const UnaryOp    = enum { Neg, Not };
pub const CompoundOp = enum { AddAssign, SubAssign };

pub const Node = struct {
    kind: NodeKind,
    line: u32,
    col:  u32,
    data: NodeData,
    resolved_type: ?AshType = null,
};

pub const NodeData = union {
    program:              ProgramData,
    import_decl:          ImportDeclData,
    function_decl:        FunctionDeclData,
    param_decl:           ParamDeclData,
    var_decl:             VarDeclData,
    const_decl:           ConstDeclData,
    multi_var_decl:       MultiVarDeclData,
    block:                BlockData,
    return_stmt:          ReturnStmtData,
    if_stmt:              IfStmtData,
    for_range_stmt:       ForRangeStmtData,
    for_each_stmt:        ForEachStmtData,
    while_stmt:           WhileStmtData,
    break_stmt:           BreakStmtData,
    continue_stmt:        ContinueStmtData,
    switch_stmt:          SwitchStmtData,
    expr_stmt:            ExprStmtData,
    assign_stmt:          AssignStmtData,
    compound_assign_stmt: CompoundAssignStmtData,
    struct_decl:          StructDeclData,
    enum_decl:            EnumDeclData,
    binary_expr:          BinaryExprData,
    unary_expr:           UnaryExprData,
    call_expr:            CallExprData,
    index_expr:           IndexExprData,
    field_expr:           FieldExprData,
    struct_literal:       StructLiteralData,
    tuple_expr:           TupleExprData,
    ident_expr:           IdentExprData,
    int_literal:          IntLiteralData,
    float_literal:        FloatLiteralData,
    string_literal:       StringLiteralData,
    bool_literal:         BoolLiteralData,
    array_literal:        ArrayLiteralData,
    fixed_array_literal:  FixedArrayLiteralData,
};

pub const ProgramData       = struct { imports: []*Node, functions: []*Node, structs: []*Node, enums: []*Node };
pub const ImportDeclData    = struct { path: []const u8 };
pub const FunctionDeclData  = struct { name: []const u8, params: []*Node, return_type: ?AshType, body: *Node };
pub const ParamDeclData     = struct { name: []const u8, param_type: AshType };
pub const VarDeclData       = struct { name: []const u8, init_expr: *Node, var_type: ?AshType };
pub const ConstDeclData     = struct { name: []const u8, init_expr: *Node, const_type: ?AshType };
pub const MultiVarDeclData  = struct { names: [][]const u8, init_expr: *Node };
pub const BlockData         = struct { stmts: []*Node };
pub const ReturnStmtData    = struct { value: ?*Node };
pub const IfStmtData        = struct { condition: *Node, then_block: *Node, else_block: ?*Node };
pub const ForRangeStmtData  = struct { var_name: []const u8, start: *Node, end: *Node, body: *Node };
pub const ForEachStmtData   = struct { var_name: []const u8, iterable: *Node, body: *Node };
pub const WhileStmtData     = struct { condition: *Node, body: *Node };
pub const BreakStmtData     = struct { dummy: u8 = 0 };
pub const ContinueStmtData  = struct { dummy: u8 = 0 };
pub const SwitchCaseData    = struct { value: ?*Node, body: []*Node };
pub const SwitchStmtData    = struct { subject: *Node, cases: []SwitchCaseData };
pub const ExprStmtData      = struct { expr: *Node };
pub const AssignStmtData    = struct { target: *Node, value: *Node };
pub const CompoundAssignStmtData = struct { target: *Node, value: *Node, op: CompoundOp };
pub const StructFieldData   = struct { name: []const u8, field_type: AshType };
pub const StructDeclData    = struct { name: []const u8, fields: []StructFieldData };
pub const EnumDeclData      = struct { name: []const u8, variants: [][]const u8 };
pub const BinaryExprData    = struct { op: BinaryOp, left: *Node, right: *Node };
pub const UnaryExprData     = struct { op: UnaryOp, operand: *Node };
pub const CallExprData      = struct { module: []const u8, callee: []const u8, args: []*Node };
pub const IndexExprData     = struct { array: *Node, index: *Node };
pub const FieldExprData     = struct { object: *Node, field: []const u8 };
pub const StructLiteralData = struct { type_name: []const u8, fields: []StructLiteralFieldData };
pub const StructLiteralFieldData = struct { name: []const u8, value: *Node };
pub const TupleExprData     = struct { elements: []*Node };
pub const IdentExprData     = struct { name: []const u8 };
pub const IntLiteralData    = struct { value: i64 };
pub const FloatLiteralData  = struct { value: f64 };
pub const StringLiteralData = struct { value: []const u8 };
pub const BoolLiteralData   = struct { value: bool };
pub const ArrayLiteralData  = struct { elements: []*Node };
pub const FixedArrayLiteralData = struct { elements: []*Node };
