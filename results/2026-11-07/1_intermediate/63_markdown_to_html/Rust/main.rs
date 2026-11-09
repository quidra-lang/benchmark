use std::collections::{HashMap, HashSet};
use std::io::{self, Read};
const TOC: &str = "\x01toc\x02";

fn trim(s: &str) -> &str {
    s.trim_matches(' ')
}

fn white(c: u8) -> bool {
    c == b' ' || c == b'\n'
}

fn label(c: u8) -> bool {
    c.is_ascii_alphanumeric() || c == b'-' || c == b'_'
}

fn escape(s: &str) -> String {
    let mut result = String::new();
    for c in s.chars() {
        match c {
            '&' => result.push_str("&amp;"), '<' => result.push_str("&lt;"), '>' => result.push_str("&gt;"), '"' => result.push_str("&quot;"), _ => result.push(c),
        }
    }
    result
}

fn strip_tags(s: &str) -> String {
    let mut result = String::new();
    let mut at = 0;
    while at < s.len() {
        if s.as_bytes()[at] == b'<' {
            if let Some(end) = s[at..].find('>') {
                at += end + 1;
                continue;
            }
        }
        result.push(s.as_bytes()[at] as char);
        at += 1;
    }
    result
}

fn normalize(s: &str) -> String {
    s.split([' ', '\n']).filter(|p| !p.is_empty()).collect::<Vec<_>>().join(" ").to_ascii_lowercase()
}

fn skip(s: &str, mut at: usize) -> usize {
    while at < s.len() && white(s.as_bytes()[at]) {
        at += 1;
    }
    at
}

fn escaped_read(s: &str, mut at: usize, stops: &[u8]) -> (String, usize) {
    let b = s.as_bytes();
    let mut result = String::new();
    while at < b.len() && !stops.contains(&b[at]) {
        if b[at] == b'\\' && at + 1 < b.len() && b[at + 1].is_ascii_punctuation() {
            at += 1;
        }
        result.push(b[at] as char);
        at += 1;
    }
    (result, at)
}

fn run_end(s: &str, mut at: usize) -> usize {
    let c = s.as_bytes()[at];
    while at < s.len() && s.as_bytes()[at] == c {
        at += 1;
    }
    at
}

fn tick_closer(s: &str, mut at: usize, length: usize) -> Option<usize> {
    while at < s.len() {
        at += s[at..].find('`')?;
        let end = run_end(s, at);
        if end - at == length {
            return Some(at);
        }
        at = end;
    }
    None
}

fn closing_bracket(s: &str, mut at: usize) -> Option<usize> {
    let mut depth = 0;
    while at < s.len() {
        match s.as_bytes()[at] {
            b'\\' => {
                at += 2;
                continue;
            }
            b'`' => {
                let end = run_end(s, at);
                at = tick_closer(s, end, end - at).map_or(end, |c| c + end - at);
                continue;
            }
            b'[' => depth += 1,
            b']' => {
                depth -= 1;
                if depth == 0 {
                    return Some(at);
                }
            }
            _ => {
            }
        }
        at += 1;
    }
    None
}

#[derive(Clone)]
struct Reference {
    url: String,
    title: Option<String>,
}

enum Block {
    Heading(usize, String),
    Paragraph(String),
    Rule,
    Code(String, Vec<String>),
    Quote(Vec<Block>),
    Alert(String, Vec<Block>),
    List(Option<usize>, Vec<Vec<Block>>),
    Table(Vec<String>, Vec<String>, Vec<Vec<String>>),
    Toc,
}

struct Marker {
    kind: u8,
    number: Option<usize>,
    content: String,
}

fn fence(s: &str) -> Option<(u8, usize, String)> {
    let c = *s.as_bytes().first()?;
    if c != b'`' && c != b'~' {
        return None;
    }
    let n = run_end(s, 0);
    let info = trim(&s[n..]);
    if n < 3 || (c == b'`' && info.contains('`')) {
        return None;
    }
    Some((c, n, info.split(' ').next().unwrap().into()))
}

