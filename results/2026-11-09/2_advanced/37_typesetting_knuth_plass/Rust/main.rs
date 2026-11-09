mod document_parser;
mod hyphenation;
mod line_breaker;
mod page_builder;
mod renderer;

use document_parser::Document;
use hyphenation::Dictionary;
use page_builder::Page;
use std::collections::{BTreeMap, BTreeSet};
use std::fs;

#[derive(Clone)]
pub struct Metric {
    pieces: Vec<String>,
    ranges: Vec<(usize, usize, usize)>,
    slack: i64,
}

#[derive(Clone)]
pub struct LayoutLine {
    text: String,
    footnotes: Vec<usize>,
    indexes: Vec<usize>,
    first_block: Option<usize>,
}

impl LayoutLine {
    pub fn empty() -> Self { Self { text: String::new(), footnotes: Vec::new(), indexes: Vec::new(), first_block: None } }
    fn text(text: String) -> Self { Self { text, ..Self::empty() } }
}

pub struct LayoutBlock {
    lines: Vec<LayoutLine>,
    kind: &'static str,
    list: bool,
    page_break: bool,
}

#[derive(Clone)]
enum Inline {
    Text(String),
    Reference(String),
    Page(String),
    Footnote(usize),
    Index(usize),
    Cite(Vec<String>),
}

struct Prepared {
    document: Document,
    tokens: Vec<Vec<Inline>>,
    tables: Vec<Vec<Vec<String>>>,
    labels: BTreeMap<String, usize>,
    bibliography_order: Vec<usize>,
    footnotes: Vec<String>,
    indexes: Vec<String>,
    body_numbers: Vec<Option<usize>>,
}

fn body(kind: &str) -> bool { ["paragraph", "item", "enum", "quote", "term"].contains(&kind) }

