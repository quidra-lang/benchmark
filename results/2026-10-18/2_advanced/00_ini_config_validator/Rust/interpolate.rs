use std::collections::{BTreeMap, BTreeSet};
use crate::{Definition, Diagnostic, key_parts, ordered_keys};
use crate::ini_parser::is_section;
use crate::lexer::LITERAL_DOLLAR;

pub struct Expansion { pub results: BTreeMap<String, Option<String>>, pub diagnostics: Vec<Diagnostic> }

struct Expander<'a> {
    definitions: &'a BTreeMap<String, Definition>,
    expansion: Expansion,
    active: Vec<String>,
    cycle_keys: BTreeSet<String>,
}

impl Expander<'_> {
    fn report(&mut self, key: &str, code: &'static str, message: String) {
        self.expansion.diagnostics.push(Diagnostic { origin: self.definitions[key].origin.clone(), code, message });
    }
    fn expand(&mut self, key: &str) -> Option<String> {
        if let Some(result) = self.expansion.results.get(key) { return result.clone(); }
        self.active.push(key.into());
        let result = self.evaluate(key);
        self.active.pop();
        self.expansion.results.insert(key.into(), result.clone());
        result
    }
    fn evaluate(&mut self, key: &str) -> Option<String> {
        let value = self.definitions[key].value.clone();
        let bytes = value.as_bytes();
        let mut result = String::new();
        let mut position = 0;
        while position < bytes.len() {
            if bytes[position] != b'$' || bytes.get(position + 1) != Some(&b'{') {
                result.push(if bytes[position] == LITERAL_DOLLAR { '$' } else { bytes[position] as char });
                position += 1;
                continue;
            }
            let close = value[position + 2..].find('}').map(|p| p + position + 2);
            let Some(close) = close.filter(|&p| is_section(&value[position + 2..p])) else {
                self.report(key, "E_BAD_REF", format!("{key}: invalid reference")); return None;
            };
            let reference = &value[position + 2..close];
            let target = if reference.contains('.') { reference.into() } else { format!("{}.{reference}", key_parts(key).0) };
            if !self.definitions.contains_key(&target) {
                self.report(key, "E_UNDEFINED", format!("{key}: undefined reference {target}")); return None;
            }
            let expanded = if let Some(start) = self.active.iter().position(|s| s == &target) {
                let mut path = self.active[start..].to_vec();
                path.push(target.clone());
                self.report(&target, "E_CYCLE", format!("interpolation cycle {}", path.join(" -> ")));
                self.cycle_keys.extend(path);
                None
            } else { self.expand(&target) };
            match expanded {
                Some(text) => result.push_str(&text),
                None => {
                    if !self.cycle_keys.contains(key) { self.report(key, "E_DEPENDENCY", format!("{key}: depends on failed key {target}")); }
                    return None;
                }
            }
            position = close + 1;
        }
        Some(result)
    }
}

pub fn expand(definitions: &BTreeMap<String, Definition>) -> Expansion {
    let mut expander = Expander {
        definitions, expansion: Expansion { results: BTreeMap::new(), diagnostics: Vec::new() },
        active: Vec::new(), cycle_keys: BTreeSet::new(),
    };
    for key in ordered_keys(definitions) { expander.expand(&key); }
    expander.expansion
}
