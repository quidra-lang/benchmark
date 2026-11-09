fn main() {
    let sentence = "Peter Piper picked a peck of pickled peppers!";
    let mut counts = [0; 26];
    for c in sentence.bytes() {
        let c = c.to_ascii_lowercase();
        if c.is_ascii_lowercase() {
            counts[(c - b'a') as usize] += 1;
        }
    }
    for (i, n) in counts.iter().enumerate() {
        if *n > 0 {
            println!("{}: {}", (b'a' + i as u8) as char, n);
        }
    }
}
