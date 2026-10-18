fn main() {
    let input = [("Tanaka", [78, 85, 94]), ("Suzuki", [88, 74, 82]), ("Yamada", [65, 90, 71]), ("Ito",
        [80, 79, 85]), ("Kato", [92, 88, 95]), ("Mori", [70, 62, 78])];
    let mut students: Vec<(&str, i32)> = input.iter().map(|(name, scores)| (*name, scores.iter().sum())).collect();
    students.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(b.0)));
    let mut rank = 0;
    for (i, (name, total)) in students.iter().enumerate() {
        if i == 0 || *total != students[i - 1].1 {
            rank = i + 1;
        }
        println!("{}. {} total={} average={:.2}", rank, name, total, f64::from(*total) / 3.0);
    }
}
