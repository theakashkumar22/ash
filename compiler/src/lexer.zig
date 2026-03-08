const std = @import("std");

pub const TokenKind = enum {
    // Literals
    Identifier,
    NumberInt,
    NumberFloat,
    StringLit,

    // Keywords
    Fn,
    Import,
    If,
    Else,
    For,
    While,
    Return,
    True,
    False,
    In,
    Const,
    Switch,
    Case,
    Default,
    Break,
    Continue,
    Struct,
    Enum,

    // Types
    TypeInt,
    TypeFloat,
    TypeBool,
    TypeString,

    // Operators
    Plus,
    Minus,
    Star,
    Slash,
    Percent,
    Eq,
    Ne,
    Lt,
    Gt,
    Le,
    Ge,
    And,
    Or,
    Not,
    Assign,
    ColonAssign,
    Arrow,      // =>  (switch case arrow)
    PlusAssign, // +=
    MinusAssign,// -=

    // Symbols
    LParen,
    RParen,
    LBrace,
    RBrace,
    LBracket,
    RBracket,
    Comma,
    Dot,
    DotDot,
    Colon,
    Semicolon,
    Newline,

    // Special
    Eof,
};

pub const Token = struct {
    kind: TokenKind,
    text: []const u8,
    line: u32,
    col: u32,
};

pub const LexError = error{
    UnexpectedCharacter,
    UnterminatedString,
    OutOfMemory,
};

