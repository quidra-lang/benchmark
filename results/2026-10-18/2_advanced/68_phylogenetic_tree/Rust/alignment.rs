use std::collections::BTreeMap;
use std::fs;

pub struct Record { pub name: String, pub line: usize, pub sequence: Vec<u8> }
pub fn read() -> Vec<Record> {
    let mut records = Vec::<Record>::new();
    for (line, text) in fs::read_to_string("input/alignment.fasta").unwrap().lines().enumerate() {
        if let Some(header) = text.strip_prefix('>') {
            records.push(Record { name: header.split(' ').next().unwrap().to_owned(), line: line+1, sequence: Vec::new() });
        } else { records.last_mut().unwrap().sequence.extend(text.bytes().map(|b| b.to_ascii_uppercase())); }
    }
    records
}
pub fn base_set(c: u8) -> Option<u8> {
    Some(match c { b'A' => 1, b'C' => 2, b'G' => 4, b'T' => 8, b'R' => 5, b'Y' => 10,
        b'S' => 6, b'W' => 9, b'K' => 12, b'M' => 3, b'B' => 14, b'D' => 13,
        b'H' => 11, b'V' => 7, b'N' | b'-' => 15, _ => return None })
}
pub fn base(c: u8) -> bool { matches!(c, b'A' | b'C' | b'G' | b'T') }
pub fn patterns(records: &[Record]) -> (Vec<String>, BTreeMap<String, usize>) {
    let mut counts = BTreeMap::new();
    let columns: Vec<_> = (0..records[0].sequence.len()).map(|c| {
        let pattern: String = records.iter().map(|r| r.sequence[c] as char).collect();
        *counts.entry(pattern.clone()).or_default() += 1; pattern
    }).collect();
    (columns, counts)
}
pub fn classify(records: &[Record]) -> [usize; 5] {
    let mut result = [0; 5];
    for c in 0..records[0].sequence.len() {
        let mut counts = [0; 4];
        let mut gapped = false;
        for record in records {
            let value = record.sequence[c]; gapped |= value == b'-';
            if base(value) { counts[base_set(value).unwrap().trailing_zeros() as usize] += 1; }
        }
        let kinds = counts.iter().filter(|&&n| n > 0).count();
        if kinds == 0 { result[4] += 1; } else if kinds == 1 { result[0] += 1; } else { result[1] += 1; }
        result[2] += usize::from(counts.iter().filter(|&&n| n >= 2).count() >= 2); result[3] += usize::from(gapped);
    }
    result
}
