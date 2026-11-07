mod arith_coder;
mod bitio;
mod huffman;
mod lz77;
mod lzw;

use bitio::{bits, DecodeError, Reader, Writer};
use lz77::Token;
use std::collections::BTreeSet;
use std::fs;

const METHODS: [&str; 5] = ["STORE", "LZW", "LZ77", "LZH", "ARITH"];

fn ratio(compressed: usize, original: usize) -> String { if original == 0 { "-".into() } else { (1000 * compressed / original).to_string() } }
fn method_name(method: usize) -> String { if method < 5 { METHODS[method].into() } else { format!("#{method}") } }

fn adler(bytes: &[u8]) -> i64 {
    let (mut a, mut b) = (1_i64, 0_i64);
    for &byte in bytes { a = (a + i64::from(byte)) % 65521; b = (b + a) % 65521; }
    b * 65536 + a
}

fn fixed_lengths(symbols: usize) -> Vec<usize> {
    let k = bits(symbols - 1);
    let short = (1 << k) - symbols;
    (0..symbols).map(|s| if s < short { k - 1 } else { k }).collect()
}

fn write_table(writer: &mut Writer, lengths: &[usize]) {
    let mut i = 0;
    while i < lengths.len() {
        if lengths[i] > 0 { writer.write(lengths[i], 4); i += 1; }
        else {
            let run = lengths[i..].iter().take_while(|&&length| length == 0).count().min(256);
            writer.write(0, 4);
            writer.write(run - 1, 8);
            i += run;
        }
    }
}

fn read_table(reader: &mut Reader<'_>, symbols: usize) -> Result<Vec<usize>, DecodeError> {
    let mut lengths = Vec::new();
    while lengths.len() < symbols {
        let value = reader.read(4, 0)?;
        if value > 0 { lengths.push(value); }
        else {
            let run = reader.read(8, 0)? + 1;
            if lengths.len() + run > symbols { return Err(DecodeError::new("bad_table", 0)); }
            lengths.resize(lengths.len() + run, 0);
        }
    }
    let used: Vec<_> = lengths.iter().copied().filter(|&length| length > 0).collect();
    if (used.len() == 1 && used[0] != 1) || (used.len() >= 2 && used.iter().map(|&length| 1_usize << (15 - length)).sum::<usize>() != 32768) {
        return Err(DecodeError::new("bad_table", 0));
    }
    Ok(lengths)
}

fn read_symbol(reader: &mut Reader<'_>, codes: &[(usize, usize)], position: usize) -> Result<usize, DecodeError> {
    if codes.iter().all(|&(_, width)| width == 0) { return Err(DecodeError::new("bad_code", position)); }
    let mut value = 0;
    for width in 1..=15 {
        value = value * 2 + reader.read(1, position)?;
        if let Some(symbol) = codes.iter().position(|&(code, length)| length == width && code == value) { return Ok(symbol); }
        if width == 1 && codes.iter().filter(|&&(_, width)| width > 0).count() == 1 { return Err(DecodeError::new("bad_code", position)); }
    }
    Err(DecodeError::new("bad_code", position))
}

fn token_bits(tokens: &[Token], literal_codes: &[(usize, usize)], distance_codes: &[(usize, usize)]) -> Writer {
    let mut writer = Writer::default();
    for token in tokens {
        match *token {
            Token::Literal(byte) => { let (code, width) = literal_codes[byte as usize]; writer.write(code, width); }
            Token::Match(distance, length) => {
                let (code, width) = literal_codes[256 + length - 3];
                writer.write(code, width);
                let u = distance - 1;
                let slot = bits(u);
                let (code, width) = distance_codes[slot];
                writer.write(code, width);
                if slot >= 2 { writer.write(u - (1 << (slot - 1)), slot - 1); }
            }
        }
    }
    writer
}

