fn main() {
    for s in [
        "AAABBBCCCD",
        "WWWWWWWWWWWWBWWWWWWWWWWWWBBB",
        "ALGORITHM",
        "MISSISSIPPI",
        "XXXXXXXXXXYYYYYYYYYYYYYYYYYYYYYZ",
    ] {
        let mut encoded = String::new();
        for run in s.as_bytes().chunk_by(|a, b| a == b) {
            encoded.push_str(&format!("{}{}", run.len(), run[0] as char));
        }
        let mut decoded = String::new();
        for run in encoded.split_inclusive(|c: char| c.is_ascii_uppercase()) {
            let (count, letter) = run.split_at(run.len() - 1);
            decoded.push_str(&letter.repeat(count.parse::<usize>().unwrap()));
        }
        println!("{} -> {} -> {}", s, encoded, decoded);
    }
}
