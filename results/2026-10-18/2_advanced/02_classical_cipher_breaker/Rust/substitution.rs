use crate::scoring::{is_letter, letter_value};

pub const AFFINE_MULTIPLIERS: [usize; 12] = [1, 3, 5, 7, 9, 11, 15, 17, 19, 21, 23, 25];

fn transform(text: &str, mut replacement: impl FnMut(i32, usize) -> i32) -> String {
    let mut index = 0;
    text.bytes()
        .map(|byte| {
            if !is_letter(byte) {
                return byte as char;
            }
            let value = replacement(letter_value(byte) as i32, index).rem_euclid(26);
            index += 1;
            let base = if byte.is_ascii_uppercase() { b'A' } else { b'a' };
            (base + value as u8) as char
        })
        .collect()
}

pub fn caesar(text: &str, key: usize, decrypt: bool) -> String {
    let shift = if decrypt { -(key as i32) } else { key as i32 };
    transform(text, |value, _| value + shift)
}

pub fn affine(text: &str, a: usize, b: usize, decrypt: bool) -> String {
    let a = a as i32;
    let b = b as i32;
    let inverse = (1..26).find(|&value| a * value % 26 == 1).unwrap();
    transform(text, |value, _| {
        if decrypt { inverse * (value - b) } else { a * value + b }
    })
}

pub fn vigenere(text: &str, key: &str, decrypt: bool) -> String {
    let values: Vec<i32> = key.bytes().map(|byte| letter_value(byte) as i32).collect();
    transform(text, |value, index| {
        let shift = values[index % values.len()];
        if decrypt { value - shift } else { value + shift }
    })
}

pub fn autokey(text: &str, key: &str, decrypt: bool) -> String {
    let values: Vec<i32> = key.bytes().map(|byte| letter_value(byte) as i32).collect();
    let mut plaintext = Vec::new();
    transform(text, |value, index| {
        let shift = if index < values.len() { values[index] } else { plaintext[index - values.len()] };
        let result = (if decrypt { value - shift } else { value + shift }).rem_euclid(26);
        plaintext.push(if decrypt { result } else { value });
        result
    })
}
