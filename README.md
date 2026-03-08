# Ash Programming Language

Ash is a minimalist, statically-typed systems language with a clean, readable syntax. You write Ash, the compiler translates it to C, and `zig cc` turns that C into a native binary — no VM, no garbage collector, no runtime overhead.

```ash
fn fib(n: int): int {
    if n <= 1 { return n }
    return fib(n - 1) + fib(n - 2)
}

fn main() {
    for i in 0..10 {
        print("fib(", i, ") =", fib(i))
    }
}
```

---

## Why compile to C?

Writing a language that compiles directly to machine code requires building or embedding an entire backend — instruction selection, register allocation, platform ABI handling, and so on. That is a large, ongoing engineering effort. Ash takes a different path: it compiles to **clean, readable C99**, then hands that C off to a battle-tested compiler.

This gives Ash several things for free:

- Mature optimizations from LLVM (via `zig cc`) without having to implement them
- Correct code generation on every platform LLVM supports
- A generated C file you can actually read and inspect if something goes wrong
- A tiny, auditable compiler codebase focused purely on language semantics

## Why `zig cc` instead of `gcc` or `clang`?

`zig cc` is a drop-in C compiler that ships as a **single self-contained binary** alongside Zig — no separate LLVM installation, no system build tools, no platform-specific setup. Because Ash already requires Zig to build itself (the compiler is written in Zig), every user already has `zig cc` available for free.

Concretely, every `ash run` or `ash build` invocation runs:

```
zig cc <generated>.c ash_runtime.c -I<runtime_dir> -O2 -std=gnu99 -lm -o <output>
```

The same command works unchanged on Linux, macOS, and Windows. On Windows it also suppresses `.pdb` debug databases automatically. There is nothing else to install.

---

## How it works

When you run `ash run hello.ash` or `ash build hello.ash`, the compiler runs five phases entirely in memory:

```
hello.ash
    │
    ▼
 Lexer          tokenizes source into a flat token stream
    │           (identifiers, literals, operators, keywords…)
    ▼
 Parser         builds an Abstract Syntax Tree (AST)
    │           (FunctionDecl, IfStmt, ForRangeStmt, BinaryExpr…)
    ▼
 Semantic       type-checks the AST, resolves names,
 Analysis       validates struct fields and enum variants,
    │           infers types for := declarations,
    │           handles forward declarations so functions
    │           can be called before they are defined
    ▼
 C Codegen      walks the AST and emits a single .c file
    │           (includes ash_runtime.h, emits forward prototypes,
    │            struct and enum declarations, then function bodies)
    ▼
 zig cc         compiles the generated C together with
                ash_runtime.c into a native binary
```

For `ash run`, the binary is placed in the system temp directory and executed immediately. For `ash build`, it lands in the current directory.

Error messages include filename, line, column, and which phase failed:

```
hello.ash:4:12: semantic error: undefined variable 'nme'
```

---

## Requirements