fn atx(s: &str) -> Option<Block> {
    let n = s.bytes().take_while(|&c| c == b'#').count();
    if n == 0 || n > 6 || (n < s.len() && s.as_bytes()[n] != b' ') {
        return None;
    }
    let mut text = trim(&s[n..]);
    let unmarked = text.trim_end_matches('#');
    if unmarked.is_empty() || unmarked.ends_with(' ') {
        text = trim(unmarked);
    }
    Some(Block::Heading(n, text.into()))
}

fn rule(s: &str) -> bool {
    let b: Vec<u8> = s.bytes().filter(|&c| c != b' ').collect();
    b.len() >= 3 && b"-*_".contains(&b[0]) && b.iter().all(|&c| c == b[0])
}

fn marker(s: &str) -> Option<Marker> {
    if rule(s) {
        return None;
    }
    let b = s.as_bytes();
    let first = *b.first()?;
    let (kind, number, mut at) = if b"-*+".contains(&first) {
        (first, None, 1)
    } else {
        let n = b.iter().take_while(|c| c.is_ascii_digit()).count();
        if n == 0 || n > 9 || n == b.len() || !b".)".contains(&b[n]) {
            return None;
        }
        (b[n], Some(s[..n].parse().unwrap()), n + 1)
    };
    if at >= b.len() || b[at] != b' ' {
        return None;
    }
    while at < b.len() && b[at] == b' ' {
        at += 1;
    }
    Some(Marker {
        kind, number, content: s[at..].into()
    })
}

fn interrupt(s: &str) -> bool {
    !s.starts_with(' ') && (fence(s).is_some() || atx(s).is_some() || rule(s) || s.starts_with('>') || marker(s).is_some())
}

fn cells(s: &str) -> Vec<String> {
    let text = trim(s).strip_prefix('|').unwrap_or(trim(s));
    let b = text.as_bytes();
    let mut result = vec![String::new()];
    let mut at = 0;
    let mut separator = false;
    while at < b.len() {
        let c = b[at];
        at += 1;
        separator = false;
        if c == b'\\' && at < b.len() {
            if b[at] != b'|' {
                result.last_mut().unwrap().push('\\');
            }
            result.last_mut().unwrap().push(b[at] as char);
            at += 1;
        } else if c == b'|' {
            result.push(String::new());
            separator = true;
        } else {
            result.last_mut().unwrap().push(c as char);
        }
    }
    if separator {
        result.pop();
    }
    result.into_iter().map(|s| trim(&s).into()).collect()
}

fn alignment(s: &str) -> Option<String> {
    let core = s.strip_prefix(':').unwrap_or(s);
    let core = core.strip_suffix(':').unwrap_or(core);
    if core.is_empty() || !core.bytes().all(|c| c == b'-') {
        return None;
    }
    Some(match (s.starts_with(':'), s.ends_with(':')) {
        (true, true) => "center", (true, false) => "left", (false, true) => "right", _ => ""
    }.into())
}

#[derive(Default)]
struct Parser {
    references: HashMap<String, Reference>,
    footnotes: HashMap<String, String>,
}

impl Parser {
    fn definition(&mut self, s: &str) -> bool {
        if let Some(rest) = s.strip_prefix("[^") {
            if let Some(end) = rest.find("]:") {
                let name = &rest[..end];
                let body = trim(&rest[end + 2..]);
                if !name.is_empty() && name.bytes().all(label) && !body.is_empty() {
                    self.footnotes.entry(name.to_ascii_lowercase()).or_insert(body.into());
                    return true;
                }
            }
        }
        if !s.starts_with('[') {
            return false;
        }
        let Some(close) = s.find(']') else {
            return false;
        };
        if !s[close + 1..].starts_with(':') {
            return false;
        }
        let name = &s[1..close];
        if name.contains('[') || trim(name).is_empty() || name.starts_with('^') {
            return false;
        }
        let (url, end) = escaped_read(s, skip(s, close + 2), b" ");
        if url.is_empty() {
            return false;
        }
        let at = skip(s, end);
        let mut title = None;
        if at < s.len() {
            if at == end || !b"\"'".contains(&s.as_bytes()[at]) {
                return false;
            }
            let (value, end) = escaped_read(s, at + 1, &[s.as_bytes()[at]]);
            if end != s.len() - 1 {
                return false;
            }
            title = Some(value);
        }
        self.references.entry(normalize(name)).or_insert(Reference {
            url, title
        });
        true
    }

