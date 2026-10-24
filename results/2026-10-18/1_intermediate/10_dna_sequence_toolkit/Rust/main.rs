use std::collections::{BTreeMap, BTreeSet, HashSet};
use std::io::{self, Read};

const BASES: &[u8] = b"ACGT";

fn complement(base: u8) -> u8 {
    match base {
        b'A' => b'T',
        b'C' => b'G',
        b'G' => b'C',
        b'T' => b'A',
        b'R' => b'Y',
        b'Y' => b'R',
        b'W' => b'W',
        b'S' => b'S',
        b'K' => b'M',
        b'M' => b'K',
        b'B' => b'V',
        b'D' => b'H',
        b'H' => b'D',
        b'V' => b'B',
        b'N' => b'N',
        _ => unreachable!("validated DNA or IUPAC symbol"),
    }
}

fn iupac(symbol: u8) -> Option<&'static [u8]> {
    match symbol {
        b'A' => Some(b"A"),
        b'C' => Some(b"C"),
        b'G' => Some(b"G"),
        b'T' => Some(b"T"),
        b'R' => Some(b"AG"),
        b'Y' => Some(b"CT"),
        b'W' => Some(b"AT"),
        b'S' => Some(b"CG"),
        b'K' => Some(b"GT"),
        b'M' => Some(b"AC"),
        b'B' => Some(b"CGT"),
        b'D' => Some(b"AGT"),
        b'H' => Some(b"ACT"),
        b'V' => Some(b"ACG"),
        b'N' => Some(b"ACGT"),
        _ => None,
    }
}

fn symbol(bases: &str) -> char {
    match bases {
        "A" => 'A', "C" => 'C', "G" => 'G', "T" => 'T',
        "AG" => 'R', "CT" => 'Y', "AT" => 'W', "CG" => 'S',
        "GT" => 'K', "AC" => 'M', "CGT" => 'B', "AGT" => 'D',
        "ACT" => 'H', "ACG" => 'V', "ACGT" => 'N',
        _ => unreachable!("nonempty canonical base set"),
    }
}

fn amino(codon: &str) -> char {
    match codon {
        "GCT" | "GCC" | "GCA" | "GCG" => 'A',
        "TGT" | "TGC" => 'C',
        "GAT" | "GAC" => 'D',
        "GAA" | "GAG" => 'E',
        "TTT" | "TTC" => 'F',
        "GGT" | "GGC" | "GGA" | "GGG" => 'G',
        "CAT" | "CAC" => 'H',
        "ATT" | "ATC" | "ATA" => 'I',
        "AAA" | "AAG" => 'K',
        "TTA" | "TTG" | "CTT" | "CTC" | "CTA" | "CTG" => 'L',
        "ATG" => 'M',
        "AAT" | "AAC" => 'N',
        "CCT" | "CCC" | "CCA" | "CCG" => 'P',
        "CAA" | "CAG" => 'Q',
        "CGT" | "CGC" | "CGA" | "CGG" | "AGA" | "AGG" => 'R',
        "TCT" | "TCC" | "TCA" | "TCG" | "AGT" | "AGC" => 'S',
        "ACT" | "ACC" | "ACA" | "ACG" => 'T',
        "GTT" | "GTC" | "GTA" | "GTG" => 'V',
        "TGG" => 'W',
        "TAT" | "TAC" => 'Y',
        "TAA" | "TAG" | "TGA" => '*',
        _ => unreachable!("validated codon"),
    }
}

fn amino_mass(amino: u8) -> i32 {
    match amino {
        b'A' => 71079, b'C' => 103139, b'D' => 115089, b'E' => 129116,
        b'F' => 147177, b'G' => 57052, b'H' => 137141, b'I' => 113160,
        b'K' => 128174, b'L' => 113160, b'M' => 131193, b'N' => 114104,
        b'P' => 97117, b'Q' => 128131, b'R' => 156188, b'S' => 87078,
        b'T' => 101105, b'V' => 99133, b'W' => 186213, b'Y' => 163176,
        _ => unreachable!("translated amino acid"),
    }
}

fn base_mass(base: u8) -> i32 {
    match base {
        b'A' => 331222, b'C' => 307197, b'G' => 347221, b'T' => 322208,
        _ => unreachable!("validated base"),
    }
}

fn enzyme(name: &str) -> Option<(&'static str, i32)> {
    match name {
        "EcoRI" => Some(("GAATTC", 1)), "BamHI" => Some(("GGATCC", 1)),
        "HindIII" => Some(("AAGCTT", 1)), "PstI" => Some(("CTGCAG", 5)),
        "SmaI" => Some(("CCCGGG", 3)), "KpnI" => Some(("GGTACC", 5)),
        "XbaI" => Some(("TCTAGA", 1)), "NotI" => Some(("GCGGCCGC", 2)),
        "EcoRV" => Some(("GATATC", 3)), "HaeIII" => Some(("GGCC", 2)),
        "AluI" => Some(("AGCT", 2)), "TaqI" => Some(("TCGA", 1)),
        "Sau3AI" => Some(("GATC", 0)), "HincII" => Some(("GTYRAC", 3)),
        "AvaI" => Some(("CYCGRG", 1)),
        _ => None,
    }
}