- **[Zig 0.15+](https://ziglang.org/download/)** — used to build the Ash compiler and to compile every Ash program via `zig cc`

---

## Install

### Linux / macOS

```bash
git clone https://github.com/yourname/ash
cd ash
chmod +x install.sh
./install.sh
```

Installs to `~/.local/share/ash/` and adds `ash` to your PATH via `~/.bashrc` / `~/.zshrc`.

### Windows

```bat
git clone https://github.com/yourname/ash
cd ash
install.bat
```

Installs to `%USERPROFILE%\AppData\Local\ash\` and adds `ash` to your user PATH via the registry.

### Manual (any platform)

```bash
zig build -Doptimize=ReleaseFast
```

The compiler locates `runtime/` relative to its own executable, so the layout must be:

```
ash/
  bin/ash          ← add this folder to PATH
  runtime/
    ash_runtime.c
    ash_runtime.h
```

---

## Usage

```bash
ash version           # print version
ash help              # show help
ash init              # create a starter main.ash in the current directory
ash run main.ash      # compile and run immediately
ash build main.ash    # compile to ./main (or main.exe on Windows)
```

---

## Language

### Variables

Type is inferred from the right-hand side with `:=`. You can also annotate explicitly.

```ash
x := 10                  // inferred int
name: string = "Ash"     // explicit annotation
flag: bool = true

const MAX = 100          // immutable, inferred
const LIMIT: int = 50    // immutable, annotated
```

### Operators

```ash
// Arithmetic
x + y    x - y    x * y    x / y    x % y

// Comparison
x == y   x != y   x < y   x > y   x <= y   x >= y

// Logical
x && y   x || y   !x

// Compound assignment
x += 5
x -= 2
```

### Functions

Functions can be defined in any order. The compiler does a forward-declaration pass first, so you can call a function before it appears in the file.

```ash
fn add(a: int, b: int): int {
    return a + b
}

fn greet(name: string): string {
    return "Hello, " + name + "!"
}

fn main() {
    print(add(3, 4))       // 7
    print(greet("World"))  // Hello, World!
}
```

#### Multiple return values

```ash
fn swap(a: int, b: int): (int, int) {
    return b, a
}

fn divmod(a: int, b: int): (int, int) {
    return a / b, a % b
}

fn rgb(hex: int): (int, int, int) {
    return (hex / 65536) % 256, (hex / 256) % 256, hex % 256
}

fn main() {
    x, y      := swap(10, 20)
    q, r      := divmod(17, 5)
    re, g, b  := rgb(16744448)
}
```

### Control Flow

#### if / else if / else

```ash
if x > 0 {
    print("positive")
} else if x == 0 {
    print("zero")
} else {
    print("negative")
}
```

#### for over a range

```ash
for i in 0..5 {
    print(i)    // 0, 1, 2, 3, 4  (end is exclusive)
}
```

#### for over a collection

```ash
a := [10, 20, 30]
for n in a {
    print(n)
}
```

#### while

```ash
x := 10
while x > 0 {
    x -= 1
}
```

#### break / continue

```ash
i := 0
while i < 10 {
    i += 1
    if i == 3 { continue }
    if i == 6 { break }
    print(i)
}
```

#### switch

Works on both integers and strings. Each case uses `=>` for a single expression.

```ash
switch val {
    case 1 => print("one")
    case 2 => print("two")
    default => print("other")
}

switch lang {
    case "ash" => print("Ash!")
    case "zig" => print("Zig!")
    default    => print("unknown")
}
```

### Structs

```ash
struct Point {
    x: int
    y: int
}

struct Person {
    name: string
    age:  int
}

fn greet(p: Person): string {
    return "Hello, " + p.name
}

fn main() {
    p := Point{ x: 10, y: 20 }
    print(p.x, p.y)
    p.x = 99

    alice := Person{ name: "Alice", age: 30 }
    print(greet(alice))
}
```

### Enums

```ash
enum Direction {
    North,
    South,
    East,
    West,
}

fn main() {
    dir := Direction.North
    print(dir)
}
```

---

## Arrays

Ash has two array types that serve different purposes.

### Dynamic array

Backed by a heap-allocated `AshVec`. Supports `push`, `pop`, `len`, indexed access, and for-each iteration. This is the default when you write an array literal with `[]`.

```ash
a := [10, 20, 30, 40, 50]

print(len(a))         // 5
push(a, 60)           // append
last := pop(a)        // remove and return last element
print(a[0])           // indexed read
a[0] = 99             // indexed write

for n in a {
    print(n)
}
```

You can also start with an empty vec and fill it:

```ash
v := vec_new()
push(v, 1)
push(v, 2)
push(v, 3)
print(len(v))
print(vec_contains(v, 2))   // 1 (true)
```

### Fixed array

Stack-allocated C array with zero overhead. No `push`/`pop`/`len`. Use the `![]` syntax.

```ash
b := ![1, 2, 3, 4, 5]

print(b[0])     // indexed read
b[2] = 77       // indexed write

for i in 0..5 {
    print(b[i])
}
```

Use a fixed array when the size is known at compile time and you don't need dynamic resizing.

---

## Standard Library

### print (always available, no import)

Accepts any number of arguments of any type, prints them space-separated with a newline.

```ash
print("Hello, World!")
print("Sum:", 3 + 4)
print(42)
print(true)
```

### io

```ash
import io

name    := io.input("Enter your name: ")
io.write_file("out.txt", "Hello, " + name)
content := io.read_file("out.txt")
print(content)
```

### string

```ash
import string

s := "Hello, Ash!"

print(str_upper(s))              // "HELLO, ASH!"
print(str_lower(s))              // "hello, ash!"
print(str_len(s))                // 11
print(str_slice(s, 0, 5))        // "Hello"
print(str_contains(s, "Ash"))    // 1 (true)
print(str_concat("foo", "bar"))  // "foobar"
print(str(42))                   // "42"
n := parse_int("123")            // 123
f := parse_float("3.14")         // 3.14
```

### math

```ash
import math

print(sqrt(16.0))       // 4.0
print(pow(2.0, 10.0))   // 1024.0
print(abs(-42))         // 42
print(min(3, 7))        // 3
print(max(3, 7))        // 7
print(clamp(15, 0, 10)) // 10
print(floor(3.7))       // 3.0
print(ceil(3.2))        // 4.0
print(round(3.5))       // 4.0
print(sin(0.0))         // 0.0
// Also: cos, tan, log, log2
```

### os

```ash
import os

print(argc())              // number of command-line arguments
home := getenv("HOME")     // read an environment variable
```

---

## Types

| Ash      | C             | Notes                          |
|----------|---------------|--------------------------------|
| `int`    | `int64_t`     | 64-bit signed integer          |
| `float`  | `double`      | 64-bit IEEE 754                |
| `bool`   | `int`         | `true` = 1, `false` = 0       |
| `string` | `const char*` | UTF-8, null-terminated         |
| `vec`    | `AshVec*`     | heap-allocated resizable array |
| fixed    | `T[N]`        | stack-allocated fixed array    |

---

## Project structure

```
ash/
  compiler/src/
    main.zig         entry point — sets up allocator, dispatches to cli
    cli.zig          ash run / build / init / version; zig cc invocation
    lexer.zig        tokenizer
    parser.zig       recursive-descent parser → AST
    ast.zig          AST node types, type system (AshType, TypeKind)
    semantic.zig     type checker and name resolver
    codegen_c.zig    C code generator
    errors.zig       error types and fatal error helpers
    utils.zig        file I/O, path helpers, exe-relative runtime discovery
  runtime/
    ash_runtime.c    C implementation of print, vec, string, math, io, os
    ash_runtime.h    public API header
  examples/
    hello.ash
    fib.ash
    fizzbuzz.ash
    ...
  build.zig          Zig build script
  install.sh         Linux/macOS installer
  install.bat        Windows installer
```

---

## Examples

| File                  | What it shows                                           |
|-----------------------|---------------------------------------------------------|
| `hello.ash`           | Hello World, variable inference, for-range loop         |
| `fib.ash`             | Recursive functions, for-range, import                  |
| `fizzbuzz.ash`        | while loop, if/else if/else, modulo                     |
| `calculator.ash`      | Multiple functions, arithmetic, running sum             |
| `features_demo.ash`   | Structs, enums, switch, fixed arrays, const, `+=`       |
| `functions_demo.ash`  | Multiple return values, forward declarations, recursion |
| `arrays_demo.ash`     | Dynamic vs fixed arrays, push/pop, indexing             |
| `strings_demo.ash`    | String module — upper/lower/slice/concat/parse          |
| `math_demo.ash`       | Math module — sqrt/pow/abs/min/max/clamp/trig           |
| `io_demo.ash`         | User input, file write, file read                       |
| `os_demo.ash`         | Argument count, environment variables                   |
| `vec_demo.ash`        | vec_new, push, len, for-each, vec_contains              |