struct LzhStatistics {
    dynamic: bool,
    fixed_bits: usize,
    table_bits: usize,
    code_bits: usize,
    halvings: usize,
    literal_used: usize,
    literal_max: usize,
    distance_used: usize,
    distance_max: usize,
    slots: Vec<usize>,
}

fn lzh_encode(tokens: &[Token], b: usize, k: usize, maximum: usize) -> (Vec<u8>, LzhStatistics) {
    let mut literal_frequencies = vec![0; 256 + (1 << k)];
    let mut distance_frequencies = vec![0; b + 1];
    for token in tokens {
        match *token {
            Token::Literal(byte) => literal_frequencies[byte as usize] += 1,
            Token::Match(distance, length) => { literal_frequencies[256 + length - 3] += 1; distance_frequencies[bits(distance - 1)] += 1; }
        }
    }
    let (literal_lengths, literal_halvings) = huffman::limited(&literal_frequencies, maximum);
    let (distance_lengths, distance_halvings) = huffman::limited(&distance_frequencies, maximum);
    let fixed = token_bits(tokens, &huffman::canonical(&fixed_lengths(literal_frequencies.len())), &huffman::canonical(&fixed_lengths(b + 1)));
    let dynamic = token_bits(tokens, &huffman::canonical(&literal_lengths), &huffman::canonical(&distance_lengths));
    let mut tables = Writer::default();
    write_table(&mut tables, &literal_lengths);
    write_table(&mut tables, &distance_lengths);
    let use_dynamic = fixed.bits.len() > tables.bits.len() + dynamic.bits.len();
    let mut payload = Writer::default();
    payload.write(usize::from(use_dynamic), 1);
    if use_dynamic { payload.append(&tables); payload.append(&dynamic); } else { payload.append(&fixed); }
    let statistics = LzhStatistics {
        dynamic: use_dynamic, fixed_bits: fixed.bits.len(), table_bits: tables.bits.len(), code_bits: dynamic.bits.len(), halvings: literal_halvings + distance_halvings,
        literal_used: literal_lengths.iter().filter(|&&length| length > 0).count(), literal_max: *literal_lengths.iter().max().unwrap(),
        distance_used: distance_lengths.iter().filter(|&&length| length > 0).count(), distance_max: *distance_lengths.iter().max().unwrap(), slots: distance_frequencies,
    };
    (payload.bytes(), statistics)
}

fn lz77_encode(tokens: &[Token], b: usize, k: usize) -> Vec<u8> {
    let mut writer = Writer::default();
    for token in tokens {
        match *token {
            Token::Literal(byte) => { writer.write(0, 1); writer.write(byte as usize, 8); }
            Token::Match(distance, length) => { writer.write(1, 1); writer.write(distance - 1, b); writer.write(length - 3, k); }
        }
    }
    writer.bytes()
}

fn lz77_decode(payload: &[u8], original: usize, b: usize, k: usize) -> Result<Vec<u8>, DecodeError> {
    let mut reader = Reader::new(payload);
    let mut output = Vec::new();
    while output.len() < original {
        if reader.read(1, output.len())? == 0 { output.push(reader.read(8, output.len())? as u8); }
        else {
            let distance = reader.read(b, output.len())? + 1;
            let length = reader.read(k, output.len())? + 3;
            lz77::copy(&mut output, distance, length, original)?;
        }
    }
    Ok(output)
}

fn lzh_decode(payload: &[u8], original: usize, b: usize, k: usize) -> Result<Vec<u8>, DecodeError> {
    let mut reader = Reader::new(payload);
    let (literal_lengths, distance_lengths) = if reader.read(1, 0)? == 1 {
        (read_table(&mut reader, 256 + (1 << k))?, read_table(&mut reader, b + 1)?)
    } else { (fixed_lengths(256 + (1 << k)), fixed_lengths(b + 1)) };
    let literal_codes = huffman::canonical(&literal_lengths);
    let distance_codes = huffman::canonical(&distance_lengths);
    let mut output = Vec::new();
    while output.len() < original {
        let symbol = read_symbol(&mut reader, &literal_codes, output.len())?;
        if symbol < 256 { output.push(symbol as u8); }
        else {
            let length = symbol - 253;
            let slot = read_symbol(&mut reader, &distance_codes, output.len())?;
            let u = if slot >= 2 { (1 << (slot - 1)) + reader.read(slot - 1, output.len())? } else { slot };
            lz77::copy(&mut output, u + 1, length, original)?;
        }
    }
    Ok(output)
}