fn arity(command: &str) -> Option<(usize, usize)> {
    match command {
        "SEQ" | "TRANSLATE" | "CODONS" | "PROTEIN" | "ORFS" | "FIND" |
        "HAMMING" | "FOLD" => Some((2, 2)),
        "SLICE" | "REPEATS" => Some((4, 4)),
        "JOIN" => Some((3, 9)),
        "MUTATE" | "GCWINDOW" | "KMERS" | "PALINDROMES" | "UNPACK" => Some((3, 3)),
        "DEL" | "REVCOMP" | "COMPLEMENT" | "REVERSE" | "TRANSCRIBE" |
        "GC" | "SKEW" | "TM" | "MASS" | "PRIMER" | "PACK" => Some((1, 1)),
        "LIST" => Some((0, 0)),
        "RESTRICT" => Some((2, 7)),
        "ALIGN" => Some((6, 6)),
        "CONSENSUS" => Some((2, 10)),
        "ASSEMBLE" => Some((4, 10)),
        _ => None,
    }
}

fn kinds(command: &str, count: usize) -> Vec<&'static str> {
    match command {
        "SEQ" => vec!["new", "sequence"],
        "SLICE" => vec!["name", "position", "position", "new"],
        "MUTATE" => vec!["name", "position", "base"],
        "TRANSLATE" | "CODONS" | "PROTEIN" => vec!["name", "frame"],
        "ORFS" => vec!["name", "orf"],
        "GCWINDOW" => vec!["name", "window", "window"],
        "KMERS" => vec!["name", "kmer", "limit"],
        "FIND" => vec!["name", "motif"],
        "PALINDROMES" => vec!["name", "palindrome", "palindrome"],
        "REPEATS" => vec!["name", "repeat", "repeat", "repeat_count"],
        "ALIGN" => vec!["name", "name", "mode", "match", "mismatch", "gap"],
        "FOLD" => vec!["name", "loop"],
        "UNPACK" => vec!["new", "length", "hex"],
        _ => {
            let mut result = vec!["name"; count];
            if command == "JOIN" || command == "ASSEMBLE" {
                result[0] = "new";
            }
            if command == "ASSEMBLE" {
                result[1] = "overlap";
            }
            if command == "RESTRICT" {
                for item in &mut result[1..] {
                    *item = "enzyme";
                }
            }
            result
        }
    }
}

fn number(text: &str, minimum: i32, maximum: i32, nonzero: bool) -> Result<i32, String> {
    let digits = text.strip_prefix('-').unwrap_or(text);
    if digits.is_empty() || digits.len() > 6 || !digits.bytes().all(|c| c.is_ascii_digit()) {
        return Err(format!("invalid number {text}"));
    }
    let value = text.parse::<i32>().map_err(|_| format!("invalid number {text}"))?;
    if value < minimum || value > maximum || (nonzero && value == 0) {
        return Err(format!("invalid number {text}"));
    }
    Ok(value)
}

fn revcomp(sequence: &str) -> String {
    sequence.bytes().rev().map(complement).map(char::from).collect()
}

fn complementary(sequence: &str) -> String {
    sequence.bytes().map(complement).map(char::from).collect()
}

fn gc(sequence: &str) -> usize {
    sequence.bytes().filter(|&b| b == b'G' || b == b'C').count()
}

fn fixed(value: i32, places: u32) -> String {
    let scale = 10_i32.pow(places);
    format!("{}.{:0width$}", value / scale, value % scale, width = places as usize)
}

fn percentage(part: usize, whole: usize) -> String {
    fixed((10000 * part / whole) as i32, 2)
}

fn transition(a: u8, b: u8) -> bool {
    a != b && matches!(
        (a, b), (b'A', b'G') | (b'G', b'A') | (b'C', b'T') | (b'T', b'C')
    )
}

fn frequency_order(counts: &BTreeMap<String, usize>) -> Vec<String> {
    let mut names: Vec<String> = counts.keys().cloned().collect();
    names.sort_by(|a, b| counts[b].cmp(&counts[a]).then_with(|| a.cmp(b)));
    names
}

fn codons(sequence: &str, frame: i32) -> Vec<String> {
    let strand = if frame > 0 { sequence.to_owned() } else { revcomp(sequence) };
    let offset = frame.unsigned_abs() as usize - 1;
    (offset..strand.len().saturating_sub(2))
        .step_by(3)
        .map(|i| strand[i..i + 3].to_owned())
        .collect()
}

fn occurrences(sequence: &str, motif: &str) -> Vec<usize> {
    let mut positions = Vec::new();
    if motif.len() > sequence.len() {
        return positions;
    }
    for i in 0..=(sequence.len() - motif.len()) {
        if motif.bytes().enumerate().all(|(j, symbol)| {
            iupac(symbol).expect("validated motif").contains(&sequence.as_bytes()[i + j])
        }) {
            positions.push(i + 1);
        }
    }
    positions
}

