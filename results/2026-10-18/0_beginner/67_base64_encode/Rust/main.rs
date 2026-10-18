fn main() {
    let alphabet = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    for s in ["Man", "Hello, World!", "", "<b>bold</b>", "a+b=c?"] {
        let bytes = s.as_bytes();
        let mut encoded = String::new();
        for chunk in bytes.chunks(3) {
            let bits = (u32::from(chunk[0]) << 16)|(u32::from(*chunk.get(1).unwrap_or(&0)) << 8)| u32::from(*chunk.get(2).unwrap_or(&0));
            encoded.push(alphabet[((bits >> 18) &63) as usize] as char);
            encoded.push(alphabet[((bits >> 12) &63) as usize] as char);
            encoded.push(if chunk.len() > 1 {
                alphabet[((bits >> 6) &63) as usize] as char
            } else {
                '='
            });
            encoded.push(if chunk.len() > 2 {
                alphabet[(bits &63) as usize] as char
            } else {
                '='
            });
        }
        println!("\"{}\" -> \"{}\"", s, encoded);
    }
}