fn prepare() -> Prepared {
    let mut document = document_parser::read();
    let mut labels = BTreeMap::new();
    let (mut chapter, mut section, mut table, mut body_number) = (0, 0, 0, 0);
    let mut body_numbers = Vec::new();
    for i in 0..document.blocks.len() {
        let previous_kind = if i == 0 { "".into() } else { document.blocks[i - 1].kind.clone() };
        let previous_number = if i == 0 { 0 } else { document.blocks[i - 1].number.parse::<usize>().unwrap_or(0) };
        let block = &mut document.blocks[i];
        match block.kind.as_str() {
            "h1" => { chapter += 1; section = 0; block.number = chapter.to_string(); if i > 0 { block.page_break = true; } }
            "h2" => { section += 1; block.number = format!("{chapter}.{section}"); }
            "enum" => block.number = (if previous_kind == "enum" { previous_number + 1 } else { 1 }).to_string(),
            "table" if !block.argument.is_empty() => { table += 1; block.number = table.to_string(); }
            "paragraph" if previous_kind == "h1" || previous_kind == "h2" => block.indent = 0,
            _ => (),
        }
        if let Some(label) = block.label.clone() {
            if labels.contains_key(&label) {
                document.warnings.push((block.line, format!("duplicate label {label}")));
                block.label = None;
            } else { labels.insert(label, i); }
        }
        body_numbers.push(if body(&block.kind) { body_number += 1; Some(body_number) } else { None });
    }
    let mut registered = BTreeSet::new();
    let mut bibliography = Vec::new();
    for entry in std::mem::take(&mut document.bibliography) {
        if registered.insert(entry.key.clone()) { bibliography.push(entry); }
        else { document.warnings.push((entry.line, format!("duplicate bibliography key {}", entry.key))); }
    }
    document.bibliography = bibliography;
    let mut footnotes = Vec::new();
    let mut indexes = Vec::new();
    let mut tokens = vec![Vec::new(); document.blocks.len()];
    let mut tables = vec![Vec::new(); document.blocks.len()];
    for i in 0..document.blocks.len() {
        let block = &document.blocks[i];
        if block.kind == "table" {
            for (line, text) in &block.inner {
                let mut cells: Vec<_> = text.split('|').map(|cell| cell.trim().to_string()).collect();
                if cells.len() != block.columns.len() {
                    document.warnings.push((*line, format!("table row has {} cells, expected {}", cells.len(), block.columns.len())));
                    cells.resize(block.columns.len(), String::new());
                    cells.truncate(block.columns.len());
                }
                tables[i].push(cells);
            }
            let lines = renderer::table(&tables[i], &block.columns, &block.argument, &block.number);
            let longest = lines.iter().map(String::len).max().unwrap();
            if longest > block.width { document.warnings.push((block.line, format!("table too wide by {}", longest - block.width))); }
        } else if block.kind == "verbatim" {
            for (line, text) in &block.inner {
                if text.len() > block.width { document.warnings.push((*line, format!("verbatim line too long by {}", text.len() - block.width))); }
            }
        } else if body(&block.kind) {
            let body_lines = block.body.clone();
            for (j, (line, text)) in body_lines.iter().enumerate() {
                if j > 0 { tokens[i].push(Inline::Text(" ".into())); }
                let mut remainder = text.as_str();
                loop {
                    let Some(start) = remainder.find('{') else { tokens[i].push(Inline::Text(remainder.into())); break; };
                    tokens[i].push(Inline::Text(remainder[..start].into()));
                    let Some(relative_end) = remainder[start + 1..].find('}') else {
                        document.warnings.push((*line, "unclosed brace".into()));
                        tokens[i].push(Inline::Text(remainder[start..].into()));
                        break;
                    };
                    let end = start + 1 + relative_end;
                    let content = &remainder[start + 1..end];
                    let (name, argument) = content.split_once(':').unwrap_or((content, ""));
                    if !["ref", "page", "fn", "idx", "cite"].contains(&name) || argument.is_empty() {
                        document.warnings.push((*line, format!("bad command {{{content}}}")));
                    } else {
                        let command = match name {
                            "ref" | "page" => {
                                if !labels.contains_key(argument) { document.warnings.push((*line, format!("undefined label {argument}"))); }
                                if name == "ref" { Inline::Reference(argument.into()) } else { Inline::Page(argument.into()) }
                            }
                            "fn" => { let id = footnotes.len(); footnotes.push(argument.into()); Inline::Footnote(id) }
                            "idx" => { let id = indexes.len(); indexes.push(argument.into()); Inline::Index(id) }
                            "cite" => {
                                let keys: Vec<_> = argument.split(',').map(String::from).collect();
                                for key in &keys {
                                    if let Some(entry) = document.bibliography.iter_mut().find(|entry| &entry.key == key) { entry.cited = true; }
                                    else { document.warnings.push((*line, format!("undefined citation {key}"))); }
                                }
                                Inline::Cite(keys)
                            }
                            _ => unreachable!(),
                        };
                        tokens[i].push(command);
                    }
                    remainder = &remainder[end + 1..];
                }
            }
        }
    }
    for entry in &document.bibliography {
        if !entry.cited { document.warnings.push((entry.line, format!("unused bibliography entry {}", entry.key))); }
    }
    document.warnings.sort_by_key(|warning| warning.0);
    for entry in document.bibliography.iter_mut().filter(|entry| entry.cited) {
        let names: Vec<_> = entry.author.split(" and ").collect();
        let mut base = if names.len() == 1 { names[0].chars().take(3).collect::<String>() }
            else if names.len() <= 4 { names.iter().map(|name| name.chars().next().unwrap()).collect() }
            else { format!("{}+", names[..3].iter().map(|name| name.chars().next().unwrap()).collect::<String>()) };
        base.push_str(&entry.year[2..]);
        entry.label = base;
    }
    let mut bibliography_order: Vec<_> = document.bibliography.iter().enumerate().filter(|(_, entry)| entry.cited).map(|(i, _)| i).collect();
    bibliography_order.sort_by(|&a, &b| {
        let a = &document.bibliography[a];
        let b = &document.bibliography[b];
        (&a.label, &a.author, &a.title, &a.key).cmp(&(&b.label, &b.author, &b.title, &b.key))
    });
    let bases: Vec<_> = bibliography_order.iter().map(|&i| document.bibliography[i].label.clone()).collect();
    for (position, &i) in bibliography_order.iter().enumerate() {
        let base = &bases[position];
        if bases.iter().filter(|other| *other == base).count() > 1 {
            let suffix = bases[..position].iter().filter(|other| *other == base).count();
            document.bibliography[i].label.push((b'a' + suffix as u8) as char);
        }
    }
    Prepared { document, tokens, tables, labels, bibliography_order, footnotes, indexes, body_numbers }
}

#[derive(Clone)]
struct Breakpoint {
    word: usize,
    position: usize,
    middle: bool,
    dictionary: bool,
}