fn repeat_count(sequence: &str, start: usize, width: usize) -> usize {
    let unit = &sequence[start..start + width];
    let mut count = 0;
    while start + (count + 1) * width <= sequence.len() &&
        &sequence[start + count * width..start + (count + 1) * width] == unit {
        count += 1;
    }
    count
}

fn primitive(unit: &str) -> bool {
    (1..unit.len()).all(|width| {
        unit.len() % width != 0 ||
            (width..unit.len()).any(|i| unit.as_bytes()[i] != unit.as_bytes()[i % width])
    })
}

fn longest_palindrome(sequence: &str) -> usize {
    let mut longest = 0;
    for center in 1..sequence.len() {
        let mut left = center as isize - 1;
        let mut right = center;
        while left >= 0 && right < sequence.len() &&
            complement(sequence.as_bytes()[left as usize]) == sequence.as_bytes()[right] {
            longest = longest.max(right - left as usize + 1);
            left -= 1;
            right += 1;
        }
    }
    longest
}

fn temperature(sequence: &str) -> i32 {
    let n = sequence.len() as i32;
    let amount = gc(sequence) as i32;
    if n < 14 {
        10 * (2 * (n - amount) + 4 * amount)
    } else {
        (649 * n + 410 * amount - 6724) / n
    }
}

fn strand_mass(sequence: &str) -> i32 {
    sequence.bytes().map(base_mass).sum::<i32>() - (sequence.len() as i32 - 1) * 18015
}

fn list_text<T: ToString>(values: &[T]) -> String {
    if values.is_empty() {
        "none".to_owned()
    } else {
        values.iter().map(ToString::to_string).collect::<Vec<_>>().join(" ")
    }
}

struct Toolkit {
    sequences: BTreeMap<String, String>,
    output: Vec<String>,
}

impl Toolkit {
    fn new() -> Self {
        Self { sequences: BTreeMap::new(), output: Vec::new() }
    }

    fn emit(&mut self, line: impl Into<String>) {
        self.output.push(line.into());
    }

    fn validate(&self, command: &str, args: &[&str]) -> Result<(), String> {
        let (minimum, maximum) =
            arity(command).ok_or_else(|| format!("unknown command {command}"))?;
        if args.len() < minimum || args.len() > maximum {
            return Err("wrong argument count".to_owned());
        }
        let mut seen = HashSet::new();
        for (i, (kind, text)) in kinds(command, args.len()).iter().zip(args.iter()).enumerate() {
            let text = *text;
            match *kind {
                "position" | "frame" | "orf" | "window" | "kmer" | "limit" |
                "palindrome" | "repeat" | "repeat_count" | "match" |
                "mismatch" | "gap" | "loop" | "overlap" | "length" => {
                    let (min, max) = match *kind {
                        "position" => (1, self.sequences[args[0]].len() as i32),
                        "frame" => (-3, 3),
                        "orf" => (1, 200),
                        "kmer" => (1, 12),
                        "limit" | "overlap" => (1, 100),
                        "palindrome" => (2, 20),
                        "repeat" => (1, 6),
                        "repeat_count" => (2, 50),
                        "match" => (1, 20),
                        "mismatch" => (-20, 0),
                        "gap" => (-20, -1),
                        "loop" => (0, 10),
                        _ => (1, 500),
                    };
                    number(text, min, max, *kind == "frame")?;
                }
                "name" => {
                    if !self.sequences.contains_key(text) {
                        return Err(format!("unknown sequence {text}"));
                    }
                }
                "new" => {
                    let bytes = text.as_bytes();
                    if bytes.is_empty() || bytes.len() > 10 ||
                       !(b'a'..=b'z').contains(&bytes[0]) ||
                       !bytes.iter().all(|&c| c.is_ascii_lowercase() || c.is_ascii_digit()) {
                        return Err(format!("invalid name {text}"));
                    }
                }
                "sequence" => {
                    for (position, base) in text.bytes().enumerate() {
                        if !BASES.contains(&base) {
                            return Err(format!("invalid base {} at {}", base as char, position + 1));
                        }
                    }
                }
                "base" => {
                    if text.len() != 1 || !BASES.contains(&text.as_bytes()[0]) {
                        return Err(format!("invalid base {text}"));
                    }
                }
                "motif" => {
                    if text.is_empty() || text.len() > 30 ||
                       !text.bytes().all(|c| iupac(c).is_some()) {
                        return Err(format!("invalid motif {text}"));
                    }
                }
                "enzyme" => {
                    if enzyme(text).is_none() {
                        return Err(format!("unknown enzyme {text}"));
                    }
                    if !seen.insert(text) {
                        return Err(format!("duplicate enzyme {text}"));
                    }
                }
                "mode" => {
                    if text != "GLOBAL" && text != "LOCAL" {
                        return Err(format!("invalid mode {text}"));
                    }
                }
                "hex" => {
                    let length = args[1].parse::<usize>().expect("validated preceding length");
                    if text.len() != 2 * length.div_ceil(4) ||
                       !text.bytes().all(|c| c.is_ascii_digit() || (b'A'..=b'F').contains(&c)) {
                        return Err("invalid hex".to_owned());
                    }
                }
                _ => unreachable!("all argument kinds accounted for"),
            }
            let _ = i;
        }
        Ok(())
    }