    fn parse(&mut self, lines: &[String]) -> Vec<Block> {
        let mut blocks = Vec::new();
        let mut at = 0;
        while at < lines.len() {
            let line = &lines[at];
            if line.is_empty() {
                at += 1;
                continue;
            }
            if line.starts_with("    ") {
                let start = at;
                while at < lines.len() && (lines[at].is_empty() || lines[at].starts_with("    ")) {
                    at += 1;
                }
                while lines[at - 1].is_empty() {
                    at -= 1;
                }
                blocks.push(Block::Code(String::new(), lines[start..at].iter().map(|s| if s.is_empty() {
                    String::new()
                } else {
                    s[4..].into()
                }).collect()));
                continue;
            }
            if !line.starts_with(' ') {
                if let Some((c, n, language)) = fence(line) {
                    at += 1;
                    let mut code = Vec::new();
                    while at < lines.len() {
                        let row = &lines[at];
                        at += 1;
                        if row.len() >= n && row.bytes().all(|v| v == c) {
                            break;
                        }
                        code.push(row.clone());
                    }
                    blocks.push(Block::Code(language, code));
                    continue;
                }
                if let Some(heading) = atx(line) {
                    blocks.push(heading);
                    at += 1;
                    continue;
                }
                if rule(line) {
                    blocks.push(Block::Rule);
                    at += 1;
                    continue;
                }
                if line.starts_with('>') {
                    let mut content = Vec::new();
                    while at < lines.len() && lines[at].starts_with('>') {
                        let row = &lines[at][1..];
                        content.push(row.strip_prefix(' ').unwrap_or(row).to_owned());
                        at += 1;
                    }
                    let kind = content[0].strip_prefix("[!").and_then(|s| s.strip_suffix(']'));
                    if let Some(kind) = kind.filter(|k| ["NOTE", "TIP", "IMPORTANT", "WARNING", "CAUTION"].contains(k)) {
                        blocks.push(Block::Alert(kind.into(), self.parse(&content[1..])));
                    } else {
                        blocks.push(Block::Quote(self.parse(&content)));
                    }
                    continue;
                }
                if let Some(mut item) = marker(line) {
                    let kind = item.kind;
                    let start = item.number;
                    let mut items = Vec::new();
                    loop {
                        let mut content = vec![item.content];
                        at += 1;
                        while at < lines.len() && lines[at].starts_with("  ") {
                            content.push(lines[at][2..].into());
                            at += 1;
                        }
                        items.push(self.parse(&content));
                        let mut next = at;
                        while next < lines.len() && lines[next].is_empty() {
                            next += 1;
                        }
                        let following = lines.get(next).and_then(|s| marker(s));
                        match following {
                            Some(m) if m.kind == kind && m.number.is_some() == start.is_some() => {
                                item = m;
                                at = next;
                            }
                            _ => break,
                        }
                    }
                    blocks.push(Block::List(start, items));
                    continue;
                }
                if self.definition(line) {
                    at += 1;
                    continue;
                }
                if at + 1 < lines.len() && line.contains('|') && lines[at + 1].contains('|') {
                    let header = cells(line);
                    let delimiters = cells(&lines[at + 1]);
                    let align: Option<Vec<String>> = delimiters.iter().map(|s| alignment(s)).collect();
                    if let Some(align) = align.filter(|_| header.len() == delimiters.len()) {
                        let columns = header.len();
                        let mut rows = Vec::new();
                        at += 2;
                        while at < lines.len() && lines[at].contains('|') {
                            let mut row = cells(&lines[at]);
                            row.resize(columns, String::new());
                            row.truncate(columns);
                            rows.push(row);
                            at += 1;
                        }
                        blocks.push(Block::Table(align, header, rows));
                        continue;
                    }
                }
            }
            let mut text = vec![line.trim_start_matches(' ').to_owned()];
            at += 1;
            let mut level = 0;
            while at < lines.len() && !lines[at].is_empty() {
                let row = &lines[at];
                if row.len() >= 3 && (row.starts_with('=') || row.starts_with('-')) && row.bytes().all(|c| c == row.as_bytes()[0]) {
                    level = if row.starts_with('=') {
                        1
                    } else {
                        2
                    };
                    at += 1;
                    break;
                }
                if interrupt(row) {
                    break;
                }
                text.push(row.trim_start_matches(' ').into());
                at += 1;
            }
            let text = text.join("\n");
            blocks.push(if level > 0 {
                Block::Heading(level, text)
            } else if text == "[TOC]" {
                Block::Toc
            } else {
                Block::Paragraph(text)
            });
        }
        blocks
    }
}

