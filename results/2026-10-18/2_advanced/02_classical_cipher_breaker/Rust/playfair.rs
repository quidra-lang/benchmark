pub fn build_square(key: &str) -> String {
    let mut seen = [false; 26];
    key.bytes()
        .chain(b"ABCDEFGHIKLMNOPQRSTUVWXYZ".iter().copied())
        .map(|byte| if byte == b'J' { b'I' } else { byte })
        .filter(|&byte| {
            let index = (byte - b'A') as usize;
            let fresh = !seen[index];
            seen[index] = true;
            fresh
        })
        .map(char::from)
        .collect()
}

pub fn preprocess(text: &str) -> String {
    let input = text.replace('J', "I").into_bytes();
    let mut output = String::new();
    let mut index = 0;
    while index < input.len() {
        let first = input[index];
        output.push(first as char);
        if index + 1 < input.len() && input[index + 1] != first {
            output.push(input[index + 1] as char);
            index += 2;
        } else {
            output.push(if first == b'X' { 'Q' } else { 'X' });
            index += 1;
        }
    }
    output
}

pub fn valid_ciphertext(text: &str) -> bool {
    let input = text.replace('J', "I");
    input.len() % 2 == 0 && input.as_bytes().chunks_exact(2).all(|pair| pair[0] != pair[1])
}

pub fn apply(text: &str, key: &str, decrypt: bool) -> String {
    let square = build_square(key);
    let grid = square.as_bytes();
    let mut positions = [0; 26];
    for (index, &byte) in grid.iter().enumerate() {
        positions[(byte - b'A') as usize] = index;
    }
    let input = if decrypt { text.replace('J', "I") } else { preprocess(text) };
    let shift = if decrypt { 4 } else { 1 };
    let mut output = String::with_capacity(input.len());
    for pair in input.as_bytes().chunks_exact(2) {
        let a = positions[(pair[0] - b'A') as usize];
        let b = positions[(pair[1] - b'A') as usize];
        let (ra, ca) = (a / 5, a % 5);
        let (rb, cb) = (b / 5, b % 5);
        let (a, b) = if ra == rb {
            (ra * 5 + (ca + shift) % 5, rb * 5 + (cb + shift) % 5)
        } else if ca == cb {
            ((ra + shift) % 5 * 5 + ca, (rb + shift) % 5 * 5 + cb)
        } else {
            (ra * 5 + cb, rb * 5 + ca)
        };
        output.push(grid[a] as char);
        output.push(grid[b] as char);
    }
    output
}
