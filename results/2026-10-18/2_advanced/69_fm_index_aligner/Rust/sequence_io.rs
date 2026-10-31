use std::fs;

pub struct Reference { pub name: String, pub sequence: Vec<u8>, pub masked: usize }
pub struct Read { pub name: String, pub sequence: Vec<u8>, pub quality: Vec<u8> }
pub struct Params {
    pub mismatches: usize, pub minimum: usize, pub trim: u8, pub seed: usize, pub step: usize, pub seed_hits: usize,
    pub band: i64, pub scores: [i64; 4], pub percent: i64, pub alternatives: usize, pub occ: usize, pub sample: usize,
    pub direct: usize, pub coverage: usize, pub mapq: usize, pub variants: [usize; 4],
}

pub fn read() -> (Vec<Reference>, Vec<Read>, Params) {
    let mut references = Vec::<Reference>::new();
    for line in fs::read_to_string("input/reference.fasta").unwrap().lines() {
        if let Some(header) = line.strip_prefix('>') { references.push(Reference { name: header.split(' ').next().unwrap().to_owned(), sequence: Vec::new(), masked: 0 }); }
        else {
            let reference = references.last_mut().unwrap(); reference.masked += line.bytes().filter(u8::is_ascii_lowercase).count();
            reference.sequence.extend(line.bytes().map(|b| b.to_ascii_uppercase()));
        }
    }
    let input = fs::read_to_string("input/reads.fastq").unwrap(); let lines: Vec<_> = input.lines().collect();
    let reads = lines.chunks(4).map(|w| Read { name: w[0][1..].to_owned(), sequence: w[1].as_bytes().to_vec(), quality: w[3].as_bytes().to_vec() }).collect();
    let input = fs::read_to_string("input/params.txt").unwrap(); let values: Vec<Vec<_>> = input.lines().map(|l| l.split_whitespace().skip(1).collect()).collect();
    let mut scores = [0; 4]; let mut variants = [0; 4];
    for i in 0..4 { scores[i] = values[7][i].parse().unwrap(); variants[i] = values[15][i].parse().unwrap(); }
    let p = Params { mismatches: values[0][0].parse().unwrap(), minimum: values[1][0].parse().unwrap(), trim: values[2][0].parse().unwrap(),
        seed: values[3][0].parse().unwrap(), step: values[4][0].parse().unwrap(), seed_hits: values[5][0].parse().unwrap(),
        band: values[6][0].parse().unwrap(), scores, percent: values[8][0].parse().unwrap(), alternatives: values[9][0].parse().unwrap(),
        occ: values[10][0].parse().unwrap(), sample: values[11][0].parse().unwrap(), direct: values[12][0].parse().unwrap(),
        coverage: values[13][0].parse().unwrap(), mapq: values[14][0].parse().unwrap(), variants };
    (references, reads, p)
}

pub fn reverse_complement(sequence: &[u8]) -> Vec<u8> {
    sequence.iter().rev().map(|&b| match b { b'A' => b'T', b'C' => b'G', b'G' => b'C', b'T' => b'A', _ => b'N' }).collect()
}