    fn store(&mut self, name: &str, sequence: String) -> Result<String, String> {
        if sequence.len() > 500 {
            return Err("too long".to_owned());
        }
        let action = if self.sequences.contains_key(name) { "replaced" } else { "stored" };
        let result = format!("{action} {name} {} nt", sequence.len());
        self.sequences.insert(name.to_owned(), sequence);
        Ok(result)
    }

    fn translation(&mut self, command: &str, name: &str, frame: i32) -> Result<(), String> {
        let triplets = codons(&self.sequences[name], frame);
        let mut protein: String = triplets.iter().map(|c| amino(c)).collect();
        match command {
            "TRANSLATE" => self.emit(if protein.is_empty() { "none" } else { &protein }),
            "CODONS" => {
                let mut counts = BTreeMap::new();
                for codon in triplets {
                    *counts.entry(codon).or_insert(0_usize) += 1;
                }
                if counts.is_empty() {
                    self.emit("none");
                }
                for codon in frequency_order(&counts) {
                    self.emit(format!("{codon} {} {}", amino(&codon), counts[&codon]));
                }
            }
            _ => {
                if let Some(stop) = protein.find('*') {
                    protein.truncate(stop);
                }
                if protein.is_empty() {
                    return Err("empty protein".to_owned());
                }
                let mut counts: BTreeMap<String, usize> = BTreeMap::new();
                let mut mass = 18015;
                let mut charge = 0;
                for letter in protein.bytes() {
                    *counts.entry((letter as char).to_string()).or_insert(0) += 1;
                    mass += amino_mass(letter);
                    charge += i32::from(letter == b'K' || letter == b'R');
                    charge -= i32::from(letter == b'D' || letter == b'E');
                }
                self.emit(protein.clone());
                let charge_text = if charge > 0 { format!("+{charge}") } else { charge.to_string() };
                self.emit(format!(
                    "length {} mass {} charge {}", protein.len(), fixed(mass, 3), charge_text
                ));
                let composition = frequency_order(&counts).iter()
                    .map(|amino| format!("{amino}={}", counts[amino]))
                    .collect::<Vec<_>>().join(" ");
                self.emit(composition);
            }
        }
        Ok(())
    }

    fn orfs(&mut self, sequence: &str, minimum: usize) {
        let mut rows: Vec<(usize, usize, i32, String)> = Vec::new();
        for frame in [1_i32, 2, 3, -1, -2, -3] {
            let triplets = codons(sequence, frame);
            let mut start: Option<usize> = None;
            for (position, codon) in triplets.iter().enumerate() {
                if start.is_none() {
                    if codon == "ATG" {
                        start = Some(position);
                    }
                } else if amino(codon) == '*' {
                    let first = start.expect("inside an ORF");
                    if position - first >= minimum {
                        let mut left = frame.unsigned_abs() as usize - 1 + 3 * first;
                        let mut right = frame.unsigned_abs() as usize - 1 + 3 * (position + 1);
                        if frame < 0 {
                            (left, right) = (sequence.len() - right, sequence.len() - left);
                        }
                        let protein: String = triplets[first..position]
                            .iter().map(|codon| amino(codon)).collect();
                        rows.push((left + 1, right, frame, protein));
                    }
                    start = None;
                }
            }
        }
        rows.sort();
        if rows.is_empty() {
            self.emit("none");
        }
        for (left, right, frame, protein) in rows {
            self.emit(format!(
                "{frame:+} {left} {right} {} {protein}", protein.len()
            ));
        }
    }

    fn restriction(&mut self, sequence: &str, selected: &[&str]) {
        let mut all_cuts = BTreeSet::new();
        for &name in selected {
            let (motif, offset) = enzyme(name).expect("validated enzyme");
            let mut cuts = Vec::new();
            for position in occurrences(sequence, motif) {
                let cut = position as i32 + offset - 1;
                if cut >= 1 && cut < sequence.len() as i32 {
                    cuts.push(cut);
                    all_cuts.insert(cut);
                }
            }
            self.emit(format!("{name} {}", list_text(&cuts)));
        }
        let mut endpoints = vec![0];
        endpoints.extend(all_cuts);
        endpoints.push(sequence.len() as i32);
        let mut fragments = Vec::new();
        let mut sizes = Vec::new();
        for pair in endpoints.windows(2) {
            fragments.push(format!("{}-{}", pair[0] + 1, pair[1]));
            sizes.push(pair[1] - pair[0]);
        }
        sizes.sort_by(|a, b| b.cmp(a));
        self.emit(format!("fragments {}", list_text(&fragments)));
        self.emit(format!("sizes {}", list_text(&sizes)));
    }

    fn repeats(&mut self, sequence: &str, minimum: usize, maximum: usize, count: usize)
        -> Result<(), String>
    {
        if minimum > maximum {
            return Err("invalid range".to_owned());
        }
        let mut rows: Vec<(usize, usize, usize, String)> = Vec::new();
        for width in minimum..=maximum {
            let mut position = 0;
            while position + width <= sequence.len() {
                let unit = &sequence[position..position + width];
                let repeated = repeat_count(sequence, position, width);
                if primitive(unit) && repeated >= count {
                    rows.push((position, width, repeated, unit.to_owned()));
                    position += repeated * width;
                } else {
                    position += 1;
                }
            }
        }
        rows.sort();
        if rows.is_empty() {
            self.emit("none");
        }
        for (position, width, repeated, unit) in rows {
            self.emit(format!(
                "{}-{} {unit}x{repeated}", position + 1, position + width * repeated
            ));
        }
        Ok(())
    }

