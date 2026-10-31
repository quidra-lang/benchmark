pub const LITERAL_DOLLAR: u8 = 1;

pub struct LogicalLine {
    pub number: usize,
    pub segments: Vec<String>,
    pub error: Option<(&'static str, String)>,
}

pub fn logical_lines(source: &str) -> Vec<LogicalLine> {
    let physical: Vec<&[u8]> = source.lines().map(str::as_bytes).collect();
    let mut lines = Vec::new();
    let mut index = 0;
    while index < physical.len() {
        let mut line = LogicalLine { number: index + 1, segments: Vec::new(), error: None };
        let mut source = physical[index];
        index += 1;
        let mut position = 0;
        let mut quoted = false;
        let mut current = String::new();
        while position < source.len() {
            let byte = source[position];
            if byte == b'\\' && position + 1 == source.len() {
                source = physical[index];
                index += 1;
                position = source.iter().position(|&c| c != b' ').unwrap_or(source.len());
            } else if quoted && byte == b'\\' {
                let follower = source[position + 1];
                let decoded = match follower {
                    b'\\' | b'"' => Some(follower),
                    b'n' => Some(b'\n'), b't' => Some(b'\t'), b'$' => Some(LITERAL_DOLLAR),
                    _ => None,
                };
                if let Some(c) = decoded {
                    current.push(c as char);
                } else if line.error.is_none() {
                    line.error = Some(("E_ESCAPE", format!("invalid escape sequence \\{}", follower as char)));
                }
                position += 2;
            } else if byte == b'"' {
                line.segments.push(std::mem::take(&mut current));
                quoted = !quoted;
                position += 1;
            } else if !quoted && (byte == b';' || byte == b'#') {
                break;
            } else {
                current.push(byte as char);
                position += 1;
            }
        }
        if quoted && line.error.is_none() {
            line.error = Some(("E_UNTERMINATED", "unterminated string".into()));
        }
        line.segments.push(current);
        lines.push(line);
    }
    lines
}
