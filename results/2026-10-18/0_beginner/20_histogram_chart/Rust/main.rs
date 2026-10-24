fn main() {
    let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    let counts = [7, 12, 4, 15, 9, 18, 11];
    for (day, count) in days.iter().zip(counts) {
        println!("{} | {} {}", day, "*".repeat(count), count);
    }
}