    fn alignment(&mut self, a: &str, b: &str, mode: &str,
                 match_score: i32, mismatch: i32, gap: i32) {
        let m = a.len();
        let n = b.len();
        let local = mode == "LOCAL";
        let mut table = vec![vec![0; n + 1]; m + 1];
        if !local {
            for (i, row) in table.iter_mut().enumerate() {
                row[0] = i as i32 * gap;
            }
            for j in 0..=n {
                table[0][j] = j as i32 * gap;
            }
        }
        let (mut best, mut end_i, mut end_j) = (0, 0, 0);
        for i in 1..=m {
            for j in 1..=n {
                let score = if a.as_bytes()[i-1] == b.as_bytes()[j-1] {
                    match_score
                } else {
                    mismatch
                };
                let candidate = (table[i-1][j-1] + score)
                    .max(table[i-1][j] + gap)
                    .max(table[i][j-1] + gap);
                table[i][j] = if local { candidate.max(0) } else { candidate };
                if local && table[i][j] > best {
                    (best, end_i, end_j) = (table[i][j], i, j);
                }
            }
        }
        if !local {
            (best, end_i, end_j) = (table[m][n], m, n);
        }
        if local && best == 0 {
            self.emit("score 0");
            return;
        }
        let (mut i, mut j) = (end_i, end_j);
        let (mut row_a, mut row_b) = (Vec::new(), Vec::new());
        while (local && table[i][j] != 0) || (!local && (i != 0 || j != 0)) {
            let score = if i > 0 && j > 0 && a.as_bytes()[i-1] == b.as_bytes()[j-1] {
                match_score
            } else {
                mismatch
            };
            if i > 0 && j > 0 && table[i][j] == table[i-1][j-1] + score {
                i -= 1;
                j -= 1;
                row_a.push(a.as_bytes()[i]);
                row_b.push(b.as_bytes()[j]);
            } else if i > 0 && table[i][j] == table[i-1][j] + gap {
                i -= 1;
                row_a.push(a.as_bytes()[i]);
                row_b.push(b'-');
            } else {
                j -= 1;
                row_a.push(b'-');
                row_b.push(b.as_bytes()[j]);
            }
        }
        row_a.reverse();
        row_b.reverse();
        let mut marks = Vec::new();
        for (&left, &right) in row_a.iter().zip(&row_b) {
            marks.push(if left == b'-' || right == b'-' { b'-' }
                       else if left == right { b'|' } else { b'*' });
        }
        let identical = marks.iter().filter(|&&mark| mark == b'|').count();
        let gaps = marks.iter().filter(|&&mark| mark == b'-').count();
        self.emit(format!(
            "score {best} a {}-{end_i} b {}-{end_j} identity {identical}/{} gaps {gaps}",
            i + 1, j + 1, marks.len()
        ));
        self.emit(String::from_utf8(row_a).expect("ASCII"));
        self.emit(String::from_utf8(marks).expect("ASCII"));
        self.emit(String::from_utf8(row_b).expect("ASCII"));
    }

    fn consensus(&mut self, names: &[&str]) -> Result<(), String> {
        let n = self.sequences[names[0]].len();
        if names.iter().any(|name| self.sequences[*name].len() != n) {
            return Err("length mismatch".to_owned());
        }
        let mut profile: [Vec<usize>; 4] = std::array::from_fn(|_| Vec::new());
        let (mut consensus, mut ambiguous) = (String::new(), String::new());
        for position in 0..n {
            let mut counts = [0_usize; 4];
            for name in names {
                let base = self.sequences[*name].as_bytes()[position];
                let index = BASES.iter().position(|&c| c == base).expect("validated sequence");
                counts[index] += 1;
            }
            let largest = *counts.iter().max().expect("four base counts");
            let mut tied = String::new();
            for (i, &base) in BASES.iter().enumerate() {
                profile[i].push(counts[i]);
                if counts[i] == largest {
                    tied.push(base as char);
                }
            }
            consensus.push(tied.chars().next().expect("nonempty base set"));
            ambiguous.push(symbol(&tied));
        }
        for (i, counts) in profile.iter().enumerate() {
            self.emit(format!("{} {}", BASES[i] as char, list_text(counts)));
        }
        self.emit(format!("consensus {consensus}"));
        self.emit(format!("iupac {ambiguous}"));
        Ok(())
    }

