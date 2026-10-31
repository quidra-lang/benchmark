use std::collections::{BTreeMap, HashMap, HashSet};

pub const TEXT_NAMES: [&str; 5] = ["INITIAL", "FINAL", "DEFAULT", "QUESTION", "REPEAT"];
const GLOBAL: [&str; 12] = ["INITIAL", "FINAL", "QUIT", "STOP", "DEFAULT", "QUESTION", "REPEAT", "MEMSIZE", "PERSIST", "PRE", "POST", "SYNON"];

#[derive(Clone)]
pub struct Diagnostic { pub line: usize, pub code: String, pub message: String }
pub struct Substitution { pub source: String, pub replacement: Vec<String>, pub line: usize }
pub struct Group { pub name: String, pub members: HashSet<String>, pub line: usize }
pub struct Item { pub kind: String, pub text: String, pub arguments: Vec<String>, pub line: usize }
pub struct Rule { pub kind: String, pub pattern: Vec<String>, pub line: usize, pub items: Vec<usize> }
pub struct Keyword { pub word: String, pub rank: usize, pub line: usize, pub memories: Vec<usize>, pub decomps: Vec<usize> }
pub struct Script {
    pub lines: Vec<String>, pub texts: BTreeMap<String, Vec<String>>,
    pub quit: HashSet<String>, pub stop: HashSet<String>, pub persist: HashSet<String>, pub capacity: usize,
    pub pres: Vec<Substitution>, pub posts: Vec<Substitution>,
    pub pre: HashMap<String, Vec<String>>, pub post: HashMap<String, Vec<String>>,
    pub groups: Vec<Group>, pub group_words: BTreeMap<String, HashSet<String>>,
    pub keywords: Vec<Keyword>, pub keyword_map: HashMap<String, usize>,
    pub rules: Vec<Rule>, pub items: Vec<Item>, pub diagnostics: Vec<Diagnostic>,
}

pub fn is_word(word: &str) -> bool {
    !word.is_empty() && !word.starts_with('\'') && !word.ends_with('\'')
        && word.bytes().all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'\'')
}

pub fn reference(word: &str) -> Option<usize> {
    let bytes = word.as_bytes();
    (bytes.len() == 3 && bytes[0] == b'(' && bytes[1].is_ascii_digit() && bytes[2] == b')')
        .then(|| (bytes[1] - b'0') as usize)
}

fn number(word: &str) -> bool { !word.is_empty() && word.len() <= 2 && word.bytes().all(|byte| byte.is_ascii_digit()) }
fn element(word: &str) -> bool { matches!(word, "*" | "#") || word.strip_prefix('@').map_or_else(|| is_word(word), is_word) }

fn well_formed(name: &str, args: &[String]) -> bool {
    match name {
        "INITIAL" | "FINAL" | "DEFAULT" | "QUESTION" | "REPEAT" | "REASM" => !args.is_empty(),
        "QUIT" | "STOP" => !args.is_empty() && args.iter().all(|word| is_word(word)),
        "MEMSIZE" => args.len() == 1 && number(&args[0]) && (1..=20).contains(&args[0].parse::<usize>().unwrap()),
        "PERSIST" => args.len() == 1 && matches!(args[0].as_str(), "cycles" | "memory"),
        "PRE" | "SYNON" => args.len() >= 2 && args.iter().all(|word| is_word(word)),
        "POST" => args.len() >= 2 && is_word(&args[0]),
        "KEY" => args.len() == 2 && is_word(&args[0]) && number(&args[1]),
        "DECOMP" | "MEMORY" => !args.is_empty() && args.iter().all(|word| element(word)),
        "GOTO" => args.len() == 1 && is_word(&args[0]),
        "NEWKEY" => args.is_empty(),
        "RESTATE" => args.len() >= 2 && is_word(&args[0]) && args[1..].iter().all(|word| is_word(word) || reference(word).is_some()),
        _ => false,
    }
}