fn decode(method: usize, payload: &[u8], original: usize, b: usize, k: usize) -> Result<Vec<u8>, DecodeError> {
    match method {
        0 => if payload.len() < original { Err(DecodeError::new("end_of_data", payload.len())) } else { Ok(payload[..original].to_vec()) },
        1 => lzw::decode(payload, original), 2 => lz77_decode(payload, original, b, k),
        3 => lzh_decode(payload, original, b, k), 4 => arith_coder::decode(payload, original),
        _ => unreachable!(),
    }
}

struct Compressed {
    payloads: Vec<Vec<u8>>,
    best: usize,
    analysis: Vec<String>,
}

fn compress(name: &str, data: &[u8], b: usize, k: usize, maximum: usize) -> Compressed {
    let tokens = lz77::tokenize(data, b, k);
    let (lzw, lzw_stats) = lzw::encode(data);
    let lz77 = lz77_encode(&tokens, b, k);
    let (lzh, stats) = lzh_encode(&tokens, b, k, maximum);
    let (arith, arith_bits, contexts, rescales) = arith_coder::encode(data);
    let payloads = vec![data.to_vec(), lzw, lz77, lzh, arith];
    let best = (0..5).min_by_key(|&method| (payloads[method].len(), method)).unwrap();
    let matches: Vec<_> = tokens.iter().filter_map(|token| if let Token::Match(distance, length) = token { Some((*distance, *length)) } else { None }).collect();
    let analysis = vec![
        format!("lzw {name} codes {} clears {} widths {} {} {} {} longest {}", lzw_stats.codes, lzw_stats.clears, lzw_stats.widths[0], lzw_stats.widths[1], lzw_stats.widths[2], lzw_stats.widths[3], lzw_stats.longest),
        format!("lz77 {name} tokens {} literals {} matches {} matched {} longest {} farthest {}", tokens.len(), tokens.len() - matches.len(), matches.len(), matches.iter().map(|m| m.1).sum::<usize>(), matches.iter().map(|m| m.1).max().unwrap_or(0), matches.iter().map(|m| m.0).max().unwrap_or(0)),
        format!("lzh {name} mode {} fixed_bits {} table_bits {} code_bits {} halvings {} litlen_used {} litlen_max {} offset_used {} offset_max {}", if stats.dynamic { "dynamic" } else { "fixed" }, stats.fixed_bits, stats.table_bits, stats.code_bits, stats.halvings, stats.literal_used, stats.literal_max, stats.distance_used, stats.distance_max),
        format!("slots {name} {}", stats.slots.iter().map(usize::to_string).collect::<Vec<_>>().join(" ")),
        format!("arith {name} bits {arith_bits} contexts {contexts} rescales {rescales}"),
    ];
    Compressed { payloads, best, analysis }
}

struct ArchiveItem {
    name: String,
    method: usize,
    data: Vec<u8>,
    payload: Vec<u8>,
}

fn archive(items: &[ArchiveItem], b: usize, k: usize) -> Vec<u8> {
    let mut bytes = b"TXAR".to_vec();
    bytes.extend([b as u8, k as u8]);
    bytes.extend_from_slice(&(items.len() as u16).to_be_bytes());
    for item in items {
        let mut header = vec![item.name.len() as u8];
        header.extend_from_slice(item.name.as_bytes());
        header.push(item.method as u8);
        header.extend_from_slice(&(item.data.len() as u32).to_be_bytes());
        header.extend_from_slice(&(item.payload.len() as u32).to_be_bytes());
        header.extend_from_slice(&(adler(&item.data) as u32).to_be_bytes());
        let check = header.iter().fold(0_usize, |sum, &byte| sum + usize::from(byte)) % 256;
        header.push(check as u8);
        bytes.extend(header);
        bytes.extend_from_slice(&item.payload);
    }
    bytes
}

