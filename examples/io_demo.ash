import io

fn main() {
    name := io.input("Enter your name: ")
    print("Hello,", name)
    io.write_file("greeting.txt", str_concat("Hello, ", name))
    content := io.read_file("greeting.txt")
    print("Saved:", content)
}
