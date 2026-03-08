import os

fn main() {
    print("arg count:", argc())

    // HOME works on Unix; on Windows it maps to USERPROFILE automatically
    home := getenv("HOME")
    print("HOME:", home)

    // These work on all platforms
    path := getenv("PATH")
    print("PATH set:", str_len(path) > 0)
}