struct Mark {
    word: usize,
    position: usize,
    id: usize,
    footnote: bool,
}

fn expand(prepared: &Prepared, index: usize, values: &BTreeMap<String, String>) -> (Vec<String>, Vec<Mark>) {
    let mut text = String::new();
    let mut offsets = Vec::new();
    for token in &prepared.tokens[index] {
        match token {
            Inline::Text(part) => text.push_str(part),
            Inline::Reference(label) => text.push_str(&prepared.labels.get(label).map_or_else(|| "??".into(), |&i| prepared.document.blocks[i].number.clone())),
            Inline::Page(label) => text.push_str(values.get(label).map_or("??", String::as_str)),
            Inline::Footnote(id) => { offsets.push((text.len(), *id, true)); text.push_str(&format!("[{}]", id + 1)); }
            Inline::Index(id) => offsets.push((text.len() - 1, *id, false)),
            Inline::Cite(keys) => {
                let mut labels = BTreeSet::new();
                let mut missing = false;
                for key in keys {
                    if let Some(entry) = prepared.document.bibliography.iter().find(|entry| &entry.key == key) { labels.insert(entry.label.clone()); }
                    else { missing = true; }
                }
                let mut labels: Vec<_> = labels.into_iter().collect();
                if missing { labels.push("?".into()); }
                text.push_str(&format!("[{}]", labels.join(", ")));
            }
        }
    }
    let mut words = Vec::new();
    let mut starts = Vec::new();
    let mut offset = 0;
    for part in text.split(' ') {
        if !part.is_empty() { words.push(part.to_string()); starts.push(offset); }
        offset += part.len() + 1;
    }
    let marks = offsets.into_iter().map(|(offset, id, footnote)| {
        let word = starts.iter().enumerate().find(|&(i, &start)| start <= offset && offset < start + words[i].len()).unwrap().0;
        Mark { word, position: offset - starts[word], id, footnote }
    }).collect();
    (words, marks)
}

fn measure(words: &[String], points: &[Breakpoint], a: usize, b: usize, first: usize, later: usize) -> Metric {
    let start_word = if a == 0 { 0 } else { points[a].word + usize::from(!points[a].middle) };
    let start_position = if a == 0 || !points[a].middle { 0 } else { points[a].position };
    let mut pieces = Vec::new();
    let mut ranges = Vec::new();
    for word in start_word..=points[b].word {
        let start = if word == start_word { start_position } else { 0 };
        let end = if word == points[b].word { points[b].position } else { words[word].len() };
        pieces.push(words[word][start..end].to_string());
        ranges.push((word, start, end));
    }
    if points[b].dictionary { pieces.last_mut().unwrap().push('-'); }
    let length = pieces.iter().map(String::len).sum::<usize>() + pieces.len() - 1;
    Metric { pieces, ranges, slack: if a == 0 { first } else { later } as i64 - length as i64 }
}

struct Broken {
    lines: Vec<LayoutLine>,
    warnings: Vec<String>,
    count: usize,
    cost: i64,
    hyphenated: usize,
}

fn break_text(words: &[String], marks: &[Mark], first: usize, later: usize, prefixes: (&str, &str), alignment: &str, name: &str, body_block: bool, dictionary: &Dictionary, params: &BTreeMap<String, i64>, greedy: bool) -> Broken {
    let mut points = vec![Breakpoint { word: 0, position: 0, middle: false, dictionary: false }];
    for (word, text) in words.iter().enumerate() {
        for (position, dictionary) in dictionary.splits(text) { points.push(Breakpoint { word, position, middle: true, dictionary }); }
        points.push(Breakpoint { word, position: text.len(), middle: false, dictionary: false });
    }
    let m = points.len() - 1;
    let mut metrics = vec![vec![None; m + 1]; m + 1];
    for a in 0..m {
        for b in a + 1..=m {
            let metric = measure(words, &points, a, b, first, later);
            if metric.slack >= 0 || b == a + 1 { metrics[a][b] = Some(metric); }
        }
    }
    let middle: Vec<_> = points.iter().map(|p| p.middle).collect();
    let (breaking, cost) = line_breaker::breaking(&metrics, &middle, params, greedy);
    let mut lines = Vec::new();
    let mut warnings = Vec::new();
    let mut hyphenated = 0;
    let mut a = 0;
    for (index, &b) in breaking.iter().enumerate() {
        let metric = metrics[a][b].as_ref().unwrap();
        let text = renderer::line(metric, alignment, b == m, if a == 0 { prefixes.0 } else { prefixes.1 });
        let mut line = LayoutLine::text(text);
        for mark in marks {
            if metric.ranges.iter().any(|&(word, start, end)| mark.word == word && start <= mark.position && mark.position < end) {
                if mark.footnote { line.footnotes.push(mark.id); } else { line.indexes.push(mark.id); }
            }
        }
        if metric.slack < 0 { warnings.push(format!("{name} line {}: overfull by {}", index + 1, -metric.slack)); }
        else if body_block && alignment == "justify" && b != m && metric.slack >= params["underfull_slack"] {
            warnings.push(format!("{name} line {}: underfull, slack {}", index + 1, metric.slack));
        }
        if points[b].middle { hyphenated += 1; }
        lines.push(line);
        a = b;
    }
    Broken { count: breaking.len(), lines, warnings, cost, hyphenated }
}

