const std = @import("std");
const builtin = @import("builtin");
const utils = @import("utils.zig");
const errors = @import("errors.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const ast = @import("ast.zig");
const semantic = @import("semantic.zig");
const codegen = @import("codegen_c.zig");

const ASH_VERSION = "0.1.0";

pub fn runCommand(allocator: std.mem.Allocator, args: [][]u8) !void {
    if (args.len < 2) { printHelp(); return; }

    const cmd = args[1];

    if (std.mem.eql(u8, cmd, "version") or std.mem.eql(u8, cmd, "--version")) {
        std.debug.print("ash version {s}\n", .{ASH_VERSION});
        return;
    }
    if (std.mem.eql(u8, cmd, "help") or std.mem.eql(u8, cmd, "--help")) {
        printHelp();
        return;
    }
    if (std.mem.eql(u8, cmd, "init")) {
        try cmdInit(allocator);
        return;
    }
    if (std.mem.eql(u8, cmd, "run")) {
        if (args.len < 3) errors.fatalMsg("Usage: ash run <file.ash>");
        try cmdRun(allocator, args[2]);
        return;
    }
    if (std.mem.eql(u8, cmd, "build")) {
        if (args.len < 3) errors.fatalMsg("Usage: ash build <file.ash>");
        try cmdBuild(allocator, args[2]);
        return;
    }

    std.debug.print("ash: unknown command '{s}'\n", .{cmd});
    printHelp();
    std.process.exit(1);
}

fn printHelp() void {
    std.debug.print(
        \\Ash Programming Language - v{s}
        \\
        \\Usage:
        \\  ash <command> [arguments]
        \\
        \\Commands:
        \\  ash init              Initialize a new Ash project
        \\  ash run <file.ash>    Compile and run an Ash program
        \\  ash build <file.ash>  Compile an Ash program to binary
        \\  ash version           Print Ash version
        \\  ash help              Show this help message
        \\
        \\Examples:
        \\  ash init
        \\  ash run main.ash
        \\  ash build main.ash
        \\
    , .{ASH_VERSION});
}

fn cmdInit(allocator: std.mem.Allocator) !void {
    _ = allocator;
    const main_content =
        \\import io
        \\
        \\fn main() {
        \\    print("Hello, World!")
        \\}
        \\
    ;
    const file = std.fs.cwd().createFile("main.ash", .{ .exclusive = true }) catch |e| {
        if (e == error.PathAlreadyExists) {
            std.debug.print("ash: main.ash already exists\n", .{});
            return;
        }
        return e;
    };
    defer file.close();
    try file.writeAll(main_content);
    std.debug.print("Initialized Ash project\n", .{});
    std.debug.print("Created: main.ash\n", .{});
    std.debug.print("Run with: ash run main.ash\n", .{});
}

// ─────────────────────────────────────────────────────────────────────────────
// Runtime discovery
//
// Install layout (recommended):
//   Windows:  C:\Users\<user>\ash\bin\ash.exe
//             C:\Users\<user>\ash\runtime\ash_runtime.c
//             C:\Users\<user>\ash\runtime\ash_runtime.h
//
//   Unix:     /usr/local/bin/ash
//             /usr/local/lib/ash/runtime/ash_runtime.c
//             /usr/local/lib/ash/runtime/ash_runtime.h
//
// The compiler resolves runtime relative to the exe using selfExePath.
// ─────────────────────────────────────────────────────────────────────────────

/// Returns the absolute path to the directory containing ash.exe. Caller frees.
fn exeDir(allocator: std.mem.Allocator) ![]u8 {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const exe_path = try std.fs.selfExePath(&buf);
    const dir = std.fs.path.dirname(exe_path) orelse ".";
    return allocator.dupe(u8, dir);
}

/// Probe candidate absolute paths for a file. Returns first found. Caller frees.
fn findFile(allocator: std.mem.Allocator, candidates: []const []const u8) ![]u8 {
    for (candidates) |path| {
        std.fs.accessAbsolute(path, .{}) catch continue;
        return allocator.dupe(u8, path);
    }
    return error.NotFound;
}

/// Build the list of candidate paths for the runtime directory and return the
/// first one that contains ash_runtime.h. Caller frees returned path.
fn findRuntimeDir(allocator: std.mem.Allocator) ![]u8 {
    const exe = try exeDir(allocator);
    defer allocator.free(exe);

    // Candidate runtime dirs, in priority order:
    //   1. <exedir>/../runtime   (e.g. ash/bin/ash.exe  → ash/runtime/)
    //   2. <exedir>/runtime      (e.g. ash/ash.exe      → ash/runtime/)
    //   3. <exedir>/../../runtime (development: zig-out/bin/ash.exe → runtime/)
    const rel_candidates = [_][]const u8{
        "../runtime",
        "runtime",
        "../../runtime",
    };

    for (rel_candidates) |rel| {
        const dir = try std.fs.path.join(allocator, &.{ exe, rel });
        defer allocator.free(dir);
        const header = try std.fs.path.join(allocator, &.{ dir, "ash_runtime.h" });
        defer allocator.free(header);
        std.fs.accessAbsolute(header, .{}) catch continue;
        // Resolve to a clean absolute path
        var real_buf: [std.fs.max_path_bytes]u8 = undefined;
        const resolved = std.fs.realpath(dir, &real_buf) catch continue;
        return allocator.dupe(u8, resolved);
    }

    return error.RuntimeNotFound;
}

/// Returns absolute path to ash_runtime.c. Caller frees.
fn findRuntimeC(allocator: std.mem.Allocator) ![]u8 {
    const dir = try findRuntimeDir(allocator);
    defer allocator.free(dir);
    const path = try std.fs.path.join(allocator, &.{ dir, "ash_runtime.c" });
    std.fs.accessAbsolute(path, .{}) catch {
        allocator.free(path);
        return error.RuntimeNotFound;
    };
    return path;
}

// ─────────────────────────────────────────────────────────────────────────────
// Temp dir
// ─────────────────────────────────────────────────────────────────────────────

fn getTempDir(allocator: std.mem.Allocator) ![]u8 {
    if (builtin.os.tag == .windows) {
        return std.process.getEnvVarOwned(allocator, "TEMP") catch
            std.process.getEnvVarOwned(allocator, "TMP") catch
            allocator.dupe(u8, "C:\\Temp");
    }
    return allocator.dupe(u8, "/tmp");
}

fn exeExt() []const u8 {
    return if (builtin.os.tag == .windows) ".exe" else "";
}

// ─────────────────────────────────────────────────────────────────────────────
// Child process helper
// ─────────────────────────────────────────────────────────────────────────────

fn runChild(allocator: std.mem.Allocator, argv: []const []const u8) !u8 {
    var child = std.process.Child.init(argv, allocator);
    child.stdin_behavior  = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    const term = try child.spawnAndWait();
    return switch (term) {
        .Exited => |code| code,
        else    => 1,
    };
}

// ─────────────────────────────────────────────────────────────────────────────
// Compile .ash → C code in memory
// ─────────────────────────────────────────────────────────────────────────────

pub fn compileFile(allocator: std.mem.Allocator, source_path: []const u8) !struct {
    c_code: []u8,
    output_name: []const u8,
} {
    const src = utils.readFile(allocator, source_path) catch |e| {
        std.debug.print("ash: cannot read '{s}': {}\n", .{ source_path, e });
        std.process.exit(1);
    };
    defer allocator.free(src);

    const filename = utils.basename(source_path);

    var lex = lexer.Lexer.init(allocator, src);
    defer lex.deinit();
    const tokens = lex.tokenize() catch |e| {
        std.debug.print("ash: lex error in '{s}': {}\n", .{ filename, e });
        std.process.exit(1);
    };

    var pars = parser.Parser.init(allocator, tokens, filename);
    const program = pars.parseProgram() catch |e| {
        std.debug.print("ash: parse error in '{s}': {}\n", .{ filename, e });
        std.process.exit(1);
    };

    var analyzer = semantic.Analyzer.init(allocator, filename);
    defer analyzer.deinit();
    analyzer.analyze(program) catch |e| {
        std.debug.print("ash: semantic error in '{s}': {}\n", .{ filename, e });
        std.process.exit(1);
    };

    var cg = codegen.Codegen.init(allocator);
    defer cg.deinit();
    cg.generate(program) catch |e| {
        std.debug.print("ash: codegen error in '{s}': {}\n", .{ filename, e });
        std.process.exit(1);
    };

    const c_code = try allocator.dupe(u8, cg.result());
    const output_name = try allocator.dupe(u8, utils.stripExtension(filename));
    return .{ .c_code = c_code, .output_name = output_name };
}

// ─────────────────────────────────────────────────────────────────────────────
// ash run / ash build
// ─────────────────────────────────────────────────────────────────────────────

fn cmdRun(allocator: std.mem.Allocator, source_path: []const u8) !void {
    const result = try compileFile(allocator, source_path);
    defer allocator.free(result.c_code);
    defer allocator.free(result.output_name);

    // Write generated C to temp
    const tmp_dir = try getTempDir(allocator);
    defer allocator.free(tmp_dir);

    const c_name   = try std.fmt.allocPrint(allocator, "ash_{s}.c", .{result.output_name});
    defer allocator.free(c_name);
    const c_file   = try std.fs.path.join(allocator, &.{ tmp_dir, c_name });
    defer allocator.free(c_file);

    const bin_name = try std.fmt.allocPrint(allocator, "ash_{s}{s}", .{ result.output_name, exeExt() });
    defer allocator.free(bin_name);
    const out_bin  = try std.fs.path.join(allocator, &.{ tmp_dir, bin_name });
    defer allocator.free(out_bin);

    utils.writeFile(c_file, result.c_code) catch |e| {
        std.debug.print("ash: cannot write temp file '{s}': {}\n", .{ c_file, e });
        std.process.exit(1);
    };

    // Locate runtime
    const runtime_c = findRuntimeC(allocator) catch {
        printRuntimeHelp();
        std.process.exit(1);
    };
    defer allocator.free(runtime_c);

    const runtime_dir = findRuntimeDir(allocator) catch {
        printRuntimeHelp();
        std.process.exit(1);
    };
    defer allocator.free(runtime_dir);

    const inc_flag = try std.fmt.allocPrint(allocator, "-I{s}", .{runtime_dir});
    defer allocator.free(inc_flag);

    const cc_argv = [_][]const u8{
        "zig", "cc", c_file, runtime_c, inc_flag,
        "-O2", "-o", out_bin, "-std=gnu99", "-lm",
        "-Xlinker", "/pdb:nul", // suppress .pdb on Windows (no-op on Unix)
    };
    const cc_exit = runChild(allocator, &cc_argv) catch |e| {
        std.debug.print("ash: failed to invoke 'zig cc': {}\n      Is 'zig' in your PATH?\n", .{e});
        std.process.exit(1);
    };
    if (cc_exit != 0) {
        std.debug.print("ash: compilation failed\n", .{});
        std.process.exit(1);
    }

    const run_argv = [_][]const u8{out_bin};
    const run_exit = runChild(allocator, &run_argv) catch |e| {
        std.debug.print("ash: failed to run '{s}': {}\n", .{ out_bin, e });
        std.process.exit(1);
    };
    std.process.exit(run_exit);
}

fn cmdBuild(allocator: std.mem.Allocator, source_path: []const u8) !void {
    const result = try compileFile(allocator, source_path);
    defer allocator.free(result.c_code);
    defer allocator.free(result.output_name);

    const tmp_dir = try getTempDir(allocator);
    defer allocator.free(tmp_dir);

    const c_name = try std.fmt.allocPrint(allocator, "ash_{s}.c", .{result.output_name});
    defer allocator.free(c_name);
    const c_file = try std.fs.path.join(allocator, &.{ tmp_dir, c_name });
    defer allocator.free(c_file);

    utils.writeFile(c_file, result.c_code) catch |e| {
        std.debug.print("ash: cannot write temp file: {}\n", .{e});
        std.process.exit(1);
    };

    const runtime_c = findRuntimeC(allocator) catch {
        printRuntimeHelp();
        std.process.exit(1);
    };
    defer allocator.free(runtime_c);

    const runtime_dir = findRuntimeDir(allocator) catch {
        printRuntimeHelp();
        std.process.exit(1);
    };
    defer allocator.free(runtime_dir);

    const inc_flag = try std.fmt.allocPrint(allocator, "-I{s}", .{runtime_dir});
    defer allocator.free(inc_flag);

    const out_bin = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.output_name, exeExt() });
    defer allocator.free(out_bin);

    const cc_argv = [_][]const u8{
        "zig", "cc", c_file, runtime_c, inc_flag,
        "-O2", "-o", out_bin, "-std=gnu99", "-lm",
        "-Xlinker", "/pdb:nul", // suppress .pdb on Windows (no-op on Unix)
    };
    const cc_exit = runChild(allocator, &cc_argv) catch |e| {
        std.debug.print("ash: failed to invoke 'zig cc': {}\n", .{e});
        std.process.exit(1);
    };

    if (cc_exit == 0) {
        std.debug.print("Built: {s}\n", .{out_bin});
    } else {
        std.debug.print("ash: build failed\n", .{});
        std.process.exit(1);
    }
}

fn printRuntimeHelp() void {
    std.debug.print(
        \\ash: cannot find runtime files (ash_runtime.c / ash_runtime.h)
        \\
        \\Expected install layout:
        \\
        \\  Windows:
        \\    C:\Users\<you>\ash\bin\ash.exe        ← add this to PATH
        \\    C:\Users\<you>\ash\runtime\ash_runtime.c
        \\    C:\Users\<you>\ash\runtime\ash_runtime.h
        \\
        \\  Unix/macOS:
        \\    /usr/local/bin/ash                    ← already in PATH
        \\    /usr/local/lib/ash/runtime/ash_runtime.c
        \\    /usr/local/lib/ash/runtime/ash_runtime.h
        \\
        \\The compiler resolves runtime/ relative to the ash executable.
        \\Make sure ash.exe is inside a bin/ folder next to the runtime/ folder.
        \\
    , .{});
}
