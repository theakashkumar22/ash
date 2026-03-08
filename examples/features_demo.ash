struct Point {
    x: int
    y: int
}

struct Person {
    name: string
    age: int
}

enum Direction {
    North,
    South,
    East,
    West,
}

fn add(a: int, b: int): int {
    return a + b
}

fn greet(p: Person): string {
    return "Hello, " + p.name
}

fn main() {
    // ── explicit type annotation ──────────────────────
    x: int = 42
    name: string = "ash"
    flag: bool = true
    print("x:", x, "name:", name, "flag:", flag)

    // ── const ─────────────────────────────────────────
    const PI = 3
    const MAX: int = 100
    print("PI:", PI, "MAX:", MAX)

    // ── += and -= ─────────────────────────────────────
    count := 0
    count += 5
    count += 3
    count -= 2
    print("count:", count)

    // ── struct ────────────────────────────────────────
    p := Point{ x: 10, y: 20 }
    print("point x:", p.x, "y:", p.y)
    p.x = 99
    print("after p.x=99:", p.x)

    alice := Person{ name: "Alice", age: 30 }
    print(greet(alice))
    print("age:", alice.age)

    // ── enum ──────────────────────────────────────────
    dir := Direction.North
    print("direction:", dir)

    // ── switch (int) ──────────────────────────────────
    val := 2
    switch val {
        case 1 => print("one")
        case 2 => print("two")
        case 3 => print("three")
        default => print("other")
    }

    // ── switch (string) ───────────────────────────────
    lang := "ash"
    switch lang {
        case "ash"  => print("Ash language!")
        case "zig"  => print("Zig language!")
        default     => print("unknown language")
    }

    // ── break and continue ────────────────────────────
    i := 0
    while i < 10 {
        i += 1
        if i == 3 { continue }
        if i == 6 { break }
        print("i:", i)
    }

    // ── fixed array len() ─────────────────────────────
    arr := ![10, 20, 30, 40, 50]
    print("fixed array len:", len(arr))
    for j in 0..5 {
        print(arr[j])
    }

    // ── user function ─────────────────────────────────
    print("add(3,4):", add(3, 4))
}