fn integer(bytes: &[u8], start: usize, length: usize) -> usize { bytes[start..start + length].iter().fold(0, |value, &byte| value * 256 + usize::from(byte)) }

fn power(mut base: i64, mut exponent: i64) -> i64 {
    let mut value = 1;
    while exponent > 0 {
        if exponent % 2 == 1 { value = value * base % 65521; }
        base = base * base % 65521;
        exponent /= 2;
    }
    value
}

fn repair(data: &mut [u8], stored: i64, computed: i64) -> Option<(usize, u8, u8)> {
    let delta_a = (stored % 65536 - computed % 65536).rem_euclid(65521);
    let delta_b = (stored / 65536 - computed / 65536).rem_euclid(65521);
    let delta = if (1..=255).contains(&delta_a) { delta_a } else if (65266..=65520).contains(&delta_a) { delta_a - 65521 } else { return None; };
    let inverse = power(delta.rem_euclid(65521), 65519);
    let t = delta_b * inverse % 65521;
    if t < 1 || t > data.len() as i64 { return None; }
    let position = data.len() - t as usize;
    let old = data[position];
    let new = i64::from(old) + delta;
    if !(0..=255).contains(&new) { return None; }
    data[position] = new as u8;
    if adler(data) == stored { Some((position, old, new as u8)) }
    else { data[position] = old; None }
}

struct Header {
    name: String,
    method: usize,
    original: usize,
    compressed: usize,
    adler: i64,
}

struct Entry {
    position: usize,
    header: Option<Header>,
    valid: bool,
    status: &'static str,
    details: String,
    data: Option<Vec<u8>>,
}

struct Parsed {
    error: Option<&'static str>,
    b: usize,
    k: usize,
    declared: usize,
    entries: Vec<Entry>,
    complete: bool,
    trailing: usize,
}

fn parse(bytes: &[u8]) -> Parsed {
    let mut parsed = Parsed { error: None, b: 0, k: 0, declared: 0, entries: Vec::new(), complete: true, trailing: 0 };
    if bytes.len() < 8 || &bytes[..4] != b"TXAR" { parsed.error = Some("bad_magic"); return parsed; }
    parsed.b = usize::from(bytes[4]);
    parsed.k = usize::from(bytes[5]);
    if !(6..=12).contains(&parsed.b) || !(2..=5).contains(&parsed.k) { parsed.error = Some("bad_params"); return parsed; }
    parsed.declared = integer(bytes, 6, 2);
    let mut position = 8;
    for _ in 0..parsed.declared {
        if position >= bytes.len() || position + 15 + usize::from(bytes[position]) > bytes.len() {
            parsed.entries.push(Entry { position, header: None, valid: false, status: "truncated", details: " header".into(), data: None });
            parsed.complete = false;
            break;
        }
        let name_length = usize::from(bytes[position]);
        let name_bytes = &bytes[position + 1..position + 1 + name_length];
        let base = position + 1 + name_length;
        let header = Header { name: String::from_utf8_lossy(name_bytes).into(), method: usize::from(bytes[base]), original: integer(bytes, base + 1, 4), compressed: integer(bytes, base + 5, 4), adler: integer(bytes, base + 9, 4) as i64 };
        let start = position + 15 + name_length;
        let next = start + header.compressed;
        let check = bytes[position..start - 1].iter().map(|&byte| usize::from(byte)).sum::<usize>() % 256;
        let valid_name = (1..=32).contains(&name_length) && name_bytes.iter().all(|&byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || b"._-".contains(&byte));
        let mut entry = Entry { position, header: Some(header), valid: false, status: "bad_header", details: String::new(), data: None };
        if check != usize::from(bytes[start - 1]) || !valid_name {
            parsed.entries.push(entry);
            position = next;
            if position > bytes.len() { parsed.complete = false; break; }
            continue;
        }
        entry.valid = true;
        if next > bytes.len() {
            entry.status = "truncated";
            entry.details = format!(" payload have {} need {}", bytes.len() - start, entry.header.as_ref().unwrap().compressed);
            parsed.entries.push(entry);
            parsed.complete = false;
            break;
        }
        let header = entry.header.as_ref().unwrap();
        if header.method >= 5 { entry.status = "unsupported"; }
        else {
            match decode(header.method, &bytes[start..next], header.original, parsed.b, parsed.k) {
                Err(error) => { entry.status = "error"; entry.details = format!(" {} at {}", error.kind, error.position); }
                Ok(mut data) => {
                    let computed = adler(&data);
                    if computed == header.adler { entry.status = "ok"; }
                    else if let Some((p, old, new)) = repair(&mut data, header.adler, computed) {
                        entry.status = "repaired";
                        entry.details = format!(" byte {p} from {old} to {new}");
                    } else {
                        entry.status = "checksum";
                        entry.details = format!(" stored {:08x} computed {computed:08x}", header.adler);
                    }
                    entry.data = Some(data);
                }
            }
        }
        parsed.entries.push(entry);
        position = next;
    }
    if parsed.complete { parsed.trailing = bytes.len() - position; }
    parsed
}

