fn main() {
    let mut counts = [0; 5];
    let grades = ['A', 'B', 'C', 'D', 'F'];
    for s in [78, 90, 100, 59, 80, 85, 89, 70, 45, 93] {
        let g = match s {
            90..=100 => 0,
            80..=89 => 1,
            70..=79 => 2,
            60..=69 => 3,
            _ => 4,
        };
        counts[g] += 1;
        println!("{}: {}", s, grades[g]);
    }
    for i in 0..5 {
        println!("{}: {}", grades[i], counts[i]);
    }
}
