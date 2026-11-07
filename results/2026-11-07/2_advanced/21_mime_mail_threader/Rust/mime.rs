pub fn strict_base64(text: &str) -> Option<Vec<u8>> {
    if text.len() % 4 != 0 { return None; }
    let data = text.trim_end_matches('=');
    if text.len() - data.len() >= 3 { return None; }
    let (mut buffer, mut bits) = (0u32, 0);
    let mut result = Vec::new();
    for byte in data.bytes() {
        let value = match byte { b'A'..=b'Z' => byte - b'A', b'a'..=b'z' => byte - b'a' + 26, b'0'..=b'9' => byte - b'0' + 52,
            b'+' => 62, b'/' => 63, _ => return None };
        buffer = buffer << 6 | value as u32;
        bits += 6;
        if bits >= 8 { bits -= 8; result.push((buffer >> bits) as u8); buffer &= (1 << bits) - 1; }
    }
    Some(result)
}
pub fn hex(byte: u8) -> Option<u8> {
    match byte { b'0'..=b'9' => Some(byte - b'0'), b'A'..=b'F' => Some(byte - b'A' + 10), b'a'..=b'f' => Some(byte - b'a' + 10), _ => None }
}
pub fn hex_byte(data: &[u8], position: usize) -> Option<u8> { Some(16 * hex(*data.get(position)?)? + hex(*data.get(position + 1)?)?) }
pub fn decode_base64_body(text: &str) -> Option<String> {
    let compact: String = text.chars().filter(|&value| value != ' ' && value != '\t' && value != '\n').collect();
    let data = strict_base64(&compact)?;
    let mut result = Vec::new();
    let mut position = 0;
    while position < data.len() {
        if data[position] == 13 && data.get(position + 1) == Some(&10) { result.push(10); position += 2; }
        else { result.push(data[position]); position += 1; }
    }
    if result.iter().any(|&byte| byte != 9 && byte != 10 && !(32..=126).contains(&byte)) { return None; }
    Some(String::from_utf8(result).unwrap())
}
pub fn decode_quoted_printable(text: &str) -> (String, bool) {
    let lines: Vec<_> = text.split('\n').collect();
    let mut result = Vec::new();
    let mut error = false;
    for (index, line) in lines.iter().enumerate() {
        let line = line.trim_end_matches([' ', '\t']);
        let soft = line.ends_with('=');
        let data = if soft { &line.as_bytes()[..line.len() - 1] } else { line.as_bytes() };
        let mut position = 0;
        while position < data.len() {
            if data[position] == b'=' {
                if let Some(value) = hex_byte(data, position + 1).filter(|&value| value == 9 || (32..=126).contains(&value)) {
                    result.push(value); position += 3; continue;
                }
                error = true;
            }
            result.push(data[position]); position += 1;
        }
        if !soft && index + 1 < lines.len() { result.push(b'\n'); }
    }
    (String::from_utf8(result).unwrap(), error)
}
