import io

fn add(a int, b int) int {
    return a + b
}

fn sub(a int, b int) int {
    return a - b
}

fn mul(a int, b int) int {
    return a * b
}

fn div(a int, b int) int {
    return a / b
}

fn main() {
    x := 20
    y := 4

    print("Addition:")
    print(add(x, y))

    print("Subtraction:")
    print(sub(x, y))

    print("Multiplication:")
    print(mul(x, y))

    print("Division:")
    print(div(x, y))

    sum := 0
    for i in 1..11 {
        sum = sum + i
    }
    print("Sum 1..10:")
    print(sum)
}