pub const Lexer = struct {
    src: []const u8,
    pos: usize,
    line: u32,
    col: u32,
    allocator: std.mem.Allocator,
    tokens: std.ArrayListUnmanaged(Token),

    pub fn init(allocator: std.mem.Allocator, src: []const u8) Lexer {
        return Lexer{ .src = src, .pos = 0, .line = 1, .col = 1,
                      .allocator = allocator, .tokens = .{} };
    }

    pub fn deinit(self: *Lexer) void { self.tokens.deinit(self.allocator); }

    fn peek(self: *Lexer) ?u8 {
        if (self.pos >= self.src.len) return null;
        return self.src[self.pos];
    }
    fn peekAt(self: *Lexer, offset: usize) ?u8 {
        const idx = self.pos + offset;
        if (idx >= self.src.len) return null;
        return self.src[idx];
    }
    fn advance(self: *Lexer) ?u8 {
        if (self.pos >= self.src.len) return null;
        const c = self.src[self.pos];
        self.pos += 1;
        if (c == '\n') { self.line += 1; self.col = 1; } else { self.col += 1; }
        return c;
    }

    fn skipWhitespaceAndComments(self: *Lexer) void {
        while (self.peek()) |c| {
            if (c == ' ' or c == '\t' or c == '\r') {
                _ = self.advance();
            } else if (c == '/' and self.peekAt(1) == '/') {
                while (self.peek()) |cc| { if (cc == '\n') break; _ = self.advance(); }
            } else break;
        }
    }

    fn readString(self: *Lexer) LexError!Token {
        const sl = self.line; const sc = self.col; const start = self.pos;
        _ = self.advance();
        while (self.peek()) |c| {
            if (c == '"')  { _ = self.advance(); return Token{ .kind = .StringLit, .text = self.src[start..self.pos], .line = sl, .col = sc }; }
            if (c == '\\') { _ = self.advance(); _ = self.advance(); continue; }
            if (c == '\n') return LexError.UnterminatedString;
            _ = self.advance();
        }
        return LexError.UnterminatedString;
    }

    fn readNumber(self: *Lexer) Token {
        const sl = self.line; const sc = self.col; const start = self.pos;
        var is_float = false;
        while (self.peek()) |c| {
            if (std.ascii.isDigit(c)) { _ = self.advance(); }
            else if (c == '.' and self.peekAt(1) != '.') { is_float = true; _ = self.advance(); }
            else break;
        }
        return Token{ .kind = if (is_float) .NumberFloat else .NumberInt,
                      .text = self.src[start..self.pos], .line = sl, .col = sc };
    }

    fn readIdentOrKeyword(self: *Lexer) Token {
        const sl = self.line; const sc = self.col; const start = self.pos;
        while (self.peek()) |c| {
            if (std.ascii.isAlphanumeric(c) or c == '_') { _ = self.advance(); } else break;
        }
        const text = self.src[start..self.pos];
        return Token{ .kind = keywordKind(text), .text = text, .line = sl, .col = sc };
    }

    fn keywordKind(text: []const u8) TokenKind {
        const keywords = .{
            .{ "fn",       TokenKind.Fn },
            .{ "import",   TokenKind.Import },
            .{ "if",       TokenKind.If },
            .{ "else",     TokenKind.Else },
            .{ "for",      TokenKind.For },
            .{ "while",    TokenKind.While },
            .{ "return",   TokenKind.Return },
            .{ "true",     TokenKind.True },
            .{ "false",    TokenKind.False },
            .{ "in",       TokenKind.In },
            .{ "const",    TokenKind.Const },
            .{ "switch",   TokenKind.Switch },
            .{ "case",     TokenKind.Case },
            .{ "default",  TokenKind.Default },
            .{ "break",    TokenKind.Break },
            .{ "continue", TokenKind.Continue },
            .{ "struct",   TokenKind.Struct },
            .{ "enum",     TokenKind.Enum },
            .{ "int",      TokenKind.TypeInt },
            .{ "float",    TokenKind.TypeFloat },
            .{ "bool",     TokenKind.TypeBool },
            .{ "string",   TokenKind.TypeString },
        };
        inline for (keywords) |kw| {
            if (std.mem.eql(u8, text, kw[0])) return kw[1];
        }
        return .Identifier;
    }

    pub fn tokenize(self: *Lexer) LexError![]Token {
        while (true) {
            self.skipWhitespaceAndComments();
            const c = self.peek() orelse {
                try self.tokens.append(self.allocator, Token{ .kind = .Eof, .text = "", .line = self.line, .col = self.col });
                break;
            };
            const tl = self.line; const tc = self.col;
            if (c == '\n') {
                _ = self.advance();
                try self.tokens.append(self.allocator, Token{ .kind = .Newline, .text = "\n", .line = tl, .col = tc });
                continue;
            }
            if (c == '"')               { try self.tokens.append(self.allocator, try self.readString()); continue; }
            if (std.ascii.isDigit(c))   { try self.tokens.append(self.allocator, self.readNumber()); continue; }
            if (std.ascii.isAlphabetic(c) or c == '_') { try self.tokens.append(self.allocator, self.readIdentOrKeyword()); continue; }

            _ = self.advance();
            const next = self.peek();
            const tok: Token = switch (c) {
                '+' => blk: {
                    if (next == '=') { _ = self.advance(); break :blk Token{ .kind = .PlusAssign,  .text = "+=", .line = tl, .col = tc }; }
                    break :blk Token{ .kind = .Plus, .text = "+", .line = tl, .col = tc };
                },
                '-' => blk: {
                    if (next == '=') { _ = self.advance(); break :blk Token{ .kind = .MinusAssign, .text = "-=", .line = tl, .col = tc }; }
                    break :blk Token{ .kind = .Minus, .text = "-", .line = tl, .col = tc };
                },
                '*' => Token{ .kind = .Star,     .text = "*",  .line = tl, .col = tc },
                '/' => Token{ .kind = .Slash,    .text = "/",  .line = tl, .col = tc },
                '%' => Token{ .kind = .Percent,  .text = "%",  .line = tl, .col = tc },
                '(' => Token{ .kind = .LParen,   .text = "(",  .line = tl, .col = tc },
                ')' => Token{ .kind = .RParen,   .text = ")",  .line = tl, .col = tc },
                '{' => Token{ .kind = .LBrace,   .text = "{",  .line = tl, .col = tc },
                '}' => Token{ .kind = .RBrace,   .text = "}",  .line = tl, .col = tc },
                '[' => Token{ .kind = .LBracket, .text = "[",  .line = tl, .col = tc },
                ']' => Token{ .kind = .RBracket, .text = "]",  .line = tl, .col = tc },
                ',' => Token{ .kind = .Comma,    .text = ",",  .line = tl, .col = tc },
                ';' => Token{ .kind = .Semicolon,.text = ";",  .line = tl, .col = tc },
                ':' => blk: {
                    if (next == '=') { _ = self.advance(); break :blk Token{ .kind = .ColonAssign, .text = ":=", .line = tl, .col = tc }; }
                    break :blk Token{ .kind = .Colon, .text = ":", .line = tl, .col = tc };
                },
                '.' => blk: {
                    if (next == '.') { _ = self.advance(); break :blk Token{ .kind = .DotDot, .text = "..", .line = tl, .col = tc }; }
                    break :blk Token{ .kind = .Dot, .text = ".", .line = tl, .col = tc };
                },
                '=' => blk: {
                    if (next == '=') { _ = self.advance(); break :blk Token{ .kind = .Eq,     .text = "==", .line = tl, .col = tc }; }
                    if (next == '>') { _ = self.advance(); break :blk Token{ .kind = .Arrow,  .text = "=>", .line = tl, .col = tc }; }
                    break :blk Token{ .kind = .Assign, .text = "=", .line = tl, .col = tc };
                },
                '!' => blk: {
                    if (next == '=') { _ = self.advance(); break :blk Token{ .kind = .Ne, .text = "!=", .line = tl, .col = tc }; }
                    break :blk Token{ .kind = .Not, .text = "!", .line = tl, .col = tc };
                },
                '<' => blk: {
                    if (next == '=') { _ = self.advance(); break :blk Token{ .kind = .Le, .text = "<=", .line = tl, .col = tc }; }
                    break :blk Token{ .kind = .Lt, .text = "<", .line = tl, .col = tc };
                },
                '>' => blk: {
                    if (next == '=') { _ = self.advance(); break :blk Token{ .kind = .Ge, .text = ">=", .line = tl, .col = tc }; }
                    break :blk Token{ .kind = .Gt, .text = ">", .line = tl, .col = tc };
                },
                '&' => blk: {
                    if (next == '&') { _ = self.advance(); break :blk Token{ .kind = .And, .text = "&&", .line = tl, .col = tc }; }
                    return LexError.UnexpectedCharacter;
                },
                '|' => blk: {
                    if (next == '|') { _ = self.advance(); break :blk Token{ .kind = .Or, .text = "||", .line = tl, .col = tc }; }
                    return LexError.UnexpectedCharacter;
                },
                else => return LexError.UnexpectedCharacter,
            };
            try self.tokens.append(self.allocator, tok);
        }
        return self.tokens.items;
    }
};
