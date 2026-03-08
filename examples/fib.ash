import io

fn fib(n int) int {
    if n <= 1 {
        return n
    }
    return fib(n - 1) + fib(n - 2)
}

fn main() {
    print("Fibonacci sequence:")
    for i in 0..10 {
        result := fib(i)
        print(result)
    }
}
