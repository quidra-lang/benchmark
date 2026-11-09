use std::collections::BTreeMap;
use crate::{Diagnostic, Origin};
use crate::lexer::logical_lines;

pub fn is_name(text: &str) -> bool {
    let bytes = text.as_bytes();
    !bytes.is_empty() && bytes[0].is_ascii_lowercase()
        && bytes[1..].iter().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || *c == b'_')
}

pub fn is_section(text: &str) -> bool { text.split('.').all(is_name) }

#[derive(Clone, Copy)]
pub enum StatementKind { Assign, Append, Unset, Inherit, Include }

#[derive(Clone)]
pub struct Statement {
    pub kind: StatementKind,
    pub line: usize,
    pub target: String,
    pub value: String,
}

#[derive(Clone)]
pub struct Document { pub statements: Vec<Statement>, pub diagnostics: Vec<Diagnostic> }

fn trim(segments: &mut [String]) {
    segments[0] = segments[0].trim_start_matches(' ').into();
    let last = segments.len() - 1;
    segments[last] = segments[last].trim_end_matches(' ').into();
}

pub fn parse_document(name: &str, source: &str) -> Document {
    let mut document = Document { statements: Vec::new(), diagnostics: Vec::new() };
    let mut diagnostics = Vec::new();
    let mut section: Option<String> = None;
    let mut base: Option<String> = None;
    let mut assigned = BTreeMap::new();
    for line in logical_lines(source) {
        let origin = Origin::new(name, line.number);
        let mut report = |code, message: String| diagnostics.push(Diagnostic { origin: origin.clone(), code, message });
        if let Some((code, message)) = line.error { report(code, message); continue; }
        let mut segments = line.segments;
        trim(&mut segments);
        let first = &segments[0];
        if segments.len() == 1 && first.is_empty() { continue; }
        if first.starts_with('[') {
            let header = if segments.len() == 1 && first.ends_with(']') {
                let inside = &first[1..first.len() - 1];
                let (child, parent) = match inside.split_once(':') {
                    Some((child, parent)) => (child.trim_matches(' '), Some(parent.trim_matches(' '))),
                    None => (inside.trim_matches(' '), None),
                };
                let relative = child.starts_with('.') && is_section(&child[1..]);
                if (!relative && !is_section(child)) || parent.is_some_and(|p| !is_section(p)) {
                    Err("invalid section header")
                } else if relative && base.is_none() {
                    Err("relative section without base")
                } else {
                    Ok((if relative { format!("{}{child}", base.as_ref().unwrap()) } else { child.into() }, relative, parent))
                }
            } else { Err("invalid section header") };
            match header {
                Err(message) => { report("E_SECTION", message.into()); section = None; }
                Ok((child, relative, parent)) => {
                    if !relative { base = Some(child.clone()); }
                    section = Some(child.clone());
                    if let Some(parent) = parent {
                        document.statements.push(Statement { kind: StatementKind::Inherit, line: line.number, target: child, value: parent.into() });
                    }
                }
            }
        } else if first.starts_with('@') {
            let words: Vec<&str> = first.split(' ').filter(|s| !s.is_empty()).collect();
            if segments.len() != 1 || words.len() != 2 || !["@include", "@unset"].contains(&words[0]) || !is_name(words[1]) {
                report("E_SYNTAX", "invalid directive".into());
            } else if words[0] == "@include" {
                document.statements.push(Statement { kind: StatementKind::Include, line: line.number, target: words[1].into(), value: String::new() });
            } else if let Some(section) = &section {
                document.statements.push(Statement { kind: StatementKind::Unset, line: line.number, target: format!("{section}.{}", words[1]), value: String::new() });
            } else { report("E_NO_SECTION", "no current section".into()); }
        } else {
            if !segments.iter().step_by(2).any(|s| s.contains('=')) { report("E_SYNTAX", "invalid line".into()); continue; }
            let Some((key, rest)) = first.split_once('=') else { report("E_SYNTAX", "invalid key".into()); continue; };
            let mut key = key.trim_matches(' ');
            let append = key.ends_with('+');
            if append { key = key[..key.len() - 1].trim_end_matches(' '); }
            if !is_name(key) { report("E_SYNTAX", "invalid key".into()); continue; }
            let mut value_segments = vec![rest.to_owned()];
            value_segments.extend_from_slice(&segments[1..]);
            trim(&mut value_segments);
            let value = match value_segments.as_slice() {
                [value] => value.clone(),
                [before, value, after] if before.is_empty() && after.is_empty() => value.clone(),
                _ => { report("E_SYNTAX", "invalid value".into()); continue; }
            };
            let Some(section) = &section else { report("E_NO_SECTION", "no current section".into()); continue; };
            let target = format!("{section}.{key}");
            if !append {
                if let Some(previous) = assigned.insert(target.clone(), line.number) {
                    report("W_DUPLICATE", format!("{target} already set at line {previous}"));
                }
            }
            document.statements.push(Statement { kind: if append { StatementKind::Append } else { StatementKind::Assign }, line: line.number, target, value });
        }
    }
    document.diagnostics = diagnostics;
    document
}
