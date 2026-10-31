use std::io::{self, BufRead, Write};

const N: usize = 108;
const Q: usize = 109;
const L: usize = 110;
const SYSTEMS: [&str; 5] = ["HEPBURN", "TRADITIONAL", "KUNREI", "NIHON", "WAPURO"];
const ROWS: [&str; 15] = ["a", "ka", "sa", "ta", "na", "ha", "ma", "ya", "ra", "wa", "ga", "za", "da", "ba", "pa"];

struct Mora {
    id: String,
    row: usize,
    dan: String,
    spelling: [String; 5],
    base: usize,
    voice: usize,
}
struct Token { id: usize, col: usize }
struct Word {
    original: String,
    start: usize,
    end: usize,
    section: usize,
    pattern: usize,
    tokens: Vec<Token>,
}
struct Element { id: usize, voice: usize, size: usize }
#[derive(Default)]
struct Settings { long: usize, casing: usize, order: usize }

fn index(items: &[&str], s: &str) -> Option<usize> {
    items.iter().position(|&item| item == s)
}
fn vowel(c: u8) -> bool { b"aiueo".contains(&c) }
fn word_char(c: u8) -> bool { c.is_ascii_alphabetic() || c == b'\'' || c == b'-' }
fn col_error(col: usize, message: &str) -> String { format!("col {col}: {message}") }
fn mora_id(table: &[Mora], id: &str) -> usize {
    table.iter().position(|m| m.id == id).unwrap_or(N)
}
fn initialize() -> Vec<Mora> {
    let base = [
        "a i u e o", "ka ki ku ke ko", "sa si su se so", "ta ti tu te to",
        "na ni nu ne no", "ha hi hu he ho", "ma mi mu me mo", "ya yu yo",
        "ra ri ru re ro", "wa wi we wo", "ga gi gu ge go", "za zi zu ze zo",
        "da di du de do", "ba bi bu be bo", "pa pi pu pe po",
    ];
    let base_rows = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 1, 2, 3, 5, 5];
    let mut table = Vec::new();
    for (r, line) in base.iter().enumerate() {
        for id in line.split(' ') {
            table.push(Mora {
                id: id.to_owned(), row: r, dan: id[id.len()-1..].to_owned(),
                spelling: Default::default(),
                base: base_rows[r], voice: if r == 14 { 2 } else if r >= 10 { 1 } else { 0 },
            });
        }
    }
    for r in [1, 2, 3, 4, 5, 6, 8, 10, 11, 12, 13, 14] {
        for dan in ["ya", "yu", "yo"] {
            table.push(Mora {
                id: format!("{}{dan}", &ROWS[r][..1]), row: r, dan: dan.to_owned(),
                spelling: Default::default(),
                base: base_rows[r], voice: if r == 14 { 2 } else if r >= 10 { 1 } else { 0 },
            });
        }
    }
    let special = ["si", "ti", "tu", "hu", "zi", "di", "du", "wi", "we", "wo"];
    let hepburn = ["shi", "chi", "tsu", "fu", "ji", "ji", "zu", "i", "e", "o"];
    let kunrei_from = ["di", "du", "wi", "we", "wo", "dya", "dyu", "dyo"];
    let kunrei_to = ["zi", "zu", "i", "e", "o", "zya", "zyu", "zyo"];
    for m in &mut table {
        for s in 0..5 {
            let mut p = m.id.clone();
            if let Some(k) = index(&special, &m.id) {
                if s <= 1 || s == 4 && k < 5 { p = hepburn[k].to_owned(); }
            }
            if s == 2 {
                if let Some(k) = index(&kunrei_from, &m.id) { p = kunrei_to[k].to_owned(); }
            }
            if m.dan.len() == 2 && (s <= 1 || s == 4) {
                match &m.id[..2] {
                    "sy" => p = format!("sh{}", &m.id[2..]),
                    "ty" => p = format!("ch{}", &m.id[2..]),
                    "zy" => p = format!("j{}", &m.id[2..]),
                    "dy" if s <= 1 => p = format!("j{}", &m.id[2..]),
                    _ => (),
                }
            }
            m.spelling[s] = p;
        }
    }
    table
}
fn lex(text: &str) -> Vec<Word> {
    let bytes = text.as_bytes();
    let mut words = Vec::new();
    let (mut i, mut section) = (0, 0);
    while i < bytes.len() {
        if !word_char(bytes[i]) {
            if bytes[i] == b'/' { section += 1; }
            i += 1;
            continue;
        }
        let start = i;
        while i < bytes.len() && word_char(bytes[i]) { i += 1; }
        words.push(Word {
            original: text[start..i].to_owned(), start, end: i, section,
            pattern: 0, tokens: Vec::new(),
        });
    }
    words
}
fn check_case(w: &mut Word) -> Result<(), String> {
    let bytes = w.original.as_bytes();
    let letters: Vec<u8> = bytes.iter().copied().filter(u8::is_ascii_alphabetic).collect();
    w.pattern = if letters.iter().all(u8::is_ascii_lowercase) { 0 }
        else if bytes[0].is_ascii_uppercase() && bytes[1..].iter().filter(|c| c.is_ascii_alphabetic()).all(u8::is_ascii_lowercase) { 1 }
        else if letters.len() >= 2 && letters.iter().all(u8::is_ascii_uppercase) { 2 }
        else { return Err(col_error(w.start+1, "mixed case")); };
    Ok(())
}
fn match_mora(table: &[Mora], s: &str, pos: usize, system: Option<usize>) -> Option<(usize, usize)> {
    let mut result = None;
    let mut length = 0;
    for (i, m) in table.iter().enumerate() {
        for (t, p) in m.spelling.iter().enumerate() {
            if system.is_some_and(|sys| t != sys) { continue; }
            if p.len() > length && s[pos..].starts_with(p.as_str()) {
                result = Some((i, p.len()));
                length = p.len();
            }
        }
    }
    result
}
fn parse(table: &[Mora], w: &mut Word, system: Option<usize>) -> Result<(), String> {
    w.tokens.clear();
    let s = w.original.to_ascii_lowercase();
    let bytes = s.as_bytes();
    let mut p = 0;
    while p < bytes.len() {
        let c = bytes[p];
        let c2 = *bytes.get(p+1).unwrap_or(&0);
        let (id, advance);
        if c == b'-' {
            if w.tokens.last().is_none_or(|t| t.id >= N) { return Err(col_error(w.start+p+1, "misplaced long mark")); }
            id = L;
            advance = 1;
        } else if c == b'\'' { return Err(col_error(w.start+p+1, "misplaced apostrophe")); }
        else if let Some(found) = match_mora(table, &s, p, system) {
            (id, advance) = found;
        } else if (system == Some(4) || system.is_none()) && s[p..].starts_with("xtu") {
            id = Q;
            advance = 3;
        } else if c == b'n' {
            id = N;
            let c3 = *bytes.get(p+2).unwrap_or(&0);
            let consume_two = if system.is_none() {
                c2 == b'\'' || c2 == b'n' && !vowel(c3) && c3 != b'y' && c3 != b'\''
            } else {
                system == Some(4) && c2 == b'n' || system != Some(4) && c2 == b'\''
            };
            advance = if consume_two { 2 } else { 1 };
        } else if (system == Some(1) || system.is_none()) && c == b'm' && b"bmp".contains(&c2) {
            id = N;
            advance = 1;
        } else {
            let next = match_mora(table, &s, p+1, system).is_some();
            if c.is_ascii_alphabetic() && !vowel(c) && c != b'n' && c2 == c && next
                || (system.is_none() || system == Some(0) || system == Some(1)) && c == b't' && s[p+1..].starts_with("ch") && next {
                id = Q;
                advance = 1;
            } else { return Err(col_error(w.start+p+1, "unknown syllable")); }
        }
        w.tokens.push(Token { id, col: w.start+p+1 });
        p += advance;
    }
    Ok(())
}
fn pairs(table: &[Mora], w: &Word, long_only: bool) -> Vec<bool> {
    let mut result = vec![false; w.tokens.len()];
    let mut i = 0;
    while i+1 < w.tokens.len() {
        let (a, b) = (w.tokens[i].id, w.tokens[i+1].id);
        if a < N && b < 5 {
            let x = *table[a].id.as_bytes().last().unwrap();
            let y = table[b].id.as_bytes()[0];
            if x == y || x == b'o' && y == b'u' || x == b'e' && y == b'i' {
                result[i+1] = !long_only || x == b'o' && (y == b'o' || y == b'u') || x == b'u' && y == b'u';
                i += 2;
                continue;
            }
        }
        i += 1;
    }
    if long_only {
        for (i, t) in w.tokens.iter().enumerate() {
            if t.id == L { result[i] = true; }
        }
    }
    result
}
fn parts(table: &[Mora], w: &Word, system: usize, mode: usize) -> Result<Vec<String>, String> {
    let long_elements = pairs(table, w, true);
    let mut result = Vec::new();
    for (i, t) in w.tokens.iter().enumerate() {
        let next_id = w.tokens.get(i+1).map(|t| t.id);
        let next = next_id.filter(|&id| id < N).map(|id| table[id].spelling[system].as_str()).unwrap_or("");
        let first = *next.as_bytes().first().unwrap_or(&0);
        let s;
        if long_elements[i] {
            let v = *table[w.tokens[i-1].id].id.as_bytes().last().unwrap();
            s = match mode {
                0 => if t.id == L { "-".to_owned() } else { table[t.id].spelling[system].clone() },
                2 if v == b'o' && !vowel(first) => "h".to_owned(),
                3 => "-".to_owned(),
                4 => (v as char).to_string(),
                _ => String::new(),
            };
        } else if t.id < N { s = table[t.id].spelling[system].clone(); }
        else if t.id == N {
            s = (if system == 4 {
                if next_id == Some(N) || vowel(first) || first == b'y' || first == b'n' { "nn" } else { "n" }
            } else if system == 1 && b"bmp".contains(&first) { "m" }
            else if vowel(first) || first == b'y' { "n'" } else { "n" }).to_owned();
        } else if first != 0 && !vowel(first) && first != b'n' {
            s = if system <= 1 && next.starts_with("ch") { "t".to_owned() } else { (first as char).to_string() };
        } else if system == 4 { s = "xtu".to_owned(); }
        else { return Err(col_error(t.col, "small tsu cannot be written")); }
        result.push(s);
    }
    Ok(result)
}
fn write_word(table: &[Mora], w: &Word, system: usize, canonical: bool, config: &Settings) -> Result<String, String> {
    let mode = if canonical { 0 } else { config.long };
    let pattern = if canonical || config.casing == 0 { w.pattern } else { [0, 0, 2, 1][config.casing] };
    let mut result = parts(table, w, system, mode)?.concat();
    if pattern == 1 && !result.is_empty() { result.replace_range(..1, &result[..1].to_ascii_uppercase()); }
    if pattern == 2 { result.make_ascii_uppercase(); }
    Ok(result)
}
fn sequence(table: &[Mora], w: &Word, loose: bool) -> Vec<usize> {
    let omit = pairs(table, w, true);
    w.tokens.iter().enumerate().filter(|(i, _)| !loose || !omit[*i]).map(|(_, t)| t.id).collect()
}
fn elements(table: &[Mora], w: &Word) -> Vec<Element> {
    let mut result = Vec::new();
    for t in &w.tokens {
        match t.id {
            L => (),
            N => result.push(Element { id: N, voice: 0, size: 0 }),
            Q => result.push(Element { id: mora_id(table, "tu"), voice: 0, size: 1 }),
            _ => {
                let m = &table[t.id];
                let mut base = m.id.clone();
                if m.voice > 0 { base.replace_range(..1, &(b"ksthh"[m.row-10] as char).to_string()); }
                if m.dan.len() == 2 {
                    result.push(Element { id: mora_id(table, &format!("{}i", &base[..1])), voice: m.voice, size: 0 });
                    result.push(Element { id: mora_id(table, &m.dan), voice: 0, size: 1 });
                } else { result.push(Element { id: mora_id(table, &base), voice: m.voice, size: 0 }); }
            }
        }
    }
    result
}
fn key(table: &[Mora], w: &Word, order: usize) -> [Vec<usize>; 4] {
    let ranks: Vec<&str> = if order == 0 {
        "a i u e o ka ki ku ke ko sa si su se so ta ti tu te to na ni nu ne no ha hi hu he ho ma mi mu me mo ya yu yo ra ri ru re ro wa wi we wo N"
    } else {
        "i ro ha ni ho he to ti ri nu ru wo wa ka yo ta re so tu ne na ra mu u wi no o ku ya ma ke hu ko e te a sa ki yu me mi si we hi mo se su N"
    }.split(' ').collect();
    let mut result: [Vec<usize>; 4] = Default::default();
    for e in elements(table, w) {
        result[0].push(index(&ranks, if e.id == N { "N" } else { &table[e.id].id }).unwrap());
        result[1].push(e.voice);
        result[2].push(e.size);
    }
    result[3] = w.tokens.iter().map(|t| usize::from(t.id == L)).collect();
    result
}
fn pattern_tokens(table: &[Mora], pattern: &str, system: usize) -> Result<Vec<isize>, String> {
    let mut result = Vec::new();
    let mut start = 0;
    for i in 0..=pattern.len() {
        let c = *pattern.as_bytes().get(i).unwrap_or(&0);
        if c == 0 || c == b'?' || c == b'*' {
            if i > start {
                let mut w = Word { original: pattern[start..i].to_owned(), start: 0, end: i-start, section: 0, pattern: 0, tokens: Vec::new() };
                parse(table, &mut w, Some(system)).map_err(|_| "invalid pattern".to_owned())?;
                result.extend(w.tokens.iter().map(|t| t.id as isize));
            }
            if c == b'?' { result.push(-1); }
            if c == b'*' { result.push(-2); }
            start = i+1;
        } else if !(c.is_ascii_lowercase() || c == b'\'' || c == b'-') { return Err("invalid pattern".to_owned()); }
    }
    Ok(result)
}
fn glob(pattern: &[isize], w: &Word) -> bool {
    let mut dp = vec![false; w.tokens.len()+1];
    dp[0] = true;
    for &p in pattern {
        let mut next = vec![false; dp.len()];
        if p == -2 {
            next[0] = dp[0];
            for j in 1..dp.len() { next[j] = dp[j] || next[j-1]; }
        } else {
            for j in 1..dp.len() { next[j] = dp[j-1] && (p == -1 || p == w.tokens[j-1].id as isize); }
        }
        dp = next;
    }
    dp[w.tokens.len()]
}
fn process(table: &[Mora], line: &str, config: &mut Settings) -> Result<String, String> {
    let names = ["SET", "TABLE", "CONVERT", "NORMALIZE", "REVERSE", "VALID", "DETECT", "DIFF", "SAME", "MORAE", "SYLLABLES", "ROW", "STATS", "SORT", "INDEX", "FIND", "HAIKU", "KAIBUN", "SHIRITORI"];
    let fixed = [2, 2, 2, 0, 1, 1, 0, 2, 2, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1];
    let command = line.split(' ').next().unwrap();
    let cmd = index(&names, command).ok_or_else(|| format!("unknown command {command}"))?;
    let mut args = Vec::new();
    let text;
    if cmd <= 1 {
        let fields: Vec<&str> = line.split(' ').collect();
        if fields.len() < 3 { return Err("missing argument".to_owned()); }
        if fields.len() > 3 { return Err("too many arguments".to_owned()); }
        args.extend_from_slice(&fields[1..]);
        text = "";
    } else {
        let mut rest = line;
        for i in 0..=fixed[cmd] {
            let (field, tail) = rest.split_once(' ').ok_or("missing argument")?;
            if i > 0 { args.push(field); }
            rest = tail;
        }
        text = rest;
    }
    if cmd == 0 {
        let option = index(&["LONG", "CASE", "ORDER"], args[0]).ok_or_else(|| format!("unknown option {}", args[0]))?;
        let values: [&[&str]; 3] = [&["KEEP", "DROP", "PASSPORT", "HYPHEN", "DOUBLE"], &["KEEP", "LOWER", "UPPER", "TITLE"], &["GOJUON", "IROHA"]];
        let value = index(values[option], args[1]).ok_or_else(|| format!("unknown value {}", args[1]))?;
        match option {
            0 => config.long = value,
            1 => config.casing = value,
            _ => config.order = value,
        }
        return Ok(format!("{}={}", args[0], args[1]));
    }
    let system_count = if cmd == 3 || cmd == 6 { 0 } else if [2, 7, 8].contains(&cmd) { 2 } else { 1 };
    let mut sys = Vec::new();
    for arg in &args[..system_count] {
        sys.push(index(&SYSTEMS, arg).ok_or_else(|| format!("unknown system {arg}"))?);
    }
    let source = sys.first().copied();
    if cmd == 1 {
        let row = index(&ROWS, args[1]).ok_or_else(|| format!("unknown row {}", args[1]))?;
        return Ok(table.iter().filter(|m| m.row == row).map(|m| m.spelling[sys[0]].as_str()).collect::<Vec<_>>().join(" "));
    }
    let pattern = if cmd == 15 { pattern_tokens(table, args[1], sys[0])? } else { Vec::new() };
    for (i, c) in text.bytes().enumerate() {
        if !word_char(c) && !c.is_ascii_digit() && !b" .,!?;:()\"".contains(&c) && !([8, 16].contains(&cmd) && c == b'/') {
            return Err(col_error(i+1, "invalid character"));
        }
    }
    let mut words = lex(text);
    let sections = text.bytes().filter(|&c| c == b'/').count()+1;
    let mut counts = vec![0; sections];
    for w in &words { counts[w.section] += 1; }
    if cmd == 8 && (sections != 2 || counts.contains(&0)) { return Err("expected two texts".to_owned()); }
    if cmd == 16 && ((sections != 3 && sections != 5) || counts.contains(&0)) { return Err("expected 3 or 5 lines".to_owned()); }
    if words.is_empty() { return Err("no words".to_owned()); }
    for w in &mut words { check_case(w)?; }
    if cmd == 6 {
        let mut output = Vec::new();
        for (s, name) in SYSTEMS.iter().enumerate() {
            let mut readable = true;
            for w in &mut words {
                if parse(table, w, Some(s)).is_err() {
                    readable = false;
                    break;
                }
            }
            let mut verdict = "error";
            if readable {
                verdict = "canonical";
                for w in &words {
                    if write_word(table, w, s, true, config)? != w.original { verdict = "readable"; }
                }
            }
            output.push(format!("{name}={verdict}"));
        }
        return Ok(output.join(" "));
    }
    for w in &mut words {
        let system = if cmd == 8 && w.section == 1 { Some(sys[1]) } else { source };
        parse(table, w, system)?;
    }
    if [2, 3, 4].contains(&cmd) {
        let mut output = String::new();
        let mut pos = 0;
        for w in &mut words {
            output.push_str(&text[pos..w.start]);
            let target = if cmd == 2 { sys[1] } else if cmd == 3 { 0 } else { sys[0] };
            if cmd == 4 {
                for i in 0..w.tokens.len() {
                    if w.tokens[i].id == L {
                        let previous = &table[w.tokens[i-1].id].id;
                        w.tokens[i].id = mora_id(table, &previous[previous.len()-1..]);
                    }
                }
                w.tokens.reverse();
            }
            output.push_str(&write_word(table, w, target, false, config)?);
            pos = w.end;
        }
        output.push_str(&text[pos..]);
        return Ok(output);
    }
    let source = sys[0];
    if cmd == 5 {
        for w in &words {
            let canonical = write_word(table, w, source, true, config)?;
            if canonical != w.original {
                let i = canonical.bytes().zip(w.original.bytes()).take_while(|(a, b)| a == b).count();
                return Ok(format!("INVALID col {}: expected {canonical}", w.start+i+1));
            }
        }
        return Ok("VALID".to_owned());
    }
    if cmd == 7 || cmd == 15 {
        let mut selected = Vec::new();
        for w in &words {
            if cmd == 7 {
                let a = write_word(table, w, source, false, config)?;
                let b = write_word(table, w, sys[1], false, config)?;
                if a != b { selected.push(format!("{a}>{b}")); }
            } else if glob(&pattern, w) { selected.push(w.original.clone()); }
        }
        let mut result = format!("{} of {}", selected.len(), words.len());
        if !selected.is_empty() { result.push_str(&format!(": {}", selected.join(" "))); }
        return Ok(result);
    }
    if cmd == 8 {
        let (left, right) = words.split_at(counts[0]);
        let mut exact = true;
        for (i, (a, b)) in left.iter().zip(right).enumerate() {
            if sequence(table, a, true) != sequence(table, b, true) { return Ok(format!("DIFFERENT at word {}", i+1)); }
            if sequence(table, a, false) != sequence(table, b, false) { exact = false; }
        }
        if left.len() != right.len() { return Ok(format!("DIFFERENT at word {}", left.len().min(right.len())+1)); }
        return Ok((if exact { "EXACT" } else { "LOOSE" }).to_owned());
    }
    if cmd == 9 || cmd == 10 {
        let mut output = Vec::new();
        let mut total = 0;
        for w in &words {
            let mut pieces: Vec<String> = Vec::new();
            if cmd == 9 {
                for t in &w.tokens {
                    pieces.push(match t.id {
                        N => "N".to_owned(), Q => "Q".to_owned(), L => "-".to_owned(),
                        _ => table[t.id].spelling[source].clone(),
                    });
                }
            } else {
                let canonical = parts(table, w, source, 0)?;
                let paired = pairs(table, w, false);
                for (i, t) in w.tokens.iter().enumerate() {
                    if i > 0 && (t.id >= N || paired[i]) { pieces.last_mut().unwrap().push_str(&canonical[i]); }
                    else { pieces.push(canonical[i].clone()); }
                }
            }
            total += pieces.len();
            output.push(pieces.join("."));
        }
        return Ok(format!("{total}: {}", output.join(" ")));
    }
    if cmd == 11 {
        let mut output = Vec::new();
        for w in &words {
            for t in &w.tokens {
                if t.id < N {
                    let m = &table[t.id];
                    output.push(format!("{}: {} {}", m.spelling[source], ROWS[m.row], m.dan));
                } else { output.push(format!("{}: special", ["N", "Q", "-"][t.id-N])); }
            }
        }
        return Ok(output.join(", "));
    }
    if cmd == 12 {
        let mut row_counts = [0; 10];
        let mut other = [0; 6];
        let mut total = 0;
        for w in &words {
            for t in &w.tokens {
                total += 1;
                if t.id < N {
                    let m = &table[t.id];
                    row_counts[m.base] += 1;
                    if m.voice > 0 { other[m.voice-1] += 1; }
                    if m.dan.len() == 2 { other[2] += 1; }
                } else { other[t.id-N+3] += 1; }
            }
        }
        let mut output = vec![format!("morae={total}")];
        for (r, &c) in row_counts.iter().enumerate() {
            if c > 0 { output.push(format!("{}={c}", ROWS[r])); }
        }
        for (label, c) in ["voiced", "semivoiced", "contracted", "N", "Q", "L"].iter().zip(other) {
            output.push(format!("{label}={c}"));
        }
        return Ok(output.join(" "));
    }
    if cmd == 13 || cmd == 14 {
        words.sort_by_cached_key(|w| key(table, w, config.order));
        let mut output: Vec<String> = Vec::new();
        let mut previous = String::new();
        for w in &words {
            if cmd == 13 {
                output.push(w.original.clone());
                continue;
            }
            let id = elements(table, w)[0].id;
            let heading = if id == N { "N" } else if config.order == 1 { &table[id].id } else { ROWS[table[id].row] };
            if heading == previous { output.last_mut().unwrap().push_str(&format!(" {}", w.original)); }
            else { output.push(format!("{heading}: {}", w.original)); }
            previous = heading.to_owned();
        }
        return Ok(output.join(if cmd == 13 { " " } else { "; " }));
    }
    if cmd == 16 {
        counts.fill(0);
        for w in &words { counts[w.section] += w.tokens.len(); }
        let expected = &[5, 7, 5, 7, 7][..sections];
        let verdict = if counts == expected { "OK" } else { "NG" };
        let kind = if sections == 3 { "haiku" } else { "tanka" };
        let numbers = counts.iter().map(usize::to_string).collect::<Vec<_>>().join("-");
        return Ok(format!("{verdict} {kind} {numbers}"));
    }
    if cmd == 17 {
        let kana: Vec<usize> = words.iter().flat_map(|w| elements(table, w).into_iter().map(|e| e.id)).collect();
        let palindrome = kana.iter().eq(kana.iter().rev());
        let output = kana.iter().map(|&id| if id == N { "N" } else { &table[id].id }).collect::<Vec<_>>().join(".");
        return Ok(format!("{} {output}", if palindrome { "YES" } else { "NO" }));
    }
    let mut previous_tail = N;
    for (i, w) in words.iter().enumerate() {
        let e = elements(table, w);
        let prefix = format!("NG {}: {}", i+1, w.original);
        if i > 0 && e[0].id != previous_tail { return Ok(format!("{prefix} must start with {}", table[previous_tail].spelling[source])); }
        for earlier in &words[..i] {
            if sequence(table, w, false) == sequence(table, earlier, false) { return Ok(format!("{prefix} is repeated")); }
        }
        previous_tail = e.last().unwrap().id;
        if previous_tail == N { return Ok(format!("{prefix} ends with N")); }
    }
    Ok(format!("OK {}", words.len()))
}
fn main() {
    let table = initialize();
    let stdin = io::stdin();
    let mut lines = stdin.lock().lines();
    let count: usize = lines.next().unwrap().unwrap().trim().parse().unwrap();
    let mut config = Settings::default();
    let stdout = io::stdout();
    let mut output = io::BufWriter::new(stdout.lock());
    for line in lines.take(count) {
        let line = line.unwrap();
        let result = process(&table, line.trim_end_matches('\r'), &mut config).unwrap_or_else(|message| format!("ERROR {message}"));
        writeln!(output, "{result}").unwrap();
    }
}