fn words(text: &str) -> Vec<String> { text.split(' ').filter(|part| !part.is_empty()).map(String::from).collect() }

fn entry(left: &str, number: &str, width: usize) -> String {
    format!("{} {} {}", left, ".".repeat(width - left.len() - number.len() - 2), number)
}

#[derive(Default)]
struct IndexEntry {
    pages: BTreeSet<i64>,
    references: BTreeSet<String>,
}

fn page_list(pages: &BTreeSet<i64>) -> String {
    let values: Vec<_> = pages.iter().copied().collect();
    let mut output = Vec::new();
    let mut i = 0;
    while i < values.len() {
        let mut end = i;
        while end + 1 < values.len() && values[end + 1] == values[end] + 1 { end += 1; }
        if end - i >= 2 { output.push(format!("{}-{}", values[i], values[end])); }
        else { output.extend(values[i..=end].iter().map(i64::to_string)); }
        i = end + 1;
    }
    output.join(", ")
}

fn index_lines(prepared: &Prepared, pages: &BTreeMap<usize, i64>) -> Vec<String> {
    let mut entries: BTreeMap<String, BTreeMap<String, IndexEntry>> = BTreeMap::new();
    for (id, phrase) in prepared.indexes.iter().enumerate() {
        let (entry, reference) = phrase.split_once('|').map_or((phrase.as_str(), None), |(a, b)| (a, Some(b)));
        let (parent, child) = entry.split_once('!').unwrap_or((entry, ""));
        let children = entries.entry(parent.into()).or_default();
        children.entry(String::new()).or_default();
        let target = children.entry(child.into()).or_default();
        if let Some(reference) = reference { target.references.insert(reference.into()); }
        else { target.pages.insert(*pages.get(&id).unwrap_or(&1)); }
    }
    let mut parents: Vec<_> = entries.into_iter().collect();
    parents.sort_by_key(|(name, _)| (name.to_ascii_lowercase(), name.clone()));
    let mut output = Vec::new();
    let mut previous_group = String::new();
    for (parent, children) in parents {
        let first = parent.as_bytes()[0];
        let group = if first.is_ascii_alphabetic() { (first.to_ascii_uppercase() as char).to_string() } else { "Symbols".into() };
        if group != previous_group { output.push(group.clone()); previous_group = group; }
        let mut children: Vec<_> = children.into_iter().collect();
        children.sort_by_key(|(name, _)| (name.to_ascii_lowercase(), name.clone()));
        for (child, entry) in children {
            let mut line = if child.is_empty() { parent.clone() } else { format!("  {child}") };
            if !entry.pages.is_empty() { line.push_str(&format!(", {}", page_list(&entry.pages))); }
            if !entry.references.is_empty() { line.push_str(&format!(", see {}", entry.references.into_iter().collect::<Vec<_>>().join(", "))); }
            output.push(line);
        }
    }
    output
}

struct Assembly {
    blocks: Vec<LayoutBlock>,
    footnotes: Vec<Vec<String>>,
    warnings: Vec<String>,
    stats: Vec<(usize, i64)>,
    hyphenated: usize,
}

fn layout_block(lines: Vec<LayoutLine>, kind: &'static str, list: bool) -> LayoutBlock {
    LayoutBlock { lines, kind, list, page_break: false }
}

