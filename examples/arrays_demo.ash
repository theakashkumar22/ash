fn main() {
    // Dynamic array — backed by AshVec, supports push/pop/len/for-each
    a := [10, 20, 30, 40, 50]
    print("dynamic length:", len(a))
    for n in a {
        print(n)
    }
    push(a, 60)
    print("after push:", len(a))
    last := pop(a)
    print("popped:", last)
    print("index 0:", a[0])
    a[0] = 99
    print("after a[0]=99:", a[0])

    // Fixed array — stack allocated C array, zero overhead
    // Supports indexing and for-range by index. No push/pop/len.
    b := ![1, 2, 3, 4, 5]
    print("fixed b[0]:", b[0])
    print("fixed b[4]:", b[4])
    b[2] = 77
    print("after b[2]=77:", b[2])
    for i in 0..5 {
        print(b[i])
    }
}
