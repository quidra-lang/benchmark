use std::fs;

pub struct Block {
    pub kind: String,
    pub argument: String,
    pub term: String,
    pub columns: String,
    pub body: Vec<(usize, String)>,
    pub inner: Vec<(usize, String)>,
    pub width: usize,
    pub indent: usize,
    pub align: String,
    pub line: usize,
    pub page_break: bool,
    pub label: Option<String>,
    pub number: String,
}

pub struct Bibliography {
    pub line: usize,
    pub key: String,
    pub author: String,
    pub year: String,
    pub title: String,
    pub cited: bool,
    pub label: String,
}

pub struct Document {
    pub blocks: Vec<Block>,
    pub bibliography: Vec<Bibliography>,
    pub additions: Vec<String>,
    pub warnings: Vec<(usize, String)>,
    pub width: usize,
    pub height: usize,
    pub header: [String; 3],
    pub footer: [String; 3],
}

fn integer(text: &str, low: usize, high: usize) -> bool {
    !text.is_empty() && text.len() <= 9 && text.bytes().all(|b| b.is_ascii_digit()) && text.parse::<usize>().is_ok_and(|v| (low..=high).contains(&v))
}

fn hyphenated(text: &str) -> bool {
    !text.is_empty() && !text.starts_with('-') && !text.ends_with('-') && !text.contains("--") && text.bytes().all(|b| b.is_ascii_lowercase() || b == b'-')
}

fn valid(name: &str, argument: &str) -> bool {
    match name {
        "width" => integer(argument, 20, 80), "indent" => integer(argument, 0, 8), "page" => integer(argument, 10, 100),
        "align" => ["left", "right", "center", "justify"].contains(&argument),
        "header" | "footer" => argument.bytes().filter(|&b| b == b'|').count() == 2,
        "newpage" | "verbatim" | "toc" | "lot" | "index" | "bibliography" => argument.is_empty(),
        "hyphenation" => argument.split(' ').all(hyphenated),
        "bib" => {
            let Some((key, rest)) = argument.split_once(' ') else { return false; };
            let parts: Vec<_> = rest.split('|').collect();
            !key.is_empty() && key.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit()) && parts.len() == 3 && !parts[0].is_empty() && parts[1].len() == 4 && parts[1].bytes().all(|b| b.is_ascii_digit()) && !parts[2].is_empty()
        }
        "term" => argument.split_once('|').is_some_and(|(a, b)| !a.is_empty() && !b.is_empty()),
        "table" => {
            let columns = argument.split(' ').next().unwrap();
            !columns.is_empty() && columns.bytes().all(|b| b"lrc".contains(&b))
        }
        _ => !argument.is_empty(),
    }
}

fn new_block(kind: &str, argument: &str, line: usize, width: usize, indent: usize, align: &str, page_break: bool) -> Block {
    let mut block = Block {
        kind: kind.into(), argument: argument.into(), term: String::new(), columns: String::new(),
        body: Vec::new(), inner: Vec::new(), width, indent, align: align.into(), line, page_break, label: None, number: String::new(),
    };
    if ["item", "enum", "quote"].contains(&kind) { block.body.push((line, argument.into())); }
    if kind == "term" {
        let (term, body) = argument.split_once('|').unwrap();
        block.term = term.into();
        block.body.push((line, body.into()));
    }
    if kind == "table" {
        let (columns, caption) = argument.split_once(' ').unwrap_or((argument, ""));
        block.columns = columns.into();
        block.argument = caption.into();
    }
    if ["h1", "h2", "table"].contains(&kind) && block.argument.ends_with('}') {
        if let Some(start) = block.argument.rfind(" {#") {
            block.label = Some(block.argument[start + 3..block.argument.len() - 1].into());
            block.argument.truncate(start);
        }
    }
    block
}

pub fn read() -> Document {
    let text = fs::read_to_string("input/document.txt").unwrap();
    let lines: Vec<_> = text.lines().collect();
    let mut document = Document { blocks: Vec::new(), bibliography: Vec::new(), additions: Vec::new(), warnings: Vec::new(), width: 60, height: 40, header: std::array::from_fn(|_| String::new()), footer: std::array::from_fn(|_| String::new()) };
    let (mut width, mut indent) = (60, 0);
    let mut align = String::from("left");
    let mut accepted = Vec::new();
    let mut pending = false;
    let mut open: Option<usize> = None;
    let mut i = 0;
    let names = ["width", "indent", "align", "page", "header", "footer", "newpage", "hyphenation", "bib", "title", "author", "h1", "h2", "item", "enum", "quote", "term", "table", "verbatim", "toc", "lot", "index", "bibliography"];
    while i < lines.len() {
        let line = lines[i];
        let line_number = i + 1;
        if line.is_empty() { open = None; i += 1; continue; }
        if !line.starts_with('.') {
            let index = if let Some(index) = open { index } else {
                if document.blocks.is_empty() { document.width = width; }
                document.blocks.push(new_block("paragraph", "", line_number, width, indent, &align, pending));
                pending = false;
                let index = document.blocks.len() - 1;
                open = Some(index);
                index
            };
            document.blocks[index].body.push((line_number, line.into()));
            i += 1;
            continue;
        }
        open = None;
        let (name, argument) = line[1..].split_once(' ').unwrap_or((&line[1..], ""));
        let preamble = ["page", "header", "footer"].contains(&name);
        let warning = if !names.contains(&name) { Some(format!("unknown directive .{name}")) }
            else if !valid(name, argument) { Some(format!("bad argument for .{name}")) }
            else if preamble && !document.blocks.is_empty() { Some(format!(".{name} ignored after the preamble")) }
            else if preamble && accepted.contains(&name) { Some(format!("duplicate .{name}")) }
            else { None };
        if let Some(warning) = warning { document.warnings.push((line_number, warning)); i += 1; continue; }
        if preamble { accepted.push(name); }
        match name {
            "width" => width = argument.parse().unwrap(), "indent" => indent = argument.parse().unwrap(), "align" => align = argument.into(),
            "page" => document.height = argument.parse().unwrap(),
            "header" => document.header = argument.split('|').map(String::from).collect::<Vec<_>>().try_into().ok().unwrap(),
            "footer" => document.footer = argument.split('|').map(String::from).collect::<Vec<_>>().try_into().ok().unwrap(),
            "newpage" => pending = true,
            "hyphenation" => document.additions.extend(argument.split(' ').map(String::from)),
            "bib" => {
                let (key, rest) = argument.split_once(' ').unwrap();
                let parts: Vec<_> = rest.split('|').collect();
                document.bibliography.push(Bibliography { line: line_number, key: key.into(), author: parts[0].into(), year: parts[1].into(), title: parts[2].into(), cited: false, label: String::new() });
            }
            _ => {
                if document.blocks.is_empty() { document.width = width; }
                let mut block = new_block(name, argument, line_number, width, indent, &align, pending);
                pending = false;
                if name == "table" || name == "verbatim" {
                    i += 1;
                    while i < lines.len() && lines[i] != ".end" {
                        block.inner.push((i + 1, lines[i].into()));
                        i += 1;
                    }
                    if i == lines.len() { document.warnings.push((line_number, format!("unterminated {name}"))); }
                }
                document.blocks.push(block);
                if ["item", "enum", "quote", "term"].contains(&name) { open = Some(document.blocks.len() - 1); }
            }
        }
        i += 1;
    }
    document
}