struct Piece {
    html: String,
    delimiter: u8,
    length: usize,
    open: bool,
    close: bool,
}

impl Piece {
    fn text(html: String) -> Self {
        Self {
            html, delimiter: 0, length: 0, open: false, close: false
        }
    }
}

fn emphasis(pieces: &[Piece]) -> String {
    let mut html = String::new();
    let mut at = 0;
    while at < pieces.len() {
        let piece = &pieces[at];
        if piece.delimiter == 0 {
            html.push_str(&piece.html);
            at += 1;
            continue;
        }
        let close = if piece.open {
            (at + 1..pieces.len()).find(|&i| pieces[i].delimiter == piece.delimiter && pieces[i].length == piece.length && pieces[i].close)
        } else {
            None
        };
        if let Some(end) = close {
            let (opening, closing) = match (piece.delimiter, piece.length) {
                (b'~', _) => ("<del>", "</del>"), (_, 1) => ("<em>", "</em>"), (_, 2) => ("<strong>", "</strong>"), _ => ("<em><strong>", "</strong></em>"),
            };
            html.push_str(opening);
            html.push_str(&emphasis(&pieces[at + 1..end]));
            html.push_str(closing);
            at = end + 1;
        } else {
            html.push_str(&String::from_utf8(vec![piece.delimiter; piece.length]).unwrap());
            at += 1;
        }
    }
    html
}

fn email(s: &str) -> bool {
    let Some((local, domain)) = s.split_once('@') else {
        return false;
    };
    if local.is_empty() || !local.bytes().all(|c| c.is_ascii_alphanumeric() || b".+-_".contains(&c)) {
        return false;
    }
    let parts: Vec<&str> = domain.split('.').collect();
    parts.len() >= 2 && parts.iter().all(|p| !p.is_empty() && p.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'-'))
}

struct Heading {
    level: usize,
    id: String,
    text: String,
}

struct Renderer {
    references: HashMap<String, Reference>,
    footnotes: HashMap<String, String>,
    used_ids: HashSet<String>,
    headings: Vec<Heading>,
    note_numbers: HashMap<String, usize>,
    note_names: Vec<String>,
    note_counts: Vec<usize>,
}

impl Renderer {
    fn new(parser: Parser) -> Self {
        Self {
            references: parser.references, footnotes: parser.footnotes, used_ids: HashSet::new(), headings: Vec::new(), note_numbers: HashMap::new(), note_names: Vec::new(), note_counts: Vec::new()
        }
    }

    fn destination(&self, s: &str, at: usize, text: &str) -> Option<(Reference, usize)> {
        if s[at..].starts_with('[') {
            if let Some(end) = s[at + 1..].find(']').map(|p| p + at + 1) {
                let name = &s[at + 1..end];
                if !name.contains('[') {
                    let key = normalize(if name.is_empty() {
                        text
                    } else {
                        name
                    });
                    return self.references.get(&key).cloned().map(|r| (r, end + 1));
                }
            }
        } else if s[at..].starts_with('(') {
            let (url, end) = escaped_read(s, skip(s, at + 1), b" \n)");
            let mut next = skip(s, end);
            let mut title = None;
            let mut valid = true;
            if next > end && next < s.len() && b"\"'".contains(&s.as_bytes()[next]) {
                let (value, end) = escaped_read(s, next + 1, &[s.as_bytes()[next]]);
                if end == s.len() {
                    valid = false;
                } else {
                    title = Some(value);
                    next = skip(s, end + 1);
                }
            }
            if valid && s[next..].starts_with(')') {
                return Some((Reference {
                    url, title
                }, next + 1));
            }
        }
        self.references.get(&normalize(text)).cloned().map(|r| (r, at))
    }

