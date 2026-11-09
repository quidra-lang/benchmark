use std::collections::BTreeMap;
use std::fs;
use crate::lexer::{
    LogicalLine,
    lex
};
#[derive(Clone)]
pub struct File {
    pub lines: Vec<LogicalLine>,
    pub physical_lines: usize,
    pub guard: Option<String>,
    pub entered: usize,
    pub skipped: usize,
    pub output: usize,
    pub skipped_lines: usize,
    pub once: bool,
}
pub struct Includes {
    pub files: BTreeMap<String,
    File>,
    pub order: Vec<String>
}
pub fn search(name: &str, quoted: bool) -> Option<String> {
    if quoted && std::path::Path::new(&format!("input/{}", name)).is_file() {
        return Some(name.into());
    }
    let path = format!("include/{}", name);
    if std::path::Path::new(&format!("input/{}", path)).is_file() {
        Some(path)
    } else {
        None
    }
}
pub fn header(tokens: &[crate::lexer::Token], index: usize) -> Result<Option<(String, String, bool, usize)>, String> {
    let token = match tokens.get(index) {
        Some(token) => token,
        None => return Ok(None)
    };
    if token.kind == "string" || token.kind == "header" {
        let text = token.text.clone();
        return Ok(Some((text[1..text.len() - 1].into(), text.clone(), token.kind == "string", index + 1)));
    }
    if token.text == "<" {
        let end = (index + 1..tokens.len()).find(|&i| tokens[i].text == ">").ok_or("missing terminating > character")?;
        let name = crate::lexer::render(&tokens[index + 1..end], false);
        return Ok(Some((name.clone(), format!("<{}>", name), false, end + 1)));
    }
    Ok(None)
}
fn guard(lines: &[LogicalLine]) -> Option<String> {
    let lines: Vec<_> = lines.iter().filter(|l| !l.tokens.is_empty()).collect();
    let first = lines.first()?.tokens.as_slice();
    let last = lines.last()?.tokens.as_slice();
    if first.len() != 3 || first[0].text != "#" || first[1].text != "ifndef" || first[2].kind != "identifier" || last.len() != 2 || last[0].text != "#" || last[1].text != "endif" {
        return None;
    }
    let mut depth = 0i64;
    for (i, line) in lines.iter().enumerate() {
        let tokens = &line.tokens;
        let directive = if tokens.len() >= 2 && tokens[0].text == "#" && tokens[1].kind == "identifier" {
            tokens[1].text.as_str()
        } else {
            ""
        };
        if depth == 1 && ["elif", "elifdef", "elifndef", "else"].contains(&directive) {
            return None;
        }
        if ["if", "ifdef", "ifndef"].contains(&directive) {
            depth += 1;
        } else if directive == "endif" {
            depth -= 1;
        }
        if depth == 0 && i + 1 != lines.len() {
            return None;
        }
    }
    if depth == 0 {
        Some(first[2].text.clone())
    } else {
        None
    }
}
impl Includes {
    pub fn new() -> Self {
        Self {
            files: BTreeMap::new(),
            order: Vec::new()
        }
    }
    pub fn enter(&mut self, path: &str) {
        if !self.files.contains_key(path) {
            let source = fs::read_to_string(format!("input/{}", path)).unwrap();
            let lines = lex(&source);
            let guard = guard(&lines);
            self.files.insert(path.into(), File {
                lines,
                physical_lines: source.bytes().filter(|&b| b == b'\n').count(),
                guard,
                entered: 0,
                skipped: 0,
                output: 0,
                skipped_lines: 0,
                once: false
            });
            self.order.push(path.into());
        }
        self.files.get_mut(path).unwrap().entered += 1;
    }
}
