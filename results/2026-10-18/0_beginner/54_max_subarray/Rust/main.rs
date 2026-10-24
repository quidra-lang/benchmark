fn main() {
    let arrays: [&[i32]; 3] = [
        &[3, -5, 8, -2, 6, -9, 4, 1, -7, 5, -3, 2],
        &[-4, 7, -1, 3, -8, 10, -2, 5, -6, -2, 9, -12, 4, -1],
        &[-6, -3, 5, -1, -4, 3, -9, 2, 3, -1, 4, -5, 1, 6, -2],
    ];
    for a in arrays {
        let (mut current, mut best, mut start, mut left, mut right) = (a[0], a[0], 0, 0, 0);
        for i in 1..a.len() {
            if current < 0 {
                current = a[i];
                start = i;
            } else {
                current += a[i];
            }
            if current > best {
                best = current;
                left = start;
                right = i;
            }
        }
        println!("max sum {} at [{}, {}]", best, left, right);
    }
}
