use std::convert::TryInto;
use std::io;

pub fn is_letter(byte: u8) -> bool {
    byte.is_ascii_alphabetic()
}

pub fn letter_value(byte: u8) -> usize {
    (byte.to_ascii_uppercase() - b'A') as usize
}

pub fn letter_string(text: &str) -> String {
    text.bytes()
        .filter(|byte| is_letter(*byte))
        .map(|byte| byte.to_ascii_uppercase() as char)
        .collect()
}

pub struct Weights {
    pub monograms: [i64; 26],
    pub bigrams: [[i64; 26]; 26],
}

impl Weights {
    pub fn parse(text: &str) -> io::Result<Self> {
        let mut lines = text.lines();
        let invalid = || io::Error::new(io::ErrorKind::InvalidData, "invalid weights file");
        if lines.next() != Some("MONOGRAMS") {
            return Err(invalid());
        }
        let parse_row = |line: Option<&str>| -> io::Result<[i64; 26]> {
            let values: Vec<i64> = line
                .ok_or_else(invalid)?
                .split(' ')
                .map(|value| value.parse().map_err(|_| invalid()))
                .collect::<io::Result<_>>()?;
            values.try_into().map_err(|_| invalid())
        };
        let monograms = parse_row(lines.next())?;
        if lines.next() != Some("BIGRAMS") {
            return Err(invalid());
        }
        let mut bigrams = [[0; 26]; 26];
        for row in &mut bigrams {
            *row = parse_row(lines.next())?;
        }
        Ok(Self { monograms, bigrams })
    }

    pub fn monogram(&self, text: &str) -> i64 {
        text.bytes().map(|byte| self.monograms[letter_value(byte)]).sum()
    }

    pub fn bigram(&self, text: &str) -> i64 {
        text.as_bytes()
            .windows(2)
            .map(|pair| self.bigrams[letter_value(pair[0])][letter_value(pair[1])])
            .sum()
    }
}
