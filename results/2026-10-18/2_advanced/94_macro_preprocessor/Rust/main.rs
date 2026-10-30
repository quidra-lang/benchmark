mod lexer;
mod definitions;
mod expression;
mod expander;
mod include_manager;
use std::collections::{
    BTreeMap,
    BTreeSet
};
use std::rc::Rc;
use std::cell::RefCell;
use std::fs;
use lexer::{
    Token,
    LogicalLine,
    render
};
use definitions::{
    Position,
    Macro,
    builtin
};
use expander::{
    Expander,
    Definition
};
use include_manager::{
    Includes,
    header,
    search
};
struct Block {
    kind: String,
    position: Position,
    parent: bool,
    chosen: bool,
    active: bool,
    else_seen: bool,
    skip: Option<usize>
}
struct Inclusion {
    path: String,
    file: String,
    offset: i64,
    depth: usize,
    blocks: Vec<Block>,
    segment: Vec<Token>
}
impl Inclusion {
    fn position(&self, line: i64) -> Position {
        Position {
            file: self.file.clone(),
            line: line + self.offset
        }
    }
    fn active(&self) -> bool {
        self.blocks.last().map_or(true, |block| block.active)
    }
}
struct Processor {
    expansion: Expander,
    includes: Includes,
    poisoned: BTreeSet<String>,
    saves: BTreeMap<String,
    Vec<Option<Definition>>>,
    ever: BTreeSet<String>,
    preprocessed: Vec<String>,
    tree: Vec<String>,
    history: Vec<String>,
    conditionals: Vec<String>,
    regions: Vec<String>,
    results: [usize; 5],
    previous: Position,
}
impl Processor {
    fn new() -> Self {
        Self {
            expansion: Expander::new(),
            includes: Includes::new(),
            poisoned: BTreeSet::new(),
            saves: BTreeMap::new(),
            ever: BTreeSet::new(),
            preprocessed: Vec::new(),
            tree: vec!["main.c".into()],
            history: Vec::new(),
            conditionals: Vec::new(),
            regions: Vec::new(),
            results: [0; 5],
            previous: Position {
                file: "main.c".into(),
                line: 0
            }
        }
    }
    fn diagnostic(&mut self, position: &Position, kind: &'static str, message: String) {
        self.expansion.diagnostic(position.clone(), kind, message);
    }
    fn history(&mut self, position: &Position, event: String) {
        self.history.push(format!("{}: {}", position.text(), event));
    }
    fn poison(&mut self, tokens: &[Token], inclusion: &Inclusion) {
        for token in tokens {
            if token.kind == "identifier" && self.poisoned.contains(&token.text) {
                self.diagnostic(&inclusion.position(token.line), "error", format!("attempt to use poisoned \"{}\"", token.text));
            }
        }
    }
    fn unused(&mut self, definition: &Macro) {
        if definition.main && definition.expanded == 0 && definition.tested == 0 {
            self.diagnostic(&definition.position, "warning", format!("macro \"{}\" is not used", definition.name));
        }
    }
    fn define(&mut self, tokens: &[Token], position: &Position, main: bool) {
        let definition = match definitions::parse(tokens, position.clone(), main) {
            Ok(definition) => definition,
            Err(message) => {
                self.diagnostic(position, "error", message);
                return;
            }
        };
        let name = definition.name.clone();
        let signature = definition.signature();
        let old = self.expansion.table.get(&name).map(|old| old.borrow().clone());
        if let Some(old) = old {
            if old.identical(&definition) {
                self.history(position, format!("identical {}", signature));
                return;
            }
            self.unused(&old);
            self.diagnostic(position, "warning", format!("\"{}\" redefined (previous definition at {})", name, old.position.text()));
            self.history(position, format!("redefine {}", signature));
        } else {
            self.history(position, format!("define {}", signature));
        }
        self.ever.insert(name.clone());
        self.expansion.table.insert(name, Rc::new(RefCell::new(definition)));
    }
    fn undef(&mut self, tokens: &[Token], position: &Position) {
        let name = match definitions::check_name(tokens, "undef") {
            Ok(name) => name,
            Err(message) => {
                self.diagnostic(position, "error", message);
                return;
            }
        };
        if tokens.len() > 1 {
            self.diagnostic(position, "warning", "extra tokens at end of #undef directive".into());
        }
        if let Some(old) = self.expansion.table.remove(&name) {
            self.unused(&old.borrow());
            self.history(position, format!("undef {}", name));
        }
        else {
            self.history(position, format!("undef {} (not defined)", name));
        }
    }
    fn marker(&mut self, file: &str, line: i64, suffix: &str) {
        self.preprocessed.push(format!("# {} \"{}\"{}", line, file, suffix));
        self.previous = Position {
            file: file.into(),
            line: line - 1
        };
    }
    fn output_line(&mut self, inclusion: &Inclusion, line: i64, text: String) {
        let position = inclusion.position(line);
        if self.previous.file == position.file && self.previous.line < position.line && position.line <= self.previous.line + 8 {
            for _ in self.previous.line + 1..position.line {
                self.preprocessed.push(String::new());
            }
        } else {
            self.marker(&position.file, position.line, "");
        }
        self.preprocessed.push(text);
        self.previous = position;
        self.includes.files.get_mut(&inclusion.path).unwrap().output += 1;
    }
    fn flush(&mut self, inclusion: &mut Inclusion) {
        let segment = std::mem::take(&mut inclusion.segment);
        self.poison(&segment, inclusion);
        let expanded = self.expansion.expand(&segment, &inclusion.file, inclusion.offset);
        let mut i = 0;
        while i < expanded.len() {
            let mut end = i + 1;
            while end < expanded.len() && expanded[end].line == expanded[i].line {
                end += 1;
            }
            self.output_line(inclusion, expanded[i].line, render(&expanded[i..end], true));
            i = end;
        }
    }
    fn defined(&mut self, name: &str) -> bool {
        if let Some(definition) = self.expansion.table.get(name) {
            definition.borrow_mut().tested += 1;
            true
        } else {
            builtin(name) || name == "__has_include"
        }
    }
    fn replace_operators(&mut self, tokens: &[Token]) -> Result<Vec<Token>,
    String> {
        let mut result = Vec::new();
        let mut i = 0;
        while i < tokens.len() {
            let token = &tokens[i];
            if token.kind == "identifier" && token.text == "defined" {
                i += 1;
                let parenthesized = tokens.get(i).map_or(false, |t| t.text == "(");
                if parenthesized {
                    i += 1;
                }
                let name = tokens.get(i).filter(|t| t.kind == "identifier").ok_or("operator \"defined\" requires an identifier")?.text.clone();
                i += 1;
                if parenthesized {
                    if tokens.get(i).map_or(true, |t| t.text != ")") {
                        return Err("missing ')' after \"defined\"".into());
                    }
                    i += 1;
                }
                let value = if self.defined(&name) {
                    "1"
                } else {
                    "0"
                };
                result.push(Token::new("number", value.into(), token.line, token.space));
            } else if token.kind == "identifier" && token.text == "__has_include" {
                i += 1;
                if tokens.get(i).map_or(true, |t| t.text != "(") {
                    return Err("missing '(' after \"__has_include\"".into());
                }
                i += 1;
                let (name, _, quoted, end) = header(tokens, i)?.filter(|h| !h.0.is_empty()).ok_or("operator \"__has_include\" requires a header-name")?;
                i = end;
                if tokens.get(i).map_or(true, |t| t.text != ")") {
                    return Err("missing ')' after \"__has_include\" operand".into());
                }
                i += 1;
                result.push(Token::new("number", if search(&name, quoted).is_some() {
                    "1"
                } else {
                    "0"
                }.into(), token.line, token.space));
            } else {
                result.push(token.clone());
                i += 1;
            }
        }
        Ok(result)
    }
    fn test(&mut self, name: &str, tokens: &[Token], inclusion: &Inclusion, position: &Position) -> (bool, String) {
        self.poison(tokens, inclusion);
        let mut expanded_text = None;
        let value = if name == "if" || name == "elif" {
            match self.replace_operators(tokens) {
                Err(message) => {
                    self.diagnostic(position, "error", message);
                    None
                },
                Ok(tokens) => {
                    let tokens = self.expansion.expand(&tokens, &inclusion.file, inclusion.offset);
                    expanded_text = Some(render(&tokens, true));
                    let (value, diagnostics) = expression::test(&tokens, name);
                    for (kind, message) in diagnostics {
                        self.diagnostic(position, kind, message);
                    }
                    value
                }
            }
        } else if tokens.is_empty() {
            self.diagnostic(position, "error", format!("no macro name given in #{} directive", name));
            None
        }
        else if tokens[0].kind != "identifier" {
            self.diagnostic(position, "error", "macro names must be identifiers".into());
            None
        }
        else {
            if tokens.len() > 1 {
                self.diagnostic(position, "warning", format!("extra tokens at end of #{} directive", name));
            }
            let defined = self.defined(&tokens[0].text);
            let positive = name == "ifdef" || name == "elifdef";
            Some(if defined == positive {
                1
            } else {
                0
            })
        };
        let mut result = match value {
            None => "not taken (error)".into(),
            Some(0) => "not taken".into(),
            Some(_) => "taken".into()
        };
        if (name == "if" || name == "elif") && value.is_some() {
            result.push_str(&format!(" (value {})", value.unwrap()));
        }
        if let Some(text) = expanded_text {
            result.push_str(&format!(" [{}]", text));
        }
        (value.map_or(false, |v| v != 0), result)
    }
    fn close_region(&mut self, inclusion: &Inclusion, block: &mut Block, end: usize) {
        if let Some(start) = block.skip.take() {
            if end >= start {
                self.regions.push(format!("{}:{}-{} lines={}", inclusion.file, start as i64 + inclusion.offset, end as i64 + inclusion.offset, end - start + 1));
                self.includes.files.get_mut(&inclusion.path).unwrap().skipped_lines += end - start + 1;
            }
        }
    }
    fn conditional(&mut self, name: &str, line: &LogicalLine, inclusion: &mut Inclusion) {
        let tokens = &line.tokens[2..];
        let position = inclusion.position(line.tokens[0].line);
        let indentation;
        let result;
        if ["if", "ifdef", "ifndef"].contains(&name) {
            indentation = inclusion.blocks.len();
            let parent = inclusion.active();
            let (active, record) = if parent {
                self.test(name, tokens, inclusion, &position)
            } else {
                (false, "skipped".into())
            };
            result = record;
            inclusion.blocks.push(Block {
                kind: name.into(),
                position: position.clone(),
                parent,
                chosen: active,
                active,
                else_seen: false,
                skip: if parent && !active {
                    Some(line.end + 1)
                } else {
                    None
                }
            });
        } else {
            let mut block = match inclusion.blocks.pop() {
                Some(block) => block,
                None => {
                    self.diagnostic(&position, "error", format!("#{} without #if", name));
                    return;
                }
            };
            indentation = inclusion.blocks.len();
            self.close_region(inclusion, &mut block, line.start.saturating_sub(1));
            if name == "endif" {
                if block.parent && !tokens.is_empty() {
                    self.diagnostic(&position, "warning", "extra tokens at end of #endif directive".into());
                }
                result = format!("closes #{} at line {}", block.kind, block.position.line);
            } else {
                if block.else_seen {
                    self.diagnostic(&position, "error", format!("#{} after #else", name));
                }
                if name == "else" {
                    if block.parent && !tokens.is_empty() {
                        self.diagnostic(&position, "warning", "extra tokens at end of #else directive".into());
                    }
                    block.else_seen = true;
                    if block.parent {
                        block.active = !block.chosen;
                        block.chosen = true;
                        result = if block.active {
                            "taken"
                        } else {
                            "not taken"
                        }.into();
                    }
                    else {
                        block.active = false;
                        result = "skipped".into();
                    }
                } else if !block.parent {
                    block.active = false;
                    result = "skipped".into();
                }
                else if block.chosen {
                    block.active = false;
                    result = "not evaluated".into();
                }
                else {
                    let (active, record) = self.test(name, tokens, inclusion, &position);
                    block.active = active;
                    block.chosen |= active;
                    result = record;
                }
                if block.parent && !block.active {
                    block.skip = Some(line.end + 1);
                }
                inclusion.blocks.push(block);
            }
        }
        let category = if result.starts_with("taken") {
            0
        } else if result.starts_with("not taken") {
            1
        } else if result.starts_with("skipped") {
            2
        } else if result.starts_with("not evaluated") {
            3
        } else {
            4
        };
        self.results[category] += 1;
        let directive = format!("#{}{}", name, if tokens.is_empty() {
            String::new()
        } else {
            format!(" {}", render(tokens, false))
        });
        self.conditionals.push(format!("{}: {}{} => {}", position.text(), " ".repeat(indentation * 2), directive, result));
    }
    fn include(&mut self, tokens: &[Token], line: &LogicalLine, inclusion: &Inclusion, position: &Position) {
        let mut sequence = tokens.to_vec();
        let mut specification = match header(&sequence, 0) {
            Ok(specification) => specification,
            Err(message) => {
                self.diagnostic(position, "error", message);
                return;
            }
        };
        if specification.is_none() && !tokens.is_empty() {
            sequence = self.expansion.expand(tokens, &inclusion.file, inclusion.offset);
            specification = match header(&sequence, 0) {
                Ok(specification) => specification,
                Err(message) => {
                    self.diagnostic(position, "error", message);
                    return;
                }
            };
        }
        let (name, rendering, quoted, end) = match specification {
            Some(specification) => specification,
            None => {
                self.diagnostic(position, "error", "#include expects \"FILENAME\" or <FILENAME>".into());
                return;
            }
        };
        if end < sequence.len() {
            self.diagnostic(position, "warning", "extra tokens at end of #include directive".into());
        }
        if name.is_empty() {
            self.diagnostic(position, "error", "empty filename in #include".into());
            return;
        }
        let prefix = format!("{}{}: ", " ".repeat(2 * (inclusion.depth + 1)), line.tokens[0].line);
        let path = match search(&name, quoted) {
            Some(path) => path,
            None => {
                self.tree.push(format!("{}{} [not found]", prefix, rendering));
                self.diagnostic(position, "error", format!("cannot find include file {}", rendering));
                return;
            }
        };
        let skipped = self.includes.files.get(&path).and_then(|file| {
            if file.once {
                Some("pragma once".into())
            } else {
                file.guard.as_ref().filter(|guard| self.expansion.table.contains_key(*guard)).map(|guard| format!("guard {}", guard))
            }
        });
        if let Some(reason) = skipped {
            self.tree.push(format!("{}{} [skipped: {}]", prefix, path, reason));
            self.includes.files.get_mut(&path).unwrap().skipped += 1;
            return;
        }
        if inclusion.depth + 1 > 8 {
            self.tree.push(format!("{}{} [too deep]", prefix, path));
            self.diagnostic(position, "error", "#include nested too deeply".into());
            return;
        }
        self.tree.push(format!("{}{}", prefix, path));
        self.marker(&path, 1, " 1");
        self.process(&path, inclusion.depth + 1);
        self.marker(&inclusion.file, line.end as i64 + 1 + inclusion.offset, " 2");
    }
    fn pragma(&mut self, tokens: &[Token], line: &LogicalLine, inclusion: &Inclusion, position: &Position) {
        let name = tokens.first().filter(|t| t.kind == "identifier").map_or("", |t| t.text.as_str());
        if name == "once" {
            if tokens.len() > 1 {
                self.diagnostic(position, "warning", "extra tokens at end of #pragma once directive".into());
            }
            if inclusion.depth == 0 {
                self.diagnostic(position, "warning", "#pragma once in main file".into());
            }
            self.includes.files.get_mut(&inclusion.path).unwrap().once = true;
        } else if tokens.len() >= 2 && tokens[0].text == "GCC" && tokens[1].text == "poison" {
            if tokens[2..].iter().any(|t| t.kind != "identifier") {
                self.diagnostic(position, "error", "invalid #pragma GCC poison directive".into());
                return;
            }
            for token in &tokens[2..] {
                if self.expansion.table.contains_key(&token.text) {
                    self.diagnostic(position, "warning", format!("poisoning existing macro \"{}\"", token.text));
                }
                self.poisoned.insert(token.text.clone());
            }
        } else if name == "push_macro" || name == "pop_macro" {
            if tokens.len() != 4 || tokens[1].text != "(" || tokens[2].kind != "string" || tokens[3].text != ")" {
                self.diagnostic(position, "error", format!("invalid #pragma {} directive", name));
                return;
            }
            let text = &tokens[2].text;
            let macro_name = text[1..text.len() - 1].to_string();
            if name == "push_macro" {
                let definition = self.expansion.table.get(&macro_name).cloned();
                self.saves.entry(macro_name.clone()).or_default().push(definition);
                self.history(position, format!("push {}", macro_name));
            }
            else {
                let saved = self.saves.get_mut(&macro_name).and_then(|stack| stack.pop());
                match saved {
                    None => self.diagnostic(position, "warning", format!("no matching push_macro for \"{}\"", macro_name)),
                    Some(None) => {
                        self.expansion.table.remove(&macro_name);
                        self.history(position, format!("pop {} (undefined)", macro_name));
                    },
                    Some(Some(definition)) => {
                        self.expansion.table.insert(macro_name.clone(), definition);
                        self.history(position, format!("pop {}", macro_name));
                    }
                }
            }
        } else {
            self.output_line(inclusion, line.tokens[0].line, format!("#pragma{}", if tokens.is_empty() {
                String::new()
            } else {
                format!(" {}", render(tokens, false))
            }));
        }
    }
    fn other(&mut self, name: &str, tokens: &[Token], line: &LogicalLine, inclusion: &mut Inclusion, position: &Position) {
        match name {
            "define" => self.define(tokens, position, inclusion.depth == 0),
            "undef" => self.undef(tokens, position),
            "include" => self.include(tokens, line, inclusion, position),
            "error" | "warning" => self.diagnostic(position, if name == "error" {
                "error"
            } else {
                "warning"
            }, format!("#{}{}", name, if tokens.is_empty() {
                String::new()
            } else {
                format!(" {}", render(tokens, false))
            })),
            "pragma" => self.pragma(tokens, line, inclusion, position),
            "line" => {
                let decimal = |token: &Token| token.kind == "number" && !token.text.is_empty() && token.text.bytes().all(|b| b.is_ascii_digit());
                let tokens = if tokens.first().map_or(false, decimal) {
                    tokens.to_vec()
                } else {
                    self.expansion.expand(tokens, &inclusion.file, inclusion.offset)
                };
                if tokens.is_empty() || tokens.len() > 2 || !decimal(&tokens[0]) || (tokens.len() == 2 && tokens[1].kind != "string") {
                    self.diagnostic(position, "error", "invalid #line directive".into());
                    return;
                }
                let number: i64 = tokens[0].text.parse().unwrap();
                if number < 1 || number > 2147483647 {
                    self.diagnostic(position, "error", "line number out of range".into());
                    return;
                }
                inclusion.offset = number - (line.end + 1) as i64;
                if tokens.len() == 2 {
                    inclusion.file = tokens[1].text[1..tokens[1].text.len() - 1].into();
                }
            },
            _ => if line.tokens.len() > 1 {
                self.diagnostic(position, "error", format!("invalid preprocessing directive #{}", line.tokens[1].text));
            }
        }
    }
    fn process(&mut self, path: &str, depth: usize) {
        self.includes.enter(path);
        let lines = self.includes.files[path].lines.clone();
        let mut inclusion = Inclusion {
            path: path.into(),
            file: path.into(),
            offset: 0,
            depth,
            blocks: Vec::new(),
            segment: Vec::new()
        };
        for line in lines {
            let directive = line.tokens.first().map_or(false, |t| t.text == "#");
            let name = if directive && line.tokens.len() > 1 && line.tokens[1].kind == "identifier" {
                line.tokens[1].text.as_str()
            } else {
                ""
            };
            if directive && ["if", "ifdef", "ifndef", "elif", "elifdef", "elifndef", "else", "endif"].contains(&name) {
                self.flush(&mut inclusion);
                self.conditional(name, &line, &mut inclusion);
            }
            else if !inclusion.active() {
                continue;
            }
            else if directive {
                self.flush(&mut inclusion);
                let tokens = if line.tokens.len() >= 2 {
                    &line.tokens[2..]
                } else {
                    &[]
                };
                let position = inclusion.position(line.tokens[0].line);
                if !(name == "pragma" && tokens.len() >= 2 && tokens[0].text == "GCC" && tokens[1].text == "poison") && line.tokens.len() > 1 {
                    self.poison(tokens, &inclusion);
                }
                self.other(name, tokens, &line, &mut inclusion, &position);
            } else {
                inclusion.segment.extend(line.tokens);
            }
        }
        self.flush(&mut inclusion);
        let last = self.includes.files[path].physical_lines;
        let mut blocks = std::mem::take(&mut inclusion.blocks);
        for block in &mut blocks {
            self.close_region(&inclusion, block, last);
        }
        for block in blocks {
            self.diagnostic(&block.position, "error", format!("unterminated #{}", block.kind));
        }
    }
    fn reports(&mut self) {
        let definitions: Vec<Macro> = self.expansion.table.values().map(|definition| definition.borrow().clone()).collect();
        for definition in &definitions {
            self.unused(definition);
        }
        let mut includes = self.tree.clone();
        includes.push(String::new());
        includes.push("== files ==".into());
        for (path, file) in &self.includes.files {
            includes.push(format!("{} entered={} skipped={} lines={} output_lines={} skipped_lines={} guard={} once={}", path, file.entered, file.skipped, file.physical_lines, file.output, file.skipped_lines, file.guard.as_deref().unwrap_or("-"), if file.once {
                "yes"
            } else {
                "no"
            }));
        }
        includes.push(String::new());
        let mut dependency = "main.o:".to_string();
        let mut any = false;
        for path in &self.includes.order {
            if any && dependency.len() + 1 + path.len() > 76 {
                includes.push(dependency + " \\");
                dependency = " ".into();
            }
            dependency.push(' ');
            dependency.push_str(path);
            any = true;
        }
        includes.push(dependency);
        let mut macros = vec!["== history ==".into()];
        macros.extend(self.history.iter().cloned());
        macros.push(String::new());
        macros.push("== table ==".into());
        let mut references: BTreeMap<String,
        BTreeSet<String>> = BTreeMap::new();
        for definition in &definitions {
            let parameters = definition.parameters.clone().unwrap_or_default();
            let names = definition.replacement.iter().filter(|t| t.kind == "identifier" && self.expansion.table.contains_key(&t.text) && !parameters.contains(&t.text)).map(|t| t.text.clone()).collect();
            references.insert(definition.name.clone(), names);
        }
        for definition in &definitions {
            let recursive = recursive(&definition.name, &references);
            macros.push(definition.definition());
            macros.push(format!("  at {} expanded={} tested={} recursive={}", definition.position.text(), definition.expanded, definition.tested, if recursive {
                "yes"
            } else {
                "no"
            }));
            macros.push(list("  refs:", references[&definition.name].iter().cloned()));
        }
        macros.push(String::new());
        let function_like = definitions.iter().filter(|d| d.parameters.is_some()).count();
        macros.push(format!("macros={} object_like={} function_like={}", definitions.len(), definitions.len() - function_like, function_like));
        macros.push(list("undefined:", self.ever.iter().filter(|name| !self.expansion.table.contains_key(*name)).cloned()));
        macros.push(format!("builtins: __COUNTER__={} __FILE__={} __LINE__={}", self.expansion.builtins["__COUNTER__"], self.expansion.builtins["__FILE__"], self.expansion.builtins["__LINE__"]));
        let mut conditionals = self.conditionals.clone();
        conditionals.push(String::new());
        conditionals.push("== skipped regions ==".into());
        conditionals.extend(self.regions.iter().cloned());
        conditionals.push(String::new());
        conditionals.push(format!("directives={} taken={} not_taken={} skipped={} not_evaluated={} endif={} regions={}", self.conditionals.len(), self.results[0], self.results[1], self.results[2], self.results[3], self.results[4], self.regions.len()));
        let mut diagnostics = Vec::new();
        let mut errors = 0;
        let mut warnings = 0;
        for diagnostic in &self.expansion.diagnostics {
            diagnostics.push(format!("{}: {}: {}", diagnostic.position.text(), diagnostic.kind, diagnostic.message));
            if diagnostic.kind == "error" {
                errors += 1;
            } else {
                warnings += 1;
            }
        }
        diagnostics.push(format!("errors={} warnings={}", errors, warnings));
        write("preprocessed.txt", &self.preprocessed);
        write("includes.txt", &includes);
        write("macros.txt", &macros);
        write("conditionals.txt", &conditionals);
        write("diagnostics.txt", &diagnostics);
    }
}
fn list(heading: &str, values: impl IntoIterator<Item = String>) -> String {
    let mut text = heading.to_string();
    for value in values {
        text.push(' ');
        text.push_str(&value);
    }
    text
}
fn recursive(name: &str, references: &BTreeMap<String, BTreeSet<String>>) -> bool {
    let mut pending: Vec<String> = references[name].iter().cloned().collect();
    let mut seen = BTreeSet::new();
    while let Some(next) = pending.pop() {
        if next == name {
            return true;
        }
        if seen.insert(next.clone()) {
            pending.extend(references[&next].iter().cloned());
        }
    }
    false
}
fn write(name: &str, lines: &[String]) {
    fs::create_dir_all("output").unwrap();
    fs::write(format!("output/{}", name), if lines.is_empty() {
        String::new()
    } else {
        lines.join("\n") + "\n"
    }).unwrap();
}
fn main() {
    let mut processor = Processor::new();
    let defines = fs::read_to_string("input/defines.txt").unwrap();
    for (i, line) in defines.lines().enumerate() {
        if line.is_empty() {
            continue;
        }
        let text = if let Some(at) = line.find('=') {
            format!("{} {}", &line[..at], &line[at + 1..])
        } else {
            format!("{} 1", line)
        };
        let tokens = lexer::lex(&(text + "\n")).remove(0).tokens;
        processor.define(&tokens, &Position {
            file: "defines.txt".into(),
            line: (i + 1) as i64
        }, false);
    }
    processor.marker("main.c", 1, "");
    processor.process("main.c", 0);
    processor.reports();
}
