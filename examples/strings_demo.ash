import string

fn main() {
    s := "Hello, Ash!"
    print("upper:", str_upper(s))
    print("lower:", str_lower(s))
    print("length:", str_len(s))
    print("slice 0..5:", str_slice(s, 0, 5))
    print("contains 'Ash':", str_contains(s, "Ash"))
    greeting := str_concat("Hello, ", "World!")
    print("concat:", greeting)
    n := 42
    print("str(42):", str(n))
    parsed := parse_int("123")
    print("parse_int:", parsed)
}
