fn main() {
    let mut a = [false; 26];
    let mut b = [false; 26];
    for n in [12, 5, 8, 21, 5, 17, 3, 12, 9] {
        a[n] = true;
    }
    for n in [8, 14, 21, 6, 14, 3, 25, 6] {
        b[n] = true;
    }
    let labels = ["union", "intersection", "difference", "symmetric difference"];
    for op in 0..4 {
        print!("{}:", labels[op]);
        for n in 0..26 {
            let keep = match op {
                0 => a[n] || b[n],
                1 => a[n] && b[n],
                2 => a[n] && !b[n],
                _ => a[n] != b[n],
            };
            if keep {
                print!(" {}", n);
            }
        }
        println!();
    }
}
