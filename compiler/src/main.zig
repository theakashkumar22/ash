const std = @import("std");
const cli = @import("cli.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Convert [][:0]u8 -> [][]u8
    var plain_args = try allocator.alloc([]u8, args.len);
    defer allocator.free(plain_args);
    for (args, 0..) |a, i| plain_args[i] = a;

    try cli.runCommand(allocator, plain_args);
}
