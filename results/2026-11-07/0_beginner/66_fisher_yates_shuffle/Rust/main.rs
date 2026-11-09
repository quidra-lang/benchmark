fn main() {
    let mut deck: Vec<usize> = (0..52).collect();
    let mut x = 2026_i64;
    for i in (1..52).rev() {
        x = x * 48271 % 2147483647;
        let j = (x % (i as i64 + 1)) as usize;
        deck.swap(i, j);
    }
    let ranks = b"A23456789TJQK";
    let suits = b"SHDC";
    for (i, card) in deck.iter().enumerate() {
        if i % 13 > 0 {
            print!(" ");
        }
        print!("{}{}", ranks[card % 13] as char, suits[card / 13] as char);
        if i % 13 == 12 {
            println!();
        }
    }
}