fn assemble(prepared: &Prepared, dictionary: &Dictionary, params: &BTreeMap<String, i64>, greedy: bool, values: &BTreeMap<String, String>, block_pages: &BTreeMap<usize, String>, index_pages: &BTreeMap<usize, i64>) -> Assembly {
    let document = &prepared.document;
    let mut result = Assembly { blocks: Vec::new(), footnotes: Vec::new(), warnings: Vec::new(), stats: Vec::new(), hyphenated: 0 };
    for (index, block) in document.blocks.iter().enumerate() {
        let begin = result.blocks.len();
        if body(&block.kind) {
            let (words, marks) = expand(prepared, index, values);
            let spaces = |n| " ".repeat(n);
            let (first, later, prefix, continuation) = match block.kind.as_str() {
                "paragraph" => (block.width - block.indent, block.width, spaces(block.indent), String::new()),
                "item" => (block.width - 2, block.width - 2, "- ".into(), spaces(2)),
                "enum" => (block.width - 4, block.width - 4, format!("{:>2}. ", block.number), spaces(4)),
                "quote" => (block.width - 8, block.width - 8, spaces(4), spaces(4)),
                "term" => (block.width - 12, block.width - 12, if block.term.len() <= 10 { format!("{:12}", block.term) } else { spaces(12) }, spaces(12)),
                _ => unreachable!(),
            };
            let number = prepared.body_numbers[index].unwrap();
            let mut broken = break_text(&words, &marks, first, later, (&prefix, &continuation), &block.align, &format!("paragraph {number}"), true, dictionary, params, greedy);
            result.stats.push((broken.count, broken.cost));
            result.hyphenated += broken.hyphenated;
            result.warnings.extend(broken.warnings);
            if block.kind == "term" && block.term.len() >= 11 { broken.lines.insert(0, LayoutLine::text(block.term.clone())); }
            result.blocks.push(layout_block(broken.lines, "flow", ["item", "enum", "term"].contains(&block.kind.as_str())));
        } else {
            match block.kind.as_str() {
                "title" | "author" => {
                    let text = if block.kind == "title" { block.argument.to_ascii_uppercase() } else { block.argument.clone() };
                    result.blocks.push(layout_block(vec![LayoutLine::text(format!("{}{}", " ".repeat((block.width - text.len()) / 2), text))], "heading", false));
                }
                "h1" | "h2" => {
                    let text = format!("{} {}", block.number, if block.kind == "h1" { block.argument.to_ascii_uppercase() } else { block.argument.clone() });
                    let underline = if block.kind == "h1" { "=" } else { "-" }.repeat(text.len());
                    result.blocks.push(layout_block(vec![LayoutLine::text(text), LayoutLine::text(underline)], "heading", false));
                }
                "table" => result.blocks.push(layout_block(renderer::table(&prepared.tables[index], &block.columns, &block.argument, &block.number).into_iter().map(LayoutLine::text).collect(), "solid", false)),
                "verbatim" => result.blocks.push(layout_block(block.inner.iter().map(|(_, text)| LayoutLine::text(text.clone())).collect(), "flow", false)),
                "toc" | "lot" | "index" => {
                    let (heading, underline) = match block.kind.as_str() { "toc" => ("CONTENTS", "========"), "lot" => ("TABLES", "======"), _ => ("INDEX", "=====") };
                    result.blocks.push(layout_block(vec![LayoutLine::text(heading.into()), LayoutLine::text(underline.into())], "heading", false));
                    let lines = if block.kind == "index" { index_lines(prepared, index_pages) } else {
                        document.blocks.iter().enumerate().filter(|(_, b)| if block.kind == "toc" { b.kind == "h1" || b.kind == "h2" } else { b.kind == "table" && !b.number.is_empty() }).map(|(i, b)| {
                            let left = if block.kind == "lot" { format!("Table {}. {}", b.number, b.argument) } else { format!("{}{} {}", if b.kind == "h2" { "  " } else { "" }, b.number, b.argument) };
                            entry(&left, block_pages.get(&i).map_or("??", String::as_str), block.width)
                        }).collect()
                    };
                    result.blocks.push(layout_block(lines.into_iter().map(LayoutLine::text).collect(), "flow", false));
                }
                "bibliography" => {
                    result.blocks.push(layout_block(vec![LayoutLine::text("REFERENCES".into()), LayoutLine::text("==========".into())], "heading", false));
                    let width = prepared.bibliography_order.iter().map(|&i| document.bibliography[i].label.len()).max().unwrap() + 3;
                    for &i in &prepared.bibliography_order {
                        let entry = &document.bibliography[i];
                        let text = format!("{}. {}. {}", entry.author, entry.year, entry.title);
                        let prefix = format!("{:<width$}", format!("[{}]", entry.label));
                        let continuation = " ".repeat(width);
                        let broken = break_text(&words(&text), &[], block.width - width, block.width - width, (&prefix, &continuation), "left", &format!("reference {}", entry.label), false, dictionary, params, greedy);
                        result.warnings.extend(broken.warnings);
                        result.blocks.push(layout_block(broken.lines, "flow", true));
                    }
                }
                _ => unreachable!(),
            }
        }
        result.blocks[begin].page_break = block.page_break;
        result.blocks[begin].lines[0].first_block = Some(index);
    }
    for (index, text) in prepared.footnotes.iter().enumerate() {
        let prefix = format!("[{}] ", index + 1);
        let continuation = " ".repeat(prefix.len());
        let broken = break_text(&words(text), &[], document.width - prefix.len(), document.width - prefix.len(), (&prefix, &continuation), "left", &format!("footnote {}", index + 1), false, dictionary, params, greedy);
        result.warnings.extend(broken.warnings);
        result.footnotes.push(broken.lines.into_iter().map(|line| line.text).collect());
    }
    result
}

