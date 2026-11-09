fn main() {
    let mut a = [27, 64, 13, 88, 41, 5, 72, 36];
    let mut total = 0;
    for p in 1..=7 {
        let mut swaps = 0;
        for j in 0..=7 - p {
            if a[j] > a[j + 1] {
                a.swap(j, j + 1);
                swaps += 1;
            }
        }
        total += swaps;
        print!("pass {}:", p);
        for n in a {
            print!(" {}", n);
        }
        println!();
        if swaps == 0 {
            break;
        }
    }
    println!("swaps: {}", total);
}
