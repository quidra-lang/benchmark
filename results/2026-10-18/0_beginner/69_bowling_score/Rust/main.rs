fn main() {
    let games: [&[i32]; 5] = [&[8, 1, 10, 7, 3, 9, 0, 10, 10, 2, 6, 6, 4, 0, 9, 10, 7, 2], &[3, 4, 5, 2,
        7, 1, 0, 6, 8, 1, 4, 4, 2, 3, 6, 2, 9, 0, 1, 5], &[5, 5, 0, 10, 7, 3, 9, 1, 6, 4, 8, 2, 3, 7,
        4, 6, 1, 9, 7, 3, 5], &[10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10], &[10, 9, 1, 10, 10,
        7, 2, 0, 0, 10, 8, 1, 10, 6, 4, 10]];
    for (g, a) in games.iter().enumerate() {
        let (mut index, mut total) = (0, 0);
        print!("game {}:", g + 1);
        for frame in 0..10 {
            let score;
            if frame == 9 {
                let base = a[index] + a[index + 1];
                score = base + if a[index] == 10 || base == 10 { a[index + 2] } else { 0 };
            } else if a[index] == 10 {
                score = 10 + a[index + 1] + a[index + 2];
                index += 1;
            } else {
                let base = a[index] + a[index + 1];
                score = base + if base == 10 { a[index + 2] } else { 0 };
                index += 2;
            }
            total += score;
            print!(" {}", total);
        }
        println!();
    }
}
