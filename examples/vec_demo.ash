fn main() {
    // Vec — dynamic, starts empty
    v := vec_new()
    push(v, 1)
    push(v, 2)
    push(v, 3)
    print("vec length:", len(v))
    for n in v {
        print(n)
    }

    // Array literal — same runtime as vec, starts with values
    a := [10, 20, 30]
    print("array length:", len(a))
    for n in a {
        print(n)
    }

    // Both support the same operations
    push(a, 40)
    print("after push:", len(a))
    print("contains 20:", vec_contains(a, 20))
    print("index 1:", a[1])
    a[1] = 99
    print("after a[1]=99:", a[1])
}