pub fn load_script(lines: Vec<String>) -> Script {
    let mut script = Script {
        texts: TEXT_NAMES.iter().map(|&name| (name.to_owned(), Vec::new())).collect(), lines,
        quit: HashSet::new(), stop: HashSet::new(), persist: HashSet::new(), capacity: 3,
        pres: Vec::new(), posts: Vec::new(), pre: HashMap::new(), post: HashMap::new(),
        groups: Vec::new(), group_words: BTreeMap::new(), keywords: Vec::new(), keyword_map: HashMap::new(),
        rules: Vec::new(), items: Vec::new(), diagnostics: Vec::new(),
    };
    let mut keyword = None;
    let mut rule = None;
    let mut ignoring = false;
    let mut first_lines: HashMap<String, usize> = HashMap::new();
    for index in 0..script.lines.len() {
        let line = script.lines[index].clone();
        if line.is_empty() || line.starts_with('#') { continue; }
        let (name, text) = line.split_once(' ').unwrap_or((&line, ""));
        let args: Vec<String> = text.split_whitespace().map(str::to_owned).collect();
        let is_rule = matches!(name, "DECOMP" | "MEMORY");
        let is_item = matches!(name, "REASM" | "GOTO" | "NEWKEY" | "RESTATE");
        if GLOBAL.contains(&name) || name == "KEY" { keyword = None; rule = None; ignoring = false; }
        else if is_rule || is_item {
            if ignoring { continue; }
            if is_rule { rule = None; }
        }
        let definition = if name == "MEMSIZE" { Some(name.to_owned()) }
            else if matches!(name, "KEY" | "SYNON" | "PRE" | "POST" | "PERSIST") && !args.is_empty() { Some(format!("{name} {}", args[0])) }
            else { None };
        let problem = if !GLOBAL.contains(&name) && name != "KEY" && !is_rule && !is_item {
            Some(("SYNTAX", format!("unknown directive {name}")))
        } else if !well_formed(name, &args) {
            Some(("SYNTAX", format!("bad arguments for {name}")))
        } else if is_rule && keyword.is_none() {
            Some(("ORPHAN", format!("{name} without KEY")))
        } else if name == "REASM" && rule.is_none() {
            Some(("ORPHAN", "REASM without DECOMP or MEMORY".to_owned()))
        } else if matches!(name, "GOTO" | "NEWKEY" | "RESTATE") && rule.is_none_or(|id: usize| script.rules[id].kind == "MEMORY") {
            Some(("ORPHAN", format!("{name} without DECOMP")))
        } else if let Some((key, first)) = definition.as_ref().and_then(|key| first_lines.get(key).map(|first| (key, first))) {
            Some(("DUPLICATE", format!("{key} first defined at line {first}")))
        } else { None };
        if let Some((code, message)) = problem {
            script.diagnostics.push(Diagnostic { line: index + 1, code: code.to_owned(), message });
            if code == "DUPLICATE" && name == "KEY" { ignoring = true; }
            continue;
        }
        let line_number = index + 1;
        if let Some(key) = definition { first_lines.insert(key, line_number); }
        match name {
            "INITIAL" | "FINAL" | "DEFAULT" | "QUESTION" | "REPEAT" => script.texts.get_mut(name).unwrap().push(text.to_owned()),
            "QUIT" => script.quit.extend(args),
            "STOP" => script.stop.extend(args),
            "PERSIST" => { script.persist.insert(args[0].clone()); }
            "MEMSIZE" => script.capacity = args[0].parse().unwrap(),
            "PRE" | "POST" => {
                let entry = Substitution { source: args[0].clone(), replacement: args[1..].to_vec(), line: line_number };
                if name == "PRE" { script.pre.insert(entry.source.clone(), entry.replacement.clone()); script.pres.push(entry); }
                else { script.post.insert(entry.source.clone(), entry.replacement.clone()); script.posts.push(entry); }
            }
            "SYNON" => {
                let members: HashSet<String> = args.iter().cloned().collect();
                script.group_words.insert(args[0].clone(), members.clone());
                script.groups.push(Group { name: args[0].clone(), members, line: line_number });
            }
            "KEY" => {
                let id = script.keywords.len();
                script.keyword_map.insert(args[0].clone(), id);
                script.keywords.push(Keyword { word: args[0].clone(), rank: args[1].parse().unwrap(), line: line_number, memories: Vec::new(), decomps: Vec::new() });
                keyword = Some(id);
            }
            "DECOMP" | "MEMORY" => {
                let id = script.rules.len();
                script.rules.push(Rule { kind: name.to_owned(), pattern: args, line: line_number, items: Vec::new() });
                let key = &mut script.keywords[keyword.unwrap()];
                if name == "MEMORY" { key.memories.push(id); } else { key.decomps.push(id); }
                rule = Some(id);
            }
            _ => {
                let id = script.items.len();
                script.items.push(Item { kind: name.to_owned(), text: text.to_owned(), arguments: args, line: line_number });
                script.rules[rule.unwrap()].items.push(id);
            }
        }
    }
    script
}
