fn main() {
    let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    let counts = [7, 12, 4, 15, 9, 18, 11];
    for i in 0..7 {
        println!("{} | {} {}", days[i], "*".repeat(counts[i]), counts[i]);
    }
}
