fn main() {
    let mut counts = [0; 5];
    let grades = ['A', 'B', 'C', 'D', 'F'];
    for s in [78, 90, 100, 59, 80, 85, 89, 70, 45, 93] {
        let g = if s >= 90 {
            0
        } else if s >= 80 {
            1
        } else if s >= 70 {
            2
        } else if s >= 60 {
            3
        } else {
            4
        };
        counts[g] += 1;
        println!("{}: {}", s, grades[g]);
    }
    for i in 0..5 {
        println!("{}: {}", grades[i], counts[i]);
    }
}
