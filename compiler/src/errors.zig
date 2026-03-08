const std = @import("std");

pub const ErrorKind = enum {
    Lex,
    Parse,
    Semantic,
    Codegen,
    IO,
    System,
};

pub const AshError = struct {
    kind: ErrorKind,
    filename: []const u8,
    line: u32,
    col: u32,
    message: []const u8,

    pub fn print(self: AshError) void {
        std.debug.print("{s}:{}:{}: {s} error: {s}\n", .{
            self.filename,
            self.line,
            self.col,
            @tagName(self.kind),
            self.message,
        });
    }
};

pub fn fatalError(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print("ash: error: " ++ fmt ++ "\n", args);
    std.process.exit(1);
}

pub fn fatalMsg(msg: []const u8) noreturn {
    std.debug.print("ash: error: {s}\n", .{msg});
    std.process.exit(1);
}
