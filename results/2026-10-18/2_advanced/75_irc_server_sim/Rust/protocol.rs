pub fn fold(value: &str) -> String {
    value.bytes().map(|b| match b {
        b'A'..=b'Z' => (b+32) as char,b'[' => '{',b']' => '}',b'\\' => '|',b'^' => '~',_ => b as char
    }).collect()
}
pub fn digits(value: &str) -> bool {
    !value.is_empty() && value.bytes().all(|b| b.is_ascii_digit())
}
pub fn nickname(value: &str) -> bool {
    fn special(b: u8) -> bool {
        b"[]\\`_^{|}".contains(&b)
    }
    let bytes = value.as_bytes();
    !bytes.is_empty() && (bytes[0].is_ascii_alphabetic() || special(bytes[0])) && bytes[1..].iter().all(|&b| b.is_ascii_alphanumeric() || special(b) || b == b'-')
}
pub fn channel(value: &str, maximum: usize) -> bool {
    (2..=maximum).contains(&value.len()) && value.starts_with('#') && !value.contains(':')
}
pub fn parse(raw: &str) -> Option<(String,Vec<String>)> {
    let mut rest = raw;
    if rest.starts_with(':') {
        rest = rest.find(' ').map(|i| &rest[i..])?;
    }
    rest = rest.trim_start_matches(' ');
    if rest.is_empty() {
        return None;
    }
    let end = rest.find(' ').unwrap_or(rest.len());
    let command = rest[..end].to_ascii_uppercase();
    rest = &rest[end..];
    let mut parameters = Vec::new();
    loop {
        rest = rest.trim_start_matches(' ');
        if rest.is_empty() {
            break;
        }
        if rest.starts_with(':') {
            parameters.push(rest[1..].to_owned());
            break;
        }
        if parameters.len() == 14 {
            parameters.push(rest.to_owned());
            break;
        }
        let end = rest.find(' ').unwrap_or(rest.len());
        parameters.push(rest[..end].to_owned());
        rest = &rest[end..];
    }
    Some((command,parameters))
}
