fn search(n: usize, row: usize, positions: &mut [usize; 8],
          count: &mut usize, first: &mut [usize; 8]) {
    if row == n {
        if n == 8 && *count == 0 {
            *first = *positions;
        }
        *count += 1;
        return;
    }
    for col in 0..n {
        if (0..row).all(|r| positions[r] != col && positions[r].abs_diff(col) != row - r) {
            positions[row] = col;
            search(n, row + 1, positions, count, first);
        }
    }
}

fn main() {
    let mut first = [0; 8];
    for n in 4..=8 {
        let mut positions = [0; 8];
        let mut count = 0;
        search(n, 0, &mut positions, &mut count, &mut first);
        println!("N={}: {} solutions", n, count);
    }
    for r in 0..8 {
        for c in 0..8 {
            print!("{}", if first[r] == c { 'Q' } else { '.' });
        }
        println!();
    }
}
