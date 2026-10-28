use crate::bitio::{bits, DecodeError, Reader, Writer};
use std::collections::BTreeMap;

pub struct Statistics {
    pub codes: usize,
    pub clears: usize,
    pub widths: [usize; 4],
    pub longest: usize,
}

fn dictionary() -> BTreeMap<Vec<u8>, usize> { (0..256).map(|byte| (vec![byte as u8], byte)).collect() }

fn emit(writer: &mut Writer, code: usize, counter: &mut usize, statistics: &mut Statistics) {
    let width = bits(258 + *counter).min(12);
    writer.write(code, width);
    statistics.codes += 1;
    statistics.widths[width - 9] += 1;
    if code == 256 { *counter = 0; statistics.clears += 1; } else { *counter += 1; }
}

pub fn encode(data: &[u8]) -> (Vec<u8>, Statistics) {
    let mut writer = Writer::default();
    let mut statistics = Statistics { codes: 0, clears: 0, widths: [0; 4], longest: 0 };
    let mut dictionary = dictionary();
    let (mut next, mut counter) = (258, 0);
    emit(&mut writer, 256, &mut counter, &mut statistics);
    let mut w = Vec::new();
    for &byte in data {
        let mut candidate = w.clone();
        candidate.push(byte);
        if dictionary.contains_key(&candidate) { w = candidate; }
        else {
            statistics.longest = statistics.longest.max(w.len());
            emit(&mut writer, dictionary[&w], &mut counter, &mut statistics);
            dictionary.insert(candidate, next);
            next += 1;
            if next == 4096 {
                emit(&mut writer, 256, &mut counter, &mut statistics);
                dictionary = self::dictionary();
                next = 258;
            }
            w = vec![byte];
        }
    }
    if !w.is_empty() {
        statistics.longest = statistics.longest.max(w.len());
        emit(&mut writer, dictionary[&w], &mut counter, &mut statistics);
    }
    emit(&mut writer, 257, &mut counter, &mut statistics);
    (writer.bytes(), statistics)
}

pub fn decode(payload: &[u8], original: usize) -> Result<Vec<u8>, DecodeError> {
    let mut reader = Reader::new(payload);
    let mut dictionary = vec![Vec::new(); 4096];
    for (code, entry) in dictionary.iter_mut().enumerate().take(256) { entry.push(code as u8); }
    let (mut next, mut counter) = (258, 0);
    let mut previous: Option<usize> = None;
    let mut output = Vec::new();
    loop {
        let c = counter;
        let code = reader.read(bits(258 + c).min(12), output.len())?;
        if code == 256 { next = 258; previous = None; counter = 0; continue; }
        counter += 1;
        if code == 257 {
            if output.len() < original { return Err(DecodeError::new("early_end", output.len())); }
            return Ok(output);
        }
        if c == 3838 { return Err(DecodeError::new("bad_code", output.len())); }
        let entry = if let Some(previous) = previous {
            if code < next { dictionary[code].clone() }
            else if code == next { let mut entry = dictionary[previous].clone(); entry.push(entry[0]); entry }
            else { return Err(DecodeError::new("bad_code", output.len())); }
        } else {
            if code >= 256 { return Err(DecodeError::new("bad_code", output.len())); }
            vec![code as u8]
        };
        if output.len() + entry.len() > original { return Err(DecodeError::new("overrun", output.len())); }
        output.extend_from_slice(&entry);
        if let Some(previous) = previous {
            let mut registration = dictionary[previous].clone();
            registration.push(entry[0]);
            dictionary[next] = registration;
            next += 1;
        }
        previous = Some(code);
    }
}