fn intact(entry: &Entry) -> bool { entry.status == "ok" || entry.status == "repaired" }

fn verify(parsed: &Parsed, items: &[ArchiveItem]) -> usize {
    parsed.entries.iter().zip(items).filter(|(entry, item)| entry.status == "ok" && entry.data.as_ref().is_some_and(|data| data == &item.data)).count()
}

fn listing(parsed: &Parsed, length: usize) -> Vec<String> {
    if let Some(error) = parsed.error { return vec![format!("archive bytes {length} error {error}")]; }
    let mut lines = vec![format!("archive bytes {} offset_bits {} length_bits {} entries {}", length, parsed.b, parsed.k, parsed.declared)];
    let mut methods = [[0; 3]; 5];
    let mut listed = 0;
    for (i, entry) in parsed.entries.iter().enumerate() {
        let mut line = format!("entry {} offset {}", i + 1, entry.position);
        if entry.valid {
            let header = entry.header.as_ref().unwrap();
            line.push_str(&format!(" method {} original {} compressed {} ratio {} adler {:08x} name {}", method_name(header.method), header.original, header.compressed, ratio(header.compressed, header.original), header.adler, header.name));
            listed += 1;
            if header.method < 5 {
                methods[header.method][0] += 1;
                methods[header.method][1] += header.original;
                methods[header.method][2] += header.compressed;
            }
        } else if entry.status == "bad_header" { line.push_str(" bad_header"); }
        else { line.push_str(" truncated header"); }
        lines.push(line);
    }
    for method in 0..5 { lines.push(format!("method {} entries {} original {} compressed {} ratio {}", METHODS[method], methods[method][0], methods[method][1], methods[method][2], ratio(methods[method][2], methods[method][1]))); }
    lines.push(format!("end listed {} of {} stop {} trailing {}", listed, parsed.declared, if parsed.complete { "complete" } else { "truncated" }, parsed.trailing));
    lines
}

