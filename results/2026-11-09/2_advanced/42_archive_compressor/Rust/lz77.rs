use crate::bitio::DecodeError;

pub enum Token {
    Literal(u8),
    Match(usize, usize),
}

pub fn tokenize(data: &[u8], offset_bits: usize, length_bits: usize) -> Vec<Token> {
    let window = 1_usize << offset_bits;
    let lookahead = (1_usize << length_bits) + 2;
    let mut tokens = Vec::new();
    let mut i = 0;
    while i < data.len() {
        let mut best = (0, 0);
        for distance in 1..=window.min(i) {
            let mut length = 0;
            while length < lookahead.min(data.len() - i) && data[i + length] == data[i + length - distance] { length += 1; }
            if length > best.1 { best = (distance, length); }
        }
        if best.1 >= 3 { tokens.push(Token::Match(best.0, best.1)); i += best.1; }
        else { tokens.push(Token::Literal(data[i])); i += 1; }
    }
    tokens
}

pub fn copy(output: &mut Vec<u8>, distance: usize, length: usize, original: usize) -> Result<(), DecodeError> {
    if distance > output.len() { return Err(DecodeError::new("bad_offset", output.len())); }
    if output.len() + length > original { return Err(DecodeError::new("overrun", output.len())); }
    for _ in 0..length { output.push(output[output.len() - distance]); }
    Ok(())
}