    fn primer(&mut self, sequence: &str) {
        let n = sequence.len();
        let amount = gc(sequence);
        let tm = temperature(sequence);
        let clamp = gc(&sequence[n.saturating_sub(5)..]);
        let mut longest_run = 0;
        let mut run = 0;
        let mut previous = 0;
        for base in sequence.bytes() {
            run = if base == previous { run + 1 } else { 1 };
            longest_run = longest_run.max(run);
            previous = base;
        }
        let mut repeated = 0;
        for i in 0..n.saturating_sub(1) {
            if sequence.as_bytes()[i] != sequence.as_bytes()[i+1] {
                repeated = repeated.max(repeat_count(sequence, i, 2));
            }
        }
        let selfcomp = longest_palindrome(sequence);
        let checks = [
            ("length", n.to_string(), (18..=25).contains(&n)),
            ("gc", percentage(amount, n), 40*n <= 100*amount && 100*amount <= 60*n),
            ("tm", fixed(tm, 1), (520..=620).contains(&tm)),
            ("clamp", clamp.to_string(), (1..=3).contains(&clamp)),
            ("run", longest_run.to_string(), longest_run <= 4),
            ("repeat", repeated.to_string(), repeated <= 4),
            ("selfcomp", selfcomp.to_string(), selfcomp <= 6),
        ];
        let mut failed = Vec::new();
        for (label, value, passed) in checks {
            self.emit(format!("{label} {value} {}", if passed { "OK" } else { "FAIL" }));
            if !passed {
                failed.push(label);
            }
        }
        self.emit(if failed.is_empty() {
            "PASS".to_owned()
        } else {
            format!("FAIL {}", failed.join(" "))
        });
    }

    fn paired(a: u8, b: u8) -> bool {
        matches!((a, b),
            (b'A', b'T') | (b'T', b'A') | (b'C', b'G') | (b'G', b'C') |
            (b'G', b'T') | (b'T', b'G'))
    }

    fn cell(table: &[Vec<i32>], i: isize, j: isize) -> i32 {
        if i > j { 0 } else { table[i as usize][j as usize] }
    }

    fn folding(&mut self, sequence: &str, loop_size: usize) -> Result<(), String> {
        let n = sequence.len();
        if n > 100 {
            return Err("too long".to_owned());
        }
        let mut table = vec![vec![0; n]; n];
        let bases = sequence.as_bytes();
        for width in 2..=n {
            for i in 0..=(n - width) {
                let j = i + width - 1;
                let mut best = Self::cell(&table, i as isize, (j - 1) as isize);
                let limit = j.saturating_sub(loop_size);
                for k in i..limit {
                    if Self::paired(bases[k], bases[j]) {
                        let candidate = Self::cell(&table, i as isize, k as isize - 1) + 1 +
                            Self::cell(&table, k as isize + 1, j as isize - 1);
                        best = best.max(candidate);
                    }
                }
                table[i][j] = best;
            }
        }
        let mut structure = vec![b'.'; n];
        let mut pending = vec![(0_isize, n as isize - 1)];
        while let Some((i, j)) = pending.pop() {
            if i > j || Self::cell(&table, i, j) == 0 {
                continue;
            }
            if Self::cell(&table, i, j) == Self::cell(&table, i, j - 1) {
                pending.push((i, j - 1));
                continue;
            }
            let limit = (j - loop_size as isize).max(i);
            for k in i..limit {
                let k_usize = k as usize;
                if Self::paired(bases[k_usize], bases[j as usize]) &&
                   Self::cell(&table, i, k-1) + 1 + Self::cell(&table, k+1, j-1) ==
                       Self::cell(&table, i, j) {
                    structure[k_usize] = b'(';
                    structure[j as usize] = b')';
                    pending.push((i, k-1));
                    pending.push((k+1, j-1));
                    break;
                }
            }
        }
        self.emit(String::from_utf8(structure).expect("ASCII"));
        self.emit(format!("pairs {}", table[0][n-1]));
        Ok(())
    }

    fn assembly(&mut self, name: &str, minimum: usize, sequences: &[String])
        -> Result<(), String>
    {
        let mut unique = Vec::new();
        let mut seen = HashSet::new();
        for sequence in sequences {
            if seen.insert(sequence.clone()) {
                unique.push(sequence.clone());
            }
        }
        let mut fragments: Vec<String> = unique.iter()
            .filter(|sequence| !unique.iter().any(|other|
                *sequence != other && other.contains(sequence.as_str())))
            .cloned().collect();
        while fragments.len() >= 2 {
            let (mut best, mut chosen) = (0_usize, None);
            for i in 0..fragments.len() {
                for j in 0..fragments.len() {
                    if i == j {
                        continue;
                    }
                    let a = &fragments[i];
                    let b = &fragments[j];
                    let mut overlap = 0;
                    for width in (1..a.len().min(b.len())).rev() {
                        if a.ends_with(&b[..width]) {
                            overlap = width;
                            break;
                        }
                    }
                    if chosen.is_none() || overlap > best {
                        best = overlap;
                        chosen = Some((i, j));
                    }
                }
            }
            if best < minimum {
                break;
            }
            let (first, second) = chosen.expect("at least two fragments");
            let merged = fragments[first].clone() + &fragments[second][best..];
            fragments = fragments.iter().enumerate().filter_map(|(i, sequence)| {
                if i == first {
                    Some(merged.clone())
                } else if i != second && !merged.contains(sequence) {
                    Some(sequence.clone())
                } else {
                    None
                }
            }).collect();
        }
        let longest = fragments.iter()
            .max_by_key(|sequence| (sequence.len(), std::cmp::Reverse(
                fragments.iter().position(|item| item == *sequence).expect("present")
            )))
            .expect("at least one fragment").clone();
        let registration = self.store(name, longest)?;
        self.emit(format!("contigs {}", fragments.len()));
        for fragment in fragments {
            self.emit(format!("{} {fragment}", fragment.len()));
        }
        self.emit(registration);
        Ok(())
    }

