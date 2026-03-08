// ── helper functions defined BEFORE main ──────────────────────────────────

fn add(a: int, b: int): int {
    return a + b
}

fn multiply(a: int, b: int): int {
    return a * b
}

fn greet(name: string): string {
    return "Hello, " + name + "!"
}

fn max_of_three(a: int, b: int, c: int): int {
    if a >= b && a >= c { return a }
    if b >= c           { return b }
    return c
}

// Multi-return: swap two integers
fn swap(a: int, b: int): (int, int) {
    return b, a
}

// Multi-return: min and max together
fn minmax(a: int, b: int): (int, int) {
    if a < b { return a, b }
    return b, a
}

// Multi-return: divide with remainder
fn divmod(a: int, b: int): (int, int) {
    return a / b, a % b
}

// Multi-return: three values
fn rgb_to_parts(hex: int): (int, int, int) {
    const r = (hex / 65536) % 256
    const g = (hex / 256) % 256
    const b = hex % 256
    return r, g, b
}

// Recursive function
fn fib(n: int): int {
    if n <= 1 { return n }
    return fib(n - 1) + fib(n - 2)
}

// ── main ───────────────────────────────────────────────────────────────────

fn main() {
    // Basic function calls
    print(add(10, 20))
    print(multiply(6, 7))
    print(greet("World"))
    print(max_of_three(3, 9, 5))

    // Multi-return: swap
    x, y := swap(100, 200)
    print("swapped:", x, y)

    // Multi-return: minmax
    lo, hi := minmax(42, 17)
    print("min:", lo, "max:", hi)

    // Multi-return: divmod
    q, r := divmod(17, 5)
    print("17/5 =", q, "rem", r)

    // Multi-return: three values
    red, green, blue := rgb_to_parts(16744448)
    print("r:", red, "g:", green, "b:", blue)

    // Recursive
    print("fib(10) =", fib(10))

    // Result of call used in expression
    print("add(3,4) + 1 =", add(3, 4) + 1)
}

// ── helper functions defined AFTER main ───────────────────────────────────
// These work because the compiler does a forward-declaration pass first.

fn square(n: int): int {
    return n * n
}

fn is_even(n: int): bool {
    return n % 2 == 0
}
