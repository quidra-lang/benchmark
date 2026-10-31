use std::collections::HashSet;
use crate::matcher::{pattern_covers, wildcard};
use crate::script_loader::{reference, Diagnostic, Script};

const CODES: [&str; 13] = ["SYNTAX", "ORPHAN", "DUPLICATE", "KEY_NO_DECOMP", "KEY_UNREACHABLE", "SYNON_UNUSED", "PRE_CHAIN", "SYNON_UNKNOWN", "RULE_NO_REASM", "RULE_SHADOWED", "REF_UNBOUND", "TARGET_UNDEFINED", "TARGET_CYCLE"];
const ERRORS: [&str; 7] = ["SYNTAX", "ORPHAN", "DUPLICATE", "SYNON_UNKNOWN", "REF_UNBOUND", "TARGET_UNDEFINED", "TARGET_CYCLE"];

pub fn lint(script: &Script) -> Vec<String> {
    let mut found = script.diagnostics.clone();
    let mut add = |line: usize, code: &str, message: String| found.push(Diagnostic { line, code: code.to_owned(), message });
    let mut targets = HashSet::new();
    let mut graph = vec![Vec::new(); script.keywords.len()];
    for (id, keyword) in script.keywords.iter().enumerate() {
        for &rule in &keyword.decomps {
            for &item in &script.rules[rule].items {
                let item = &script.items[item];
                if matches!(item.kind.as_str(), "GOTO" | "RESTATE") {
                    targets.insert(item.arguments[0].clone());
                    if let Some(&target) = script.keyword_map.get(&item.arguments[0]) { graph[id].push(target); }
                }
            }
        }
    }
    let unknown = |pattern: &[String]| pattern.iter().filter_map(|element| element.strip_prefix('@')).any(|name| !script.group_words.contains_key(name));
    for (id, keyword) in script.keywords.iter().enumerate() {
        if keyword.decomps.is_empty() { add(keyword.line, "KEY_NO_DECOMP", format!("keyword {} has no DECOMP", keyword.word)); }
        if script.pre.contains_key(&keyword.word) && !script.pres.iter().any(|pre| pre.replacement.contains(&keyword.word)) && !targets.contains(&keyword.word) {
            add(keyword.line, "KEY_UNREACHABLE", format!("keyword {} is replaced by PRE", keyword.word));
        }
        for rules in [&keyword.memories, &keyword.decomps] {
            for (position, &rule_id) in rules.iter().enumerate() {
                let rule = &script.rules[rule_id];
                for name in rule.pattern.iter().filter_map(|element| element.strip_prefix('@')) {
                    if !script.group_words.contains_key(name) { add(rule.line, "SYNON_UNKNOWN", format!("unknown group {name}")); }
                }
                if rule.items.is_empty() { add(rule.line, "RULE_NO_REASM", "rule has no reassembly".to_owned()); }
                if !unknown(&rule.pattern) {
                    if let Some(earlier) = rules[..position].iter().map(|&index| &script.rules[index]).find(|earlier| !unknown(&earlier.pattern) && pattern_covers(&earlier.pattern, &rule.pattern, &script.group_words)) {
                        add(rule.line, "RULE_SHADOWED", format!("pattern is shadowed by line {}", earlier.line));
                    }
                }
                let wildcards = rule.pattern.iter().filter(|element| wildcard(element)).count();
                for &item_id in &rule.items {
                    let item = &script.items[item_id];
                    let refs: Vec<usize> = if item.kind == "REASM" {
                        item.text.as_bytes().windows(3).filter_map(|chunk| reference(std::str::from_utf8(chunk).unwrap())).collect()
                    } else if item.kind == "RESTATE" { item.arguments[1..].iter().filter_map(|word| reference(word)).collect() } else { Vec::new() };
                    for number in refs {
                        if number == 0 || number > wildcards { add(item.line, "REF_UNBOUND", format!("reference ({number}) is not bound")); }
                    }
                    if !matches!(item.kind.as_str(), "GOTO" | "RESTATE") { continue; }
                    let target = &item.arguments[0];
                    if let Some(&start) = script.keyword_map.get(target) {
                        let mut pending = vec![start];
                        let mut seen = HashSet::new();
                        let mut cycle = false;
                        while let Some(node) = pending.pop() {
                            if node == id { cycle = true; break; }
                            if seen.insert(node) { pending.extend(graph[node].iter().copied()); }
                        }
                        if cycle { add(item.line, "TARGET_CYCLE", format!("edge {} -> {target} is on a cycle", keyword.word)); }
                    } else { add(item.line, "TARGET_UNDEFINED", format!("target {target} is not a keyword")); }
                }
            }
        }
    }
    for group in &script.groups {
        if !script.rules.iter().any(|rule| rule.pattern.iter().any(|element| element.strip_prefix('@') == Some(group.name.as_str()))) {
            add(group.line, "SYNON_UNUSED", format!("group {} is never used", group.name));
        }
    }
    for pre in &script.pres {
        for word in &pre.replacement {
            if script.pre.contains_key(word) { add(pre.line, "PRE_CHAIN", format!("replacement {word} is itself replaced by PRE")); }
        }
    }
    found.sort_by_key(|diagnostic| (diagnostic.line, CODES.iter().position(|&code| code == diagnostic.code).unwrap()));
    if found.is_empty() { return vec!["OK".to_owned()]; }
    let errors = found.iter().filter(|diagnostic| ERRORS.contains(&diagnostic.code.as_str())).count();
    let mut lines: Vec<String> = found.iter().map(|diagnostic| format!("{} {} {}", diagnostic.line, diagnostic.code, diagnostic.message)).collect();
    lines.push(format!("TOTAL {} errors={errors} warnings={}", found.len(), found.len() - errors));
    lines
}