    fn inline(&mut self, s: &str, links: bool, notes: bool) -> String {
        let b = s.as_bytes();
        let mut pieces = Vec::new();
        let mut at = 0;
        while at < s.len() {
            let c = b[at];
            if c == b'\\' {
                if at + 1 < b.len() && b[at + 1].is_ascii_punctuation() {
                    pieces.push(Piece::text(escape(&s[at + 1..at + 2])));
                    at += 2;
                } else if at + 1 < b.len() && b[at + 1] == b'\n' {
                    pieces.push(Piece::text("<br />\n".into()));
                    at += 2;
                } else {
                    pieces.push(Piece::text("\\".into()));
                    at += 1;
                }
                continue;
            }
            if c == b'`' {
                let end = run_end(s, at);
                if let Some(close) = tick_closer(s, end, end - at) {
                    let mut code = s[end..close].replace('\n', " ");
                    if code.starts_with(' ') && code.ends_with(' ') && code.bytes().any(|c| c != b' ') {
                        code = code[1..code.len() - 1].into();
                    }
                    pieces.push(Piece::text(format!("<code>{}</code>", escape(&code))));
                    at = close + end - at;
                } else {
                    pieces.push(Piece::text(s[at..end].into()));
                    at = end;
                }
                continue;
            }
            if links && c == b'<' {
                if let Some(close) = s[at + 1..].find('>').map(|p| p + at + 1) {
                    let target = &s[at + 1..close];
                    let clean = !target.bytes().any(|c| white(c) || c == b'<');
                    let href = if clean && ((target.starts_with("http://") && target.len() > 7) || (target.starts_with("https://") && target.len() > 8)) {
                        Some(target.to_owned())
                    } else if email(target) {
                        Some(format!("mailto:{}", target))
                    } else {
                        None
                    };
                    if let Some(href) = href {
                        pieces.push(Piece::text(format!("<a href=\"{}\">{}</a>", escape(&href), escape(target))));
                        at = close + 1;
                        continue;
                    }
                }
            }
            if links && (s[at..].starts_with("http://") || s[at..].starts_with("https://")) && (at == 0 || b" \n*_~(".contains(&b[at - 1])) {
                let mut end = at;
                while end < b.len() && !b" \n<".contains(&b[end]) {
                    end += 1;
                }
                while end > at && b".,:;!?*_~)".contains(&b[end - 1]) {
                    end -= 1;
                }
                let url = &s[at..end];
                if url != "http://" && url != "https://" {
                    let url = escape(url);
                    pieces.push(Piece::text(format!("<a href=\"{}\">{}</a>", url, url)));
                    at = end;
                    continue;
                }
            }
            if c == b'[' || (c == b'!' && b.get(at + 1) == Some(&b'[')) {
                if links && notes && s[at..].starts_with("[^") {
                    if let Some(close) = s[at + 2..].find(']').map(|p| p + at + 2) {
                        let name = s[at + 2..close].to_ascii_lowercase();
                        if self.footnotes.contains_key(&name) {
                            pieces.push(Piece::text(self.note_reference(&name)));
                            at = close + 1;
                            continue;
                        }
                    }
                }
                let image = c == b'!';
                let opening = at + usize::from(image);
                if image || links {
                    if let Some(close) = closing_bracket(s, opening) {
                        let text = &s[opening + 1..close];
                        if let Some((reference, end)) = self.destination(s, close + 1, text) {
                            let content = self.inline(text, false, false);
                            let title = reference.title.map_or(String::new(), |t| format!(" title=\"{}\"", escape(&t)));
                            let url = escape(&reference.url);
                            let html = if image {
                                format!("<img src=\"{}\" alt=\"{}\"{} />", url, strip_tags(&content), title)
                            } else {
                                format!("<a href=\"{}\"{}>{}</a>", url, title, content)
                            };
                            pieces.push(Piece::text(html));
                            at = end;
                            continue;
                        }
                    }
                }
            }
            if b"*_~".contains(&c) {
                let end = run_end(s, at);
                let length = end - at;
                let before = if at == 0 {
                    b' '
                } else {
                    b[at - 1]
                };
                let after = b.get(end).copied().unwrap_or(b' ');
                let mut open = !white(after);
                let mut close = !white(before);
                if c == b'_' && before.is_ascii_alphanumeric() && after.is_ascii_alphanumeric() {
                    open = false;
                    close = false;
                }
                if (c != b'~' && length <= 3) || (c == b'~' && length == 2) {
                    pieces.push(Piece {
                        html: String::new(), delimiter: c, length, open, close
                    });
                } else {
                    pieces.push(Piece::text(s[at..end].into()));
                }
                at = end;
                continue;
            }
            pieces.push(Piece::text(escape(&s[at..at + 1])));
            at += 1;
        }
        emphasis(&pieces)
    }