fn test_report(parsed: &Parsed) -> Vec<String> {
    if let Some(error) = parsed.error { return vec![format!("archive error {error}")]; }
    let mut lines = Vec::new();
    for (i, entry) in parsed.entries.iter().enumerate() {
        let mut line = format!("entry {} offset {}", i + 1, entry.position);
        if entry.valid {
            let header = entry.header.as_ref().unwrap();
            line.push_str(&format!(" name {} method {} status {}{}", header.name, method_name(header.method), entry.status, entry.details));
        } else if entry.status == "bad_header" { line.push_str(" status bad_header"); }
        else { line.push_str(" status truncated header"); }
        lines.push(line);
    }
    let count = |status| parsed.entries.iter().filter(|entry| entry.status == status).count();
    lines.push(format!("summary entries {} checked {} ok {} repaired {} checksum {} error {} unsupported {} truncated {} bad_header {} missing {} trailing {}", parsed.declared, parsed.entries.len(), count("ok"), count("repaired"), count("checksum"), count("error"), count("unsupported"), count("truncated"), count("bad_header"), parsed.declared - parsed.entries.len(), parsed.trailing));
    lines
}

fn text_lines(data: &[u8]) -> Vec<String> {
    if data.is_empty() { return Vec::new(); }
    let text = String::from_utf8(data.to_vec()).unwrap();
    let mut lines: Vec<_> = text.split('\n').map(String::from).collect();
    lines.pop();
    lines
}

fn compare(name: &str, old: &[String], new: &[String]) -> Vec<String> {
    if old == new { return vec![format!("same {name} lines {}", old.len())]; }
    let first = old.iter().zip(new).position(|(old, new)| old != new).unwrap_or(old.len().min(new.len())) + 1;
    let (a, b) = (old.len(), new.len());
    let mut lcs = vec![vec![0_u16; b + 1]; a + 1];
    for i in (0..a).rev() {
        for j in (0..b).rev() { lcs[i][j] = if old[i] == new[j] { lcs[i + 1][j + 1] + 1 } else { lcs[i + 1][j].max(lcs[i][j + 1]) }; }
    }
    let (mut i, mut j, mut removed, mut added) = (0, 0, 0, 0);
    let mut edits = Vec::new();
    while i < a || j < b {
        if i < a && j < b && old[i] == new[j] { i += 1; j += 1; }
        else if j == b || (i < a && lcs[i + 1][j] >= lcs[i][j + 1]) { edits.push(format!("-{}:{}", i + 1, old[i])); removed += 1; i += 1; }
        else { edits.push(format!("+{}:{}", j + 1, new[j])); added += 1; j += 1; }
    }
    let mut lines = vec![format!("differs {name} first_line {first} archive_lines {a} manifest_lines {b} removed {removed} added {added}")];
    lines.extend(edits);
    lines
}

fn hex_lines(bytes: &[u8]) -> Vec<String> { bytes.chunks(32).map(|chunk| chunk.iter().map(|byte| format!("{byte:02x}")).collect()).collect() }
fn write(name: &str, lines: &[String]) { fs::write(format!("output/{name}"), if lines.is_empty() { String::new() } else { format!("{}\n", lines.join("\n")) }).unwrap(); }