    fn command(&mut self, command: &str, args: &[&str]) -> Result<(), String> {
        match command {
            "SEQ" => {
                let result = self.store(args[0], args[1].to_owned())?;
                self.emit(result);
                return Ok(());
            }
            "UNPACK" => {
                let length = args[1].parse::<usize>().expect("validated number");
                let mut codes = Vec::new();
                for bytes in args[2].as_bytes().chunks_exact(2) {
                    let number = u8::from_str_radix(
                        std::str::from_utf8(bytes).expect("ASCII"), 16
                    ).expect("validated hex");
                    codes.extend([
                        number / 64, number / 16 % 4, number / 4 % 4, number % 4
                    ]);
                }
                if codes[length..].iter().any(|&code| code != 0) {
                    return Err("invalid padding".to_owned());
                }
                let sequence: String = codes[..length].iter()
                    .map(|&code| BASES[code as usize] as char).collect();
                let result = self.store(args[0], sequence)?;
                self.emit(result);
                return Ok(());
            }
            "JOIN" => {
                let sequence: String = args[1..].iter()
                    .map(|name| self.sequences[*name].as_str()).collect();
                let result = self.store(args[0], sequence)?;
                self.emit(result);
                return Ok(());
            }
            "ASSEMBLE" => {
                let minimum = args[1].parse::<usize>().expect("validated overlap");
                let fragments: Vec<String> = args[2..].iter()
                    .map(|name| self.sequences[*name].clone()).collect();
                return self.assembly(args[0], minimum, &fragments);
            }
            "LIST" => {
                if self.sequences.is_empty() {
                    self.emit("no sequences");
                }
                let entries: Vec<(String, usize)> = self.sequences.iter()
                    .map(|(name, sequence)| (name.clone(), sequence.len())).collect();
                for (name, length) in entries {
                    self.emit(format!("{name} {length} nt"));
                }
                return Ok(());
            }
            _ => {}
        }

        let name = args[0].to_owned();
        let sequence = self.sequences[&name].clone();
        let n = sequence.len();
        match command {
            "SLICE" => {
                let start = args[1].parse::<usize>().expect("validated position");
                let end = args[2].parse::<usize>().expect("validated position");
                let segment = if start <= end {
                    sequence[start-1..end].to_owned()
                } else {
                    revcomp(&sequence[end-1..start])
                };
                let result = self.store(args[3], segment)?;
                self.emit(result);
            }
            "MUTATE" => {
                let position = args[1].parse::<usize>().expect("validated position");
                let before = sequence.as_bytes()[position-1];
                let after = args[2].as_bytes()[0];
                if before == after {
                    return Err("no change".to_owned());
                }
                let mut replacement = sequence.into_bytes();
                replacement[position-1] = after;
                self.sequences.insert(
                    name.clone(), String::from_utf8(replacement).expect("ASCII")
                );
                self.emit(format!(
                    "{name} {}{position}{} {}", before as char, after as char,
                    if transition(before, after) { "transition" } else { "transversion" }
                ));
            }
            "DEL" => {
                self.sequences.remove(&name);
                self.emit(format!("deleted {name}"));
            }
            "REVCOMP" => self.emit(revcomp(&sequence)),
            "COMPLEMENT" => self.emit(complementary(&sequence)),
            "REVERSE" => self.emit(sequence.chars().rev().collect::<String>()),
            "TRANSCRIBE" => self.emit(sequence.replace('T', "U")),
            "TRANSLATE" | "CODONS" | "PROTEIN" => {
                let frame = args[1].parse::<i32>().expect("validated frame");
                self.translation(command, &name, frame)?;
            }
            "ORFS" => {
                let minimum = args[1].parse::<usize>().expect("validated minimum");
                self.orfs(&sequence, minimum);
            }
            "GC" => {
                let fields = BASES.iter().map(|&base| {
                    format!("{}={}", base as char,
                        sequence.bytes().filter(|&c| c == base).count())
                }).collect::<Vec<_>>();
                self.emit(format!("{} GC={}%", fields.join(" "), percentage(gc(&sequence), n)));
            }
            "GCWINDOW" => {
                let width = args[1].parse::<usize>().expect("validated width");
                let step = args[2].parse::<usize>().expect("validated step");
                if width > n {
                    return Err("window too large".to_owned());
                }
                for i in (0..=n-width).step_by(step) {
                    self.emit(format!("{}-{} {}%",
                        i+1, i+width, percentage(gc(&sequence[i..i+width]), width)));
                }
            }
            "SKEW" => {
                let mut values = vec![0_i32];
                for base in sequence.bytes() {
                    values.push(values.last().expect("initial zero") +
                        i32::from(base == b'G') - i32::from(base == b'C'));
                }
                for (label, extreme) in [
                    ("min", *values.iter().min().expect("nonempty")),
                    ("max", *values.iter().max().expect("nonempty")),
                ] {
                    let positions = values.iter().enumerate()
                        .filter(|&(_, value)| *value == extreme)
                        .map(|(position, _)| position).collect::<Vec<_>>();
                    self.emit(format!("{label} {extreme} at {}", list_text(&positions)));
                }
            }
            "KMERS" => {
                let width = args[1].parse::<usize>().expect("validated k");
                let limit = args[2].parse::<usize>().expect("validated limit");
                if width > n {
                    return Err("k too large".to_owned());
                }
                let mut counts = BTreeMap::new();
                for i in 0..=n-width {
                    *counts.entry(sequence[i..i+width].to_owned()).or_insert(0) += 1;
                }
                self.emit(format!("{} windows {} distinct", n-width+1, counts.len()));
                for word in frequency_order(&counts).into_iter().take(limit) {
                    self.emit(format!("{word} {}", counts[&word]));
                }
            }
            "FIND" => {
                self.emit(format!("forward {}", list_text(&occurrences(&sequence, args[1]))));
                self.emit(format!("reverse {}", list_text(&occurrences(&sequence, &revcomp(args[1])))));
            }
            "RESTRICT" => self.restriction(&sequence, &args[1..]),
            "PALINDROMES" => {
                let minimum = args[1].parse::<usize>().expect("validated min");
                let maximum = args[2].parse::<usize>().expect("validated max");
                if minimum > maximum {
                    return Err("invalid range".to_owned());
                }
                let mut found = false;
                for i in 0..n {
                    for width in minimum..=maximum.min(n-i) {
                        let part = &sequence[i..i+width];
                        if part == revcomp(part) {
                            self.emit(format!("{} {width} {part}", i+1));
                            found = true;
                        }
                    }
                }
                if !found {
                    self.emit("none");
                }
            }
            "REPEATS" => {
                let min = args[1].parse::<usize>().expect("validated min");
                let max = args[2].parse::<usize>().expect("validated max");
                let count = args[3].parse::<usize>().expect("validated count");
                self.repeats(&sequence, min, max, count)?;
            }
            "HAMMING" => {
                let other = &self.sequences[args[1]];
                if other.len() != n {
                    return Err("length mismatch".to_owned());
                }
                let mut distance = 0;
                let mut transitions = 0;
                for (&a, &b) in sequence.as_bytes().iter().zip(other.bytes().collect::<Vec<_>>().iter()) {
                    if a != b {
                        distance += 1;
                        transitions += i32::from(transition(a, b));
                    }
                }
                self.emit(format!(
                    "distance {distance} transitions {transitions} transversions {}",
                    distance-transitions
                ));
            }
            "ALIGN" => {
                let match_score = args[3].parse::<i32>().expect("validated match");
                let mismatch = args[4].parse::<i32>().expect("validated mismatch");
                let gap = args[5].parse::<i32>().expect("validated gap");
                let other = self.sequences[args[1]].clone();
                self.alignment(&sequence, &other, args[2], match_score, mismatch, gap);
            }
            "CONSENSUS" => self.consensus(args)?,
            "TM" => self.emit(format!(
                "Tm {} {}", fixed(temperature(&sequence), 1),
                if n < 14 { "wallace" } else { "gc" }
            )),
            "MASS" => {
                let single = strand_mass(&sequence);
                self.emit(format!(
                    "ss {} ds {}", fixed(single, 3),
                    fixed(single + strand_mass(&revcomp(&sequence)), 3)
                ));
            }
            "PRIMER" => self.primer(&sequence),
            "FOLD" => {
                let loop_size = args[1].parse::<usize>().expect("validated loop");
                self.folding(&sequence, loop_size)?;
            }
            "PACK" => {
                let mut codes: Vec<usize> = sequence.bytes()
                    .map(|base| BASES.iter().position(|&c| c == base).expect("DNA")).collect();
                codes.resize(codes.len().div_ceil(4) * 4, 0);
                let hex = codes.chunks(4).map(|group| format!("{:02X}",
                    64*group[0] + 16*group[1] + 4*group[2] + group[3]))
                    .collect::<String>();
                self.emit(format!("{n} {hex}"));
            }
            _ => unreachable!("validated command"),
        }
        Ok(())
    }

    fn execute(&mut self, line: &str) {
        let words: Vec<&str> = line.split(' ').collect();
        let command = words[0];
        let args = &words[1..];
        let result = self.validate(command, args)
            .and_then(|_| self.command(command, args));
        if let Err(error) = result {
            self.emit(format!("ERROR {error}"));
        }
    }
}

fn main() {
    let mut text = String::new();
    io::stdin().read_to_string(&mut text).expect("stdin");
    let mut lines = text.lines();
    let count = lines.next().expect("count").parse::<usize>().expect("integer count");
    let mut tool = Toolkit::new();
    for line in lines.take(count) {
        tool.execute(line);
    }
    for line in tool.output {
        println!("{line}");
    }
}