    fn blocks(&mut self, blocks: &[Block]) -> String {
        let mut html = String::new();
        for block in blocks {
            html.push_str(&self.render(block));
            html.push('\n');
        }
        html
    }

    fn render(&mut self, block: &Block) -> String {
        match block {
            Block::Heading(level, text) => self.heading(*level, text), Block::Paragraph(text) => format!("<p>{}</p>", self.inline(text, true, true)), Block::Rule => "<hr />".into(), Block::Code(language, lines) => {
                let attribute = if language.is_empty() {
                    String::new()
                } else {
                    format!(" class=\"language-{}\"", escape(language))
                };
                format!("<pre><code{}>{}</code></pre>", attribute, lines.iter().map(|s| format!("{}\n", escape(s))).collect::<String>())
            }
            Block::Quote(blocks) => format!("<blockquote>\n{}</blockquote>", self.blocks(blocks)), Block::Alert(kind, blocks) => {
                let name = kind.to_ascii_lowercase();
                let title = format!("{}{}", &kind[..1], &name[1..]);
                format!("<div class=\"alert alert-{}\">\n<p class=\"alert-title\">{}</p>\n{}</div>", name, title, self.blocks(blocks))
            }
            Block::List(start, items) => {
                let tag = if start.is_some() {
                    "ol"
                } else {
                    "ul"
                };
                let attribute = start.filter(|&n| n != 1).map_or(String::new(), |n| format!(" start=\"{}\"", n));
                let mut html = format!("<{}{}>\n", tag, attribute);
                for item in items {
                    html.push_str(&self.item(item));
                    html.push('\n');
                }
                format!("{}</{}>", html, tag)
            }
            Block::Table(align, header, rows) => {
                let mut html = format!("<table>\n<thead>\n<tr>\n{}</tr>\n</thead>\n", self.table_cells("th", align, header));
                if !rows.is_empty() {
                    html.push_str("<tbody>\n");
                    for row in rows {
                        html.push_str(&format!("<tr>\n{}</tr>\n", self.table_cells("td", align, row)));
                    }
                    html.push_str("</tbody>\n");
                }
                html + "</table>"
            }
            Block::Toc => TOC.into(),
        }
    }

    fn item(&mut self, blocks: &[Block]) -> String {
        let mut html = "<li>".to_owned();
        for (i, block) in blocks.iter().enumerate() {
            if let Block::Paragraph(text) = block {
                let task = i == 0 && text.len() > 4 && ["[ ] ", "[x] ", "[X] "].iter().any(|p| text.starts_with(p));
                if task {
                    html.push_str(if text.as_bytes()[1] == b' ' {
                        "<input type=\"checkbox\" disabled=\"\" /> "
                    } else {
                        "<input type=\"checkbox\" checked=\"\" disabled=\"\" /> "
                    });
                }
                html.push_str(&self.inline(if task {
                    &text[4..]
                } else {
                    text
                }, true, true));
            } else {
                if !html.ends_with('\n') {
                    html.push('\n');
                }
                html.push_str(&self.render(block));
                html.push('\n');
            }
        }
        html + "</li>"
    }

    fn table_cells(&mut self, tag: &str, align: &[String], cells: &[String]) -> String {
        let mut html = String::new();
        for (cell, alignment) in cells.iter().zip(align) {
            let style = if alignment.is_empty() {
                String::new()
            } else {
                format!(" style=\"text-align:{}\"", alignment)
            };
            html.push_str(&format!("<{}{}>{}</{}>\n", tag, style, self.inline(cell, true, true), tag));
        }
        html
    }