fn numbered_pages(prepared: &Prepared, lines: &[LayoutLine], pages: Vec<Page>) -> (Vec<Page>, usize) {
    let mut result = Vec::new();
    let mut front = None;
    for page in pages {
        let chapter = page.lines.first().and_then(|&i| lines[i].first_block).is_some_and(|i| prepared.document.blocks[i].kind == "h1");
        if chapter && (result.len() + 1) % 2 == 0 { result.push(Page { lines: Vec::new(), footnotes: Vec::new(), height: 0, forced: true, blank: true }); }
        if chapter && front.is_none() { front = Some(result.len()); }
        result.push(page);
    }
    (result, front.unwrap_or(0))
}

fn display(serial: usize, front: usize) -> String {
    if serial > front { return (serial - front).to_string(); }
    let small = ["", "i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix"];
    format!("{}{}", "x".repeat(serial / 10), small[serial % 10])
}

fn page_maps(prepared: &Prepared, lines: &[LayoutLine], pages: &[Page], front: usize) -> (BTreeMap<String, String>, BTreeMap<usize, String>, BTreeMap<usize, i64>) {
    let mut values = BTreeMap::new();
    let mut block_pages = BTreeMap::new();
    let mut index_pages = BTreeMap::new();
    for (index, page) in pages.iter().enumerate() {
        let serial = index + 1;
        for &line in &page.lines {
            if let Some(block) = lines[line].first_block {
                block_pages.insert(block, display(serial, front));
                if let Some(label) = &prepared.document.blocks[block].label { values.insert(label.clone(), display(serial, front)); }
            }
            for &id in &lines[line].indexes { index_pages.insert(id, serial as i64 - front as i64); }
        }
    }
    (values, block_pages, index_pages)
}

struct LayoutResult {
    output: Vec<String>,
    warnings: Vec<String>,
    stats: Vec<(usize, i64)>,
}

