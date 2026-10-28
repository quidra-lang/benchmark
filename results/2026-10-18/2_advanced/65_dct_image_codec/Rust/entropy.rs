#[derive(Clone)]
pub struct Table {
    pub counts: [usize; 16],
    pub symbols: Vec<u8>,
    pub codes: Vec<Option<(u32, usize)>>,
}

impl Table {
    pub fn new(counts: [usize; 16], symbols: Vec<u8>) -> Self {
        let mut code = 0;
        let mut index = 0;
        let mut codes = vec![None; 256];
        for (length, &count) in counts.iter().enumerate() {
            for _ in 0..count {
                codes[symbols[index] as usize] = Some((code, length+1));
                code += 1; index += 1;
            }
            code *= 2;
        }
        Self { counts, symbols, codes }
    }
}

pub fn category(value: i64) -> usize {
    let magnitude = value.unsigned_abs();
    if magnitude == 0 { 0 } else { 64-magnitude.leading_zeros() as usize }
}

pub fn extra(value: i64) -> (u32, usize) {
    let n = category(value);
    (if value >= 0 { value as u32 } else { (value+(1i64<<n)-1) as u32 }, n)
}

pub fn value(bits: u32, length: usize) -> i64 {
    if length == 0 { 0 }
    else if bits >= 1u32<<(length-1) { bits as i64 }
    else { bits as i64-(1i64<<length)+1 }
}

pub fn optimized(frequencies: &[usize; 256]) -> Table {
    let mut freq = frequencies.to_vec(); freq.push(1);
    let mut sizes = vec![0usize; 257];
    let mut others = vec![None; 257];
    loop {
        let first = (0..257).filter(|&v| freq[v] > 0).min_by_key(|&v| (freq[v], std::cmp::Reverse(v))).unwrap();
        let second = (0..257).filter(|&v| v != first && freq[v] > 0).min_by_key(|&v| (freq[v], std::cmp::Reverse(v)));
        let Some(second) = second else { break; };
        let combined = freq[first]+freq[second];
        freq[first] = combined; freq[second] = 0;
        let mut c1 = first;
        sizes[c1] += 1;
        while let Some(next) = others[c1] { c1 = next; sizes[c1] += 1; }
        others[c1] = Some(second);
        let mut c2 = second;
        sizes[c2] += 1;
        while let Some(next) = others[c2] { c2 = next; sizes[c2] += 1; }
    }
    let maximum = *sizes.iter().max().unwrap();
    let mut count = vec![0usize; maximum.max(16)+1];
    for &length in &sizes { if length > 0 { count[length] += 1; } }
    for length in (17..=maximum).rev() {
        while count[length] > 0 {
            let mut j = length-2;
            while count[j] == 0 { j -= 1; }
            count[length] -= 2; count[length-1] += 1; count[j+1] += 2; count[j] -= 1;
        }
    }
    let longest = (1..=16).rev().find(|&length| count[length] > 0).unwrap();
    count[longest] -= 1;
    let mut symbols: Vec<_> = (0..256).filter(|&v| sizes[v] > 0).collect();
    symbols.sort_by_key(|&v| (sizes[v], v));
    let mut counts = [0; 16]; counts.copy_from_slice(&count[1..=16]);
    Table::new(counts, symbols.iter().map(|&v| v as u8).collect())
}