    fn heading(&mut self, level: usize, source: &str) -> String {
        let mut text = source;
        let explicit = source.rfind(" {#").filter(|_| source.ends_with('}')).and_then(|at| {
            let name = &source[at + 3..source.len() - 1];
            if !name.is_empty() && name.bytes().all(label) {
                Some((at, name))
            } else {
                None
            }
        });
        let id = if let Some((at, name)) = explicit {
            text = source[..at].trim_end_matches(' ');
            name.into()
        } else {
            let mut base: String = source.to_ascii_lowercase().bytes().filter_map(|c| if label(c) {
                Some(c as char)
            } else if white(c) {
                Some('-')
            } else {
                None
            }).collect();
            if base.is_empty() {
                base = "heading".into();
            }
            let mut id = base.clone();
            let mut suffix = 1;
            while self.used_ids.contains(&id) {
                id = format!("{}-{}", base, suffix);
                suffix += 1;
            }
            id
        };
        self.used_ids.insert(id.clone());
        let html = self.inline(text, true, true);
        self.headings.push(Heading {
            level, id: id.clone(), text: strip_tags(&html)
        });
        format!("<h{} id=\"{}\">{}</h{}>", level, id, html, level)
    }

    fn toc_list(&self, children: &[Vec<usize>], entries: &[usize]) -> String {
        let mut html = "<ul>\n".to_owned();
        for &i in entries {
            let heading = &self.headings[i];
            html.push_str(&format!("<li><a href=\"#{}\">{}</a>", heading.id, heading.text));
            if !children[i].is_empty() {
                html.push_str(&format!("\n{}\n", self.toc_list(children, &children[i])));
            }
            html.push_str("</li>\n");
        }
        html + "</ul>"
    }

    fn toc(&self) -> String {
        if self.headings.is_empty() {
            return "<nav class=\"toc\">\n</nav>".into();
        }
        let mut roots = Vec::new();
        let mut parents: Vec<usize> = Vec::new();
        let mut children = vec![Vec::new(); self.headings.len()];
        for (i, heading) in self.headings.iter().enumerate() {
            while parents.last().is_some_and(|&p| self.headings[p].level >= heading.level) {
                parents.pop();
            }
            if let Some(&p) = parents.last() {
                children[p].push(i);
            } else {
                roots.push(i);
            }
            parents.push(i);
        }
        format!("<nav class=\"toc\">\n{}\n</nav>", self.toc_list(&children, &roots))
    }

    fn reference_id(index: usize, count: usize) -> String {
        format!("fnref-{}{}", index + 1, if count == 1 {
            String::new()
        } else {
            format!("-{}", count)
        })
    }

    fn note_reference(&mut self, name: &str) -> String {
        let index = if let Some(&i) = self.note_numbers.get(name) {
            i
        } else {
            let i = self.note_names.len();
            self.note_numbers.insert(name.into(), i);
            self.note_names.push(name.into());
            self.note_counts.push(0);
            i
        };
        self.note_counts[index] += 1;
        format!("<sup id=\"{}\"><a href=\"#fn-{}\">{}</a></sup>", Self::reference_id(index, self.note_counts[index]), index + 1, index + 1)
    }

    fn note_list(&mut self) -> String {
        let mut html = "<section class=\"footnotes\">\n<ol>\n".to_owned();
        for i in 0..self.note_names.len() {
            let source = self.footnotes[&self.note_names[i]].clone();
            let body = self.inline(&source, true, false);
            html.push_str(&format!("<li id=\"fn-{}\">{}", i + 1, body));
            for count in 1..=self.note_counts[i] {
                html.push_str(&format!(" <a href=\"#{}\">&#8617;</a>", Self::reference_id(i, count)));
            }
            html.push_str("</li>\n");
        }
        html + "</ol>\n</section>\n"
    }

    fn document(&mut self, blocks: &[Block]) -> String {
        let html = self.blocks(blocks);
        let mut html = html.replace(TOC, &self.toc());
        if !self.note_names.is_empty() {
            html.push_str(&self.note_list());
        }
        html
    }
}

fn main() {
    let mut source = String::new();
    io::stdin().read_to_string(&mut source).unwrap();
    let lines: Vec<String> = source.lines().take_while(|&s| s != "@@END@@").map(str::to_owned).collect();
    let mut parser = Parser::default();
    let blocks = parser.parse(&lines);
    let mut renderer = Renderer::new(parser);
    print!("{}", renderer.document(&blocks));
}