fn layout(prepared: &Prepared, dictionary: &Dictionary, params: &BTreeMap<String, i64>, greedy: bool) -> LayoutResult {
    let mut values: BTreeMap<_, _> = prepared.labels.keys().map(|label| (label.clone(), "??".into())).collect();
    let mut block_pages = BTreeMap::new();
    let mut index_pages = BTreeMap::new();
    loop {
        let assembly = assemble(prepared, dictionary, params, greedy, &values, &block_pages, &index_pages);
        let (lines, pages) = page_builder::build(&assembly.blocks, &assembly.footnotes, prepared.document.height, params["orphan_lines"] as usize, params["widow_lines"] as usize);
        let (pages, front) = numbered_pages(prepared, &lines, pages);
        let (computed, computed_blocks, computed_indexes) = page_maps(prepared, &lines, &pages, front);
        let stable = computed == values;
        values = computed;
        block_pages = computed_blocks;
        index_pages = computed_indexes;
        if !stable { continue; }
        let assembly = assemble(prepared, dictionary, params, greedy, &values, &block_pages, &index_pages);
        let (lines, pages) = page_builder::build(&assembly.blocks, &assembly.footnotes, prepared.document.height, params["orphan_lines"] as usize, params["widow_lines"] as usize);
        let (pages, front) = numbered_pages(prepared, &lines, pages);
        let mut warnings = assembly.warnings;
        let mut output_pages = Vec::new();
        let (mut chapter, mut section) = (String::new(), String::new());
        for (index, page) in pages.iter().enumerate() {
            if page.blank { output_pages.push((String::new(), vec![String::new(); prepared.document.height], String::new())); continue; }
            for &line in &page.lines {
                if let Some(i) = lines[line].first_block {
                    let block = &prepared.document.blocks[i];
                    if block.kind == "h1" { chapter = format!("{} {}", block.number, block.argument); section.clear(); }
                    if block.kind == "h2" { section = format!("{} {}", block.number, block.argument); }
                }
            }
            let replacements = [("{page}", display(index + 1, front)), ("{pages}", (pages.len() - front).to_string()), ("{chapter}", chapter.clone()), ("{section}", section.clone())];
            let chapter_start = page.lines.first().and_then(|&line| lines[line].first_block).is_some_and(|i| prepared.document.blocks[i].kind == "h1");
            let header = if chapter_start { String::new() } else { renderer::running(&prepared.document.header, &replacements, prepared.document.width, (index + 1) % 2 == 0) };
            let footer = renderer::running(&prepared.document.footer, &replacements, prepared.document.width, (index + 1) % 2 == 0);
            let mut body: Vec<_> = page.lines.iter().map(|&line| lines[line].text.clone()).collect();
            let mut footnote_lines = Vec::new();
            if !page.footnotes.is_empty() {
                footnote_lines.push("----------".into());
                for &id in &page.footnotes { footnote_lines.extend(assembly.footnotes[id].clone()); }
            }
            body.resize(prepared.document.height - footnote_lines.len(), String::new());
            body.extend(footnote_lines);
            output_pages.push((header, body, footer));
            if !page.forced && prepared.document.height - page.height >= params["underfull_page"] as usize {
                warnings.push(format!("page {}: underfull, {} empty lines", index + 1, prepared.document.height - page.height));
            }
        }
        warnings.push(format!("{} pages, {} hyphenated lines", pages.len(), assembly.hyphenated));
        let prefix = if greedy { "greedy" } else { "kp" };
        return LayoutResult { output: renderer::pages(&output_pages), warnings: warnings.into_iter().map(|warning| format!("{prefix}: {warning}")).collect(), stats: assembly.stats };
    }
}

fn write(name: &str, lines: &[String]) {
    let text = if lines.is_empty() { String::new() } else { format!("{}\n", lines.join("\n")) };
    fs::write(format!("output/{name}"), text).unwrap();
}

fn main() {
    let params: BTreeMap<String, i64> = fs::read_to_string("input/params.txt").unwrap().lines().map(|line| {
        let (key, value) = line.split_once(' ').unwrap();
        (key.into(), value.parse().unwrap())
    }).collect();
    let prepared = prepare();
    let dictionary = Dictionary::read(&prepared.document.additions, params["left_min"] as usize, params["right_min"] as usize);
    let kp = layout(&prepared, &dictionary, &params, false);
    let greedy = layout(&prepared, &dictionary, &params, true);
    let mut stats = vec!["paragraph,lines_kp,cost_kp,lines_greedy,cost_greedy".into()];
    let mut totals = [0_i64; 4];
    for (i, (&(kp_lines, kp_cost), &(greedy_lines, greedy_cost))) in kp.stats.iter().zip(&greedy.stats).enumerate() {
        stats.push(format!("{},{},{},{},{}", i + 1, kp_lines, kp_cost, greedy_lines, greedy_cost));
        for (total, value) in totals.iter_mut().zip([kp_lines as i64, kp_cost, greedy_lines as i64, greedy_cost]) { *total += value; }
    }
    stats.push(format!("total,{},{},{},{}", totals[0], totals[1], totals[2], totals[3]));
    let mut log: Vec<_> = prepared.document.warnings.iter().map(|(line, warning)| format!("line {line}: {warning}")).collect();
    log.extend(kp.warnings);
    log.extend(greedy.warnings);
    fs::create_dir_all("output").unwrap();
    write("pages.txt", &kp.output);
    write("greedy_pages.txt", &greedy.output);
    write("stats.csv", &stats);
    write("log.txt", &log);
}
