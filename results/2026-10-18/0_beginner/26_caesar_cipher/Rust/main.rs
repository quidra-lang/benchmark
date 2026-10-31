fn cipher(s: &str, shift: u8) -> String {
    s.bytes()
        .map(|c| {
            let base = if c.is_ascii_lowercase() {
                b'a'
            } else if c.is_ascii_uppercase() {
                b'A'
            } else {
                return c as char;
            };
            (base + (c - base + shift) % 26) as char
        })
        .collect()
}

fn main() {
    let message = "Zoe, meet Max by the Old Bridge at six!";
    let encrypted = cipher(message, 3);
    println!("{}", encrypted);
    println!("{}", cipher(&encrypted, 23));
}
