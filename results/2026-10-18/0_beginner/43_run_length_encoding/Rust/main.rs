fn main() {
    for s in ["AAABBBCCCD", "WWWWWWWWWWWWBWWWWWWWWWWWWBBB", "ALGORITHM", "MISSISSIPPI", "XXXXXXXXXXYYYYYYYYYYYYYYYYYYYYYZ"] {
        let bytes = s.as_bytes();
        let mut encoded = String::new();
        let mut i = 0;
        while i < bytes.len() {
            let mut j = i + 1;
            while j < bytes.len() && bytes[j] == bytes[i] {
                j += 1;
            }
            encoded.push_str(&format!("{}{}", j - i, bytes[i] as char));
            i = j;
        }
        let b = encoded.as_bytes();
        let mut decoded = String::new();
        i = 0;
        while i < b.len() {
            let mut count = 0;
            while b[i].is_ascii_digit() {
                count = count * 10 + usize::from(b[i] - b'0');
                i += 1;
            }
            let c = b[i] as char;
            i += 1;
            decoded.extend(std::iter::repeat(c).take(count));
        }
        println!("{} -> {} -> {}", s, encoded, decoded);
    }
}
