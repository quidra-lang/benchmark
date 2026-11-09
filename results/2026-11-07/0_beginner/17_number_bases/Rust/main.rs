fn main() {
    for n in [0, 10, 255, 1000, 43981, 65535] {
        println!("{}: bin={:b} oct={:o} hex={:X}", n, n, n, n);
    }
}