fn main() {
    let manifest = fs::read_to_string("input/manifest.txt").unwrap();
    let lines: Vec<_> = manifest.lines().collect();
    let number = |i: usize| lines[i].split(' ').nth(1).unwrap().parse::<usize>().unwrap();
    let (b, k, maximum) = (number(0), number(1), number(2));
    let names: Vec<_> = lines[3..].iter().map(|line| line[5..].to_string()).collect();
    let file_data: Vec<_> = names.iter().map(|name| fs::read(format!("input/files/{name}")).unwrap()).collect();
    let mut sizes = vec![format!("params offset_bits {} length_bits {} window {} lookahead {} max_code_length {}", b, k, 1_usize << b, (1_usize << k) + 2, maximum)];
    let mut analysis = Vec::new();
    let mut items = Vec::new();
    let mut totals = [0; 5];
    let mut chosen = [0; 5];
    let mut total_best = 0;
    let original: usize = file_data.iter().map(Vec::len).sum();
    for (name, data) in names.iter().zip(&file_data) {
        let compressed = compress(name, data, b, k, maximum);
        let mut line = format!("file {name} original {}", data.len());
        for method in 0..5 {
            let length = compressed.payloads[method].len();
            totals[method] += length;
            line.push_str(&format!(" {} {} {}", METHODS[method], length, ratio(length, data.len())));
        }
        line.push_str(&format!(" best {}", METHODS[compressed.best]));
        sizes.push(line);
        analysis.extend(compressed.analysis);
        chosen[compressed.best] += 1;
        total_best += compressed.payloads[compressed.best].len();
        items.push(ArchiveItem { name: name.clone(), method: compressed.best, data: data.clone(), payload: compressed.payloads[compressed.best].clone() });
    }
    let created = archive(&items, b, k);
    let verification = parse(&created);
    let mut total = format!("total original {original}");
    let mut chosen_line = String::from("chosen");
    for method in 0..5 { total.push_str(&format!(" {} {} {}", METHODS[method], totals[method], ratio(totals[method], original))); chosen_line.push_str(&format!(" {} {}", METHODS[method], chosen[method])); }
    total.push_str(&format!(" best {} {}", total_best, ratio(total_best, original)));
    sizes.extend([total, chosen_line, format!("archive bytes {} entries {} ratio {}", created.len(), items.len(), ratio(created.len(), original)), format!("verify entries {} ok {}", verification.entries.len(), verify(&verification, &items))]);
    let hex: String = fs::read_to_string("input/archive.hex").unwrap().lines().collect();
    let given: Vec<_> = (0..hex.len()).step_by(2).map(|i| u8::from_str_radix(&hex[i..i + 2], 16).unwrap()).collect();
    let parsed = parse(&given);
    let mut test = test_report(&parsed);
    let mut extracted = Vec::new();
    let mut comparisons = Vec::new();
    let mut salvage_items = Vec::new();
    let mut intact_names = BTreeSet::new();
    let (salvage_b, salvage_k) = if parsed.error.is_some() { (b, k) } else { (parsed.b, parsed.k) };
    for entry in parsed.entries.iter().filter(|entry| intact(entry)) {
        let header = entry.header.as_ref().unwrap();
        let data = entry.data.as_ref().unwrap();
        let lines = text_lines(data);
        let words = lines.iter().map(|line| line.split(' ').filter(|word| !word.is_empty()).count()).sum::<usize>();
        extracted.push(format!("file {} bytes {} lines {} words {} longest {}", header.name, data.len(), lines.len(), words, lines.iter().map(String::len).max().unwrap_or(0)));
        extracted.extend(lines.clone());
        intact_names.insert(header.name.clone());
        if let Some(index) = names.iter().position(|name| name == &header.name) { comparisons.extend(compare(&header.name, &lines, &text_lines(&file_data[index]))); }
        else { comparisons.push(format!("archive_only {}", header.name)); }
        let compressed = compress(&header.name, data, salvage_b, salvage_k, maximum);
        let payload = compressed.payloads[compressed.best].clone();
        test.push(format!("salvage {} method {} compressed {} was {} {}", header.name, METHODS[compressed.best], payload.len(), method_name(header.method), header.compressed));
        salvage_items.push(ArchiveItem { name: header.name.clone(), method: compressed.best, data: data.clone(), payload });
    }
    for name in names.iter().filter(|name| !intact_names.contains(*name)) { comparisons.push(format!("new {name}")); }
    let salvaged = archive(&salvage_items, salvage_b, salvage_k);
    let verification = parse(&salvaged);
    test.push(format!("salvaged entries {} bytes {} original {} verified {}", salvage_items.len(), salvaged.len(), salvage_items.iter().map(|item| item.data.len()).sum::<usize>(), verify(&verification, &salvage_items)));
    fs::create_dir_all("output").unwrap();
    write("sizes.txt", &sizes);
    write("analysis.txt", &analysis);
    write("archive.hex", &hex_lines(&created));
    write("listing.txt", &listing(&parsed, given.len()));
    write("test_report.txt", &test);
    write("extracted.txt", &extracted);
    write("compare.txt", &comparisons);
    write("salvaged.hex", &hex_lines(&salvaged));
}
