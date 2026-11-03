for n in [0, 10, 255, 1000, 43981, 65535] {
    print("\(n): bin=\(String(n, radix: 2)) oct=\(String(n, radix: 8)) hex=\(String(n, radix: 16, uppercase: true))")
}
