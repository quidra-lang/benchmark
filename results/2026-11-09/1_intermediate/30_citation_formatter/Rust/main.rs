use std::collections::{BTreeMap, BTreeSet};
use std::io::{self, Read};

const FIELDS: [&str; 18] = [
    "author", "editor", "title", "journal", "booktitle", "edition", "volume", "number", "pages",
    "publisher", "institution", "school", "address", "howpublished", "month", "year", "doi", "note",
];
const TYPES: [&str; 7] = ["article", "book", "inproceedings", "incollection", "techreport", "phdthesis", "misc"];
const REQUIRED: [&[&str]; 7] = [
    &["author", "title", "journal", "year"], &["author", "title", "publisher", "year"],
    &["author", "title", "booktitle", "year"], &["author", "title", "booktitle", "publisher", "year"],
    &["author", "title", "institution", "year"], &["author", "title", "school", "year"], &["author", "title", "year"],
];
const MONTHS: [&str; 12] = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
const MONTH_MACROS: [&str; 12] = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
const MONTH_SHORT: [&str; 12] = ["Jan.", "Feb.", "Mar.", "Apr.", "May", "June", "July", "Aug.", "Sep.", "Oct.", "Nov.", "Dec."];
const SMALL_WORDS: [&str; 24] = ["a", "an", "and", "as", "at", "but", "by", "for", "from", "in", "into", "nor", "of", "on", "or", "over", "per", "so", "the", "to", "up", "via", "with", "yet"];

fn plain(value: &str) -> String { value.chars().filter(|&c| c != '{' && c != '}').collect() }
fn letters(value: &str) -> String { value.chars().filter(char::is_ascii_alphabetic).map(|c| c.to_ascii_lowercase()).collect() }
fn digits(value: &str) -> bool { !value.is_empty() && value.bytes().all(|c| c.is_ascii_digit()) }
fn split_depth<'a>(text: &'a str, delimiter: &str) -> Vec<&'a str> {
    let mut result = Vec::new();
    let (mut start, mut i, mut depth) = (0, 0, 0);
    while i < text.len() {
        if depth == 0 && text[i..].starts_with(delimiter) {
            result.push(&text[start..i]); i += delimiter.len(); start = i;
        } else {
            match text.as_bytes()[i] { b'{' => depth += 1, b'}' => depth -= 1, _ => {} }
            i += 1;
        }
    }
    result.push(&text[start..]); result
}
fn evaluate(expression: &str, macros: &BTreeMap<String, String>) -> Result<String, String> {
    let mut depth = 0;
    for c in expression.bytes() {
        match c { b'{' => depth += 1, b'}' => depth -= 1, _ => {} }
        if depth < 0 { return Err("unbalanced braces".into()); }
    }
    if depth != 0 { return Err("unbalanced braces".into()); }
    let mut result = String::new();
    for term in expression.split(" # ") {
        match term.as_bytes()[0] {
            b'{' | b'"' => result.push_str(&term[1..term.len() - 1]),
            b'0'..=b'9' => result.push_str(term),
            _ => result.push_str(macros.get(term).ok_or_else(|| format!("unknown macro '{term}'"))?),
        }
    }
    Ok(result)
}
fn accent(text: &[u8], at: usize) -> Option<(u8, usize)> {
    if text.get(at) != Some(&b'\\') { return None; }
    let &command = text.get(at + 1)?;
    if command == b'&' { return Some((b'&', 2)); }
    let symbol = b"'\"`^~=.".contains(&command);
    if symbol && text.get(at + 2).is_some_and(u8::is_ascii_alphabetic) { return Some((text[at + 2], 3)); }
    if (symbol || b"cuvH".contains(&command)) && text.get(at + 2) == Some(&b'{')
        && text.get(at + 3).is_some_and(u8::is_ascii_alphabetic) && text.get(at + 4) == Some(&b'}') {
        return Some((text[at + 3], 5));
    }
    None
}
fn normalize(value: &str) -> String {
    let bytes = value.as_bytes();
    let mut accents = String::new();
    let mut i = 0;
    while i < bytes.len() {
        let wrapped = if bytes[i] == b'{' { accent(bytes, i + 1).filter(|&(_, width)| bytes.get(i + width + 1) == Some(&b'}')) } else { None };
        if let Some((c, width)) = wrapped { accents.push(c as char); i += width + 2; }
        else if let Some((c, width)) = accent(bytes, i) { accents.push(c as char); i += width; }
        else { accents.push(bytes[i] as char); i += 1; }
    }
    accents.replace('~', " ").split(' ').filter(|s| !s.is_empty()).collect::<Vec<_>>().join(" ")
}

#[derive(Clone, PartialEq, Eq)]
struct Name { first: String, von: String, last: String, jr: String }
impl Name {
    fn parse(text: &str) -> Self {
        let parts: Vec<_> = split_depth(text, ",").into_iter().map(|p| p.trim_matches(' ')).collect();
        let words = split_depth(parts[0], " ");
        let lowercase: Vec<_> = (0..words.len() - 1).filter(|&i| words[i].as_bytes()[0].is_ascii_lowercase()).collect();
        let mut name = Self { first: String::new(), von: String::new(), last: String::new(), jr: String::new() };
        if parts.len() == 1 {
            if let (Some(&first), Some(&last)) = (lowercase.first(), lowercase.last()) {
                name.first = words[..first].join(" "); name.von = words[first..=last].join(" "); name.last = words[last + 1..].join(" ");
            } else { name.first = words[..words.len() - 1].join(" "); name.last = words[words.len() - 1].into(); }
        } else {
            if let Some(&last) = lowercase.last() { name.von = words[..=last].join(" "); name.last = words[last + 1..].join(" "); }
            else { name.last = words.join(" "); }
            name.first = parts[parts.len() - 1].into();
            if parts.len() == 3 { name.jr = parts[1].into(); }
        }
        name
    }
    fn surname(&self) -> String { plain(&if self.von.is_empty() { self.last.clone() } else { format!("{} {}", self.von, self.last) }) }
    fn initials(&self) -> String {
        plain(&self.first).split(' ').filter(|word| !word.is_empty()).map(|word| {
            word.split('-').map(|part| format!("{}.", part.chars().find(char::is_ascii_alphabetic).unwrap().to_ascii_uppercase())).collect::<Vec<_>>().join("-")
        }).collect::<Vec<_>>().join(" ")
    }
    fn text(&self, inverted: bool, abbreviated: bool) -> String {
        let given = if abbreviated { self.initials() } else { plain(&self.first) };
        let mut result = self.surname();
        if !self.first.is_empty() { result = if inverted { format!("{result}, {given}") } else { format!("{given} {result}") }; }
        if !self.jr.is_empty() { result.push_str(&format!(", {}", plain(&self.jr))); }
        result
    }
}
#[derive(Clone, PartialEq, Eq)]
struct NameList { names: Vec<Name>, et_al: bool }
impl NameList {
    fn parse(text: &str) -> Self {
        let mut names = split_depth(text, " and ");
        let et_al = names.last() == Some(&"others");
        if et_al { names.pop(); }
        Self { names: names.into_iter().map(Name::parse).collect(), et_al }
    }
    fn single(&self) -> bool { self.names.len() == 1 && !self.et_al }
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum Style { Apa, Ieee, Chicago, Mla }
impl Style {
    fn parse(text: &str) -> Option<Self> { match text { "APA" => Some(Self::Apa), "IEEE" => Some(Self::Ieee), "CHICAGO" => Some(Self::Chicago), "MLA" => Some(Self::Mla), _ => None } }
}
fn title_case(title: &str, style: Style) -> String {
    if style == Style::Ieee { return title.into(); }
    if style == Style::Apa {
        let mut result = title.as_bytes().to_vec();
        let mut depth = 0;
        for i in 0..result.len() {
            match result[i] {
                b'{' => depth += 1, b'}' => depth -= 1,
                c if depth == 0 && c.is_ascii_alphabetic() => result[i] = if i == 0 || (i >= 2 && &title[i - 2..i] == ": ") { c.to_ascii_uppercase() } else { c.to_ascii_lowercase() },
                _ => {}
            }
        }
        return String::from_utf8(result).unwrap();
    }
    let words = split_depth(title, " ");
    words.iter().enumerate().map(|(i, word)| {
        if word.starts_with('{') { return (*word).to_owned(); }
        let lowercase = i > 0 && i + 1 < words.len() && !words[i - 1].ends_with(':') && SMALL_WORDS.contains(&letters(word).as_str());
        let (mut depth, mut first_letter) = (0, true);
        word.bytes().map(|c| {
            let mut result = c;
            match c {
                b'{' => depth += 1, b'}' => depth -= 1,
                _ if c.is_ascii_alphabetic() => {
                    if depth == 0 && lowercase { result = c.to_ascii_lowercase(); }
                    else if depth == 0 && first_letter { result = c.to_ascii_uppercase(); }
                    first_letter = false;
                }, _ => {}
            }
            result as char
        }).collect::<String>()
    }).collect::<Vec<_>>().join(" ")
}
fn listed(names: &[String], conjunction: &str, list_b: bool) -> String {
    if names.len() == 1 { return names[0].clone(); }
    if names.len() == 2 && list_b { return format!("{} {conjunction} {}", names[0], names[1]); }
    format!("{}, {conjunction} {}", names[..names.len() - 1].join(", "), names.last().unwrap())
}
fn render_names(list: &NameList, style: Style, editor: bool) -> String {
    let names: Vec<_> = list.names.iter().enumerate().map(|(i, name)| {
        name.text(!editor && (style == Style::Apa || (style != Style::Ieee && i == 0)), style == Style::Apa || style == Style::Ieee)
    }).collect();
    if editor { return if list.et_al { format!("{} et al.", names[0]) } else { listed(&names, if style == Style::Apa { "&" } else { "and" }, true) }; }
    match style {
        Style::Apa if list.et_al => format!("{}, et al.", names.join(", ")),
        Style::Apa if names.len() >= 21 => format!("{}, . . . {}", names[..19].join(", "), names.last().unwrap()),
        Style::Apa => listed(&names, "&", false),
        Style::Ieee if list.et_al || names.len() >= 7 => format!("{} et al.", names[0]),
        Style::Ieee => listed(&names, "and", true),
        Style::Chicago if list.et_al || names.len() >= 11 => format!("{}, et al.", names[..names.len().min(7)].join(", ")),
        Style::Chicago => listed(&names, "and", false),
        Style::Mla if list.et_al || names.len() >= 3 => format!("{}, et al.", names[0]),
        Style::Mla => listed(&names, "and", false),
    }
}

struct Entry {
    key: String, kind: usize, fields: BTreeMap<String, String>,
    authors: Option<NameList>, editors: Option<NameList>, suffix: Option<char>,
    sort_last: String, year: String, sort_title: String, plain_title: String, lower_title: String, base_key: String,
}
impl Entry {
    fn new(key: String, kind: usize, fields: BTreeMap<String, String>) -> Self {
        let authors = fields.get("author").map(|s| NameList::parse(s));
        let editors = fields.get("editor").map(|s| NameList::parse(s));
        let lead = &authors.as_ref().or(editors.as_ref()).unwrap().names[0];
        let sort_last = plain(&lead.last).to_ascii_lowercase();
        let year = plain(&fields["year"]);
        let plain_title = plain(&fields["title"]);
        let lower_title = plain_title.to_ascii_lowercase();
        let sort_title = ["a ", "an ", "the "].iter().find_map(|prefix| lower_title.strip_prefix(*prefix)).unwrap_or(&lower_title).to_owned();
        let title_word = plain_title.split(' ').map(letters).find(|s| !s.is_empty() && !SMALL_WORDS.contains(&s.as_str())).unwrap_or_default();
        let year_digits: String = fields["year"].chars().filter(char::is_ascii_digit).collect();
        let base_key = format!("{}{year_digits}{title_word}", letters(&plain(&lead.last)));
        Self { key, kind, fields, authors, editors, suffix: None, sort_last, year, sort_title, plain_title, lower_title, base_key }
    }
    fn primary(&self) -> &NameList { self.authors.as_ref().or(self.editors.as_ref()).unwrap() }
    fn sort_key(&self) -> (&str, &str, &str, &str) { (&self.sort_last, &self.year, &self.sort_title, &self.key) }
    fn year_label(&self, style: Style) -> String {
        if let Some(suffix) = self.suffix.filter(|_| style == Style::Apa || style == Style::Chicago) { format!("{}{suffix}", self.year) } else { self.year.clone() }
    }
    fn short_name(&self, style: Style, parenthetical: bool) -> String {
        let names = self.primary();
        if names.et_al || names.names.len() >= if style == Style::Chicago { 4 } else { 3 } { return format!("{} et al.", names.names[0].surname()); }
        listed(&names.names.iter().map(Name::surname).collect::<Vec<_>>(), if style == Style::Apa && parenthetical { "&" } else { "and" }, true)
    }
    fn unknown_fields(&self) -> Vec<&str> { self.fields.keys().map(String::as_str).filter(|name| !FIELDS.contains(name)).collect() }
}

const TEMPLATES: [[&str; 6]; 4] = [
    [
        "{author}. ({year}). {title}. {journal}<, {volume}<({number})>><, {pages}>.< https://doi.org/{doi}>",
        "{author}. ({year}). {title}< ({edition})>. {publisher}.",
        "{author}. ({year}). {title}. In <{editor} ({eds}), >{booktitle}< ({pp})>.< {publisher}.>",
        "{author}. ({year}). {title}< (Report No. {number})>. {institution}.",
        "{author}. ({year}). {title} [Doctoral dissertation, {school}].",
        "{author}. ({year}<, {month}>). {title}.< {howpublished}.>< {note}.>",
    ], [
        "{author}, \"{title},\" {journal}<, vol. {volume}><, no. {number}><, {pp}>, <{mon} >{year}<, doi: {doi}>.",
        "{author}, {title}<, {edition}>. <{address}: >{publisher}, {year}.",
        "{author}, \"{title},\" in {booktitle}<, {editor}, {eds}><, {address}><, {publisher}>, {year}<, {pp}>.",
        "{author}, \"{title},\" {institution}<, {address}>, Tech. Rep.< {number}>, {year}.",
        "{author}, \"{title},\" Ph.D. dissertation, {school}<, {address}>, {year}.",
        "{author}, \"{title},\"< {howpublished},> <{mon} >{year}.< {note}.>",
    ], [
        "{author}. {year}. \"{title}.\" {journal}< {volume}>< ({number})><: {pages}>.< https://doi.org/{doi}.>",
        "{author}. {year}. {title}.< {edition}.> <{address}: >{publisher}.",
        "{author}. {year}. \"{title}.\" In {booktitle}<, edited by {editor}><, {pages}>.< <{address}: >{publisher}.>",
        "{author}. {year}. {title}. Technical Report< {number}>. <{address}: >{institution}.",
        "{author}. {year}. \"{title}.\" PhD diss., {school}.",
        "{author}. {year}. {title}.< {howpublished}.>< {note}.>",
    ], [
        "{author}. \"{title}.\" {journal}<, vol. {volume}><, no. {number}>, <{mon} >{year}<, {pp}>.< https://doi.org/{doi}.>",
        "{author}. {title}.< {edition},> {publisher}, {year}.",
        "{author}. \"{title}.\" {booktitle},< edited by {editor},>< {publisher},> {year}<, {pp}>.",
        "{author}. {title}. {institution}, {year}.< Technical Report {number}.>",
        "{author}. {title}. {year}. {school}, PhD dissertation.",
        "{author}. {title}.< {howpublished},> <{mon} >{year}.< {note}.>",
    ],
];
fn placeholder_index(name: &str) -> usize {
    FIELDS.iter().position(|&field| field == name).unwrap_or(match name { "eds" => 18, "pp" => 19, _ => 20 })
}
fn optional_end(pattern: &str, start: usize) -> usize {
    let mut depth = 1;
    let mut i = start + 1;
    loop {
        match pattern.as_bytes()[i] { b'<' => depth += 1, b'>' => depth -= 1, _ => {} }
        if depth == 0 { return i; }
        i += 1;
    }
}
fn optional_present(pattern: &str, start: usize, end: usize, values: &[String; 21]) -> bool {
    let mut i = start;
    while i < end {
        if pattern.as_bytes()[i] == b'<' { i = optional_end(pattern, i); }
        else if pattern.as_bytes()[i] == b'{' {
            let close = i + pattern[i..].find('}').unwrap();
            if values[placeholder_index(&pattern[i + 1..close])].is_empty() { return false; }
            i = close;
        }
        i += 1;
    }
    true
}
fn render_template(pattern: &str, start: usize, end: usize, values: &[String; 21], result: &mut String) {
    let mut i = start;
    while i < end {
        match pattern.as_bytes()[i] {
            b'<' => {
                let close = optional_end(pattern, i);
                if optional_present(pattern, i + 1, close, values) { render_template(pattern, i + 1, close, values, result); }
                i = close;
            },
            b'{' => {
                let close = i + pattern[i..].find('}').unwrap();
                result.push_str(&values[placeholder_index(&pattern[i + 1..close])]); i = close;
            },
            b'.' if result.as_bytes().last().is_some_and(|c| b".?!".contains(c)) => {},
            c => result.push(c as char),
        }
        i += 1;
    }
}
impl Entry {
    fn reference(&self, style: Style, number: usize, repeated: bool) -> String {
        let mut values: [String; 21] = std::array::from_fn(|_| String::new());
        for (i, name) in FIELDS.iter().enumerate() { if let Some(value) = self.fields.get(*name) { values[i] = plain(value); } }
        let names = self.primary();
        values[0] = if repeated { "---".into() } else { render_names(names, style, false) };
        if self.authors.is_none() {
            let annotations = [[" (Ed.)", " (Eds.)"], [", Ed.", ", Eds."], [", ed.", ", eds."], [", editor", ", editors"]];
            values[0].push_str(annotations[style as usize][usize::from(!names.single())]);
        }
        if let Some(editors) = &self.editors {
            values[1] = render_names(editors, style, true);
            values[18] = if editors.single() { "Ed." } else { "Eds." }.into();
        }
        values[2] = plain(&title_case(&self.fields["title"], style)); values[15] = self.year_label(style);
        if let Some(pages) = self.fields.get("pages") {
            values[8] = plain(pages).replace("--", "-");
            values[19] = format!("{} {}", if values[8].contains('-') { "pp." } else { "p." }, values[8]);
        }
        if let Some(edition) = self.fields.get("edition") {
            let value = plain(edition);
            values[5] = if digits(&value) {
                let n: u32 = value.parse().unwrap();
                let suffix = if (11..=13).contains(&(n % 100)) { "th" } else { match n % 10 { 1 => "st", 2 => "nd", 3 => "rd", _ => "th" } };
                format!("{n}{suffix} ed.")
            } else { format!("{value} ed.") };
        }
        if let Some(month) = self.fields.get("month") {
            let value = plain(month);
            values[20] = MONTHS.iter().position(|&m| m == value).map(|i| MONTH_SHORT[i].to_owned()).unwrap_or(value);
        }
        let kind = if self.kind == 3 { 2 } else if self.kind > 3 { self.kind - 1 } else { self.kind };
        let pattern = TEMPLATES[style as usize][kind];
        let mut result = if style == Style::Ieee { format!("[{number}] ") } else { String::new() };
        render_template(pattern, 0, pattern.len(), &values, &mut result); result
    }
}

struct Database { entries: Vec<Entry>, lookup: BTreeMap<String, usize>, record: Vec<usize>, output: Vec<String> }
impl Database {
    fn read(lines: &[&str]) -> Self {
        let mut database = Self { entries: Vec::new(), lookup: BTreeMap::new(), record: Vec::new(), output: Vec::new() };
        let mut macros: BTreeMap<String, String> = MONTH_MACROS.into_iter().zip(MONTHS).map(|(a, b)| (a.into(), b.into())).collect();
        let (mut macro_count, mut errors, mut i) = (0, 0, 0);
        while i < lines.len() {
            let line = lines[i];
            if line.is_empty() || line.starts_with('%') { i += 1; continue; }
            if let Some(definition) = line.strip_prefix("@string{") {
                let (name, expression) = definition[..definition.len() - 1].split_once(" = ").unwrap();
                let result = evaluate(expression, &macros).and_then(|value| if macros.contains_key(name) { Err("duplicate macro".into()) } else { Ok(value) });
                match result {
                    Ok(value) => { macros.insert(name.into(), value); macro_count += 1; },
                    Err(reason) => { database.output.push(format!("ERROR line {}: {name}: {reason}", i + 1)); errors += 1; },
                }
                i += 1; continue;
            }
            let (kind_name, key) = line[1..line.len() - 1].split_once('{').unwrap();
            let kind = TYPES.iter().position(|&value| value == kind_name);
            let mut error = if kind.is_none() { Some((i + 1, format!("unknown type '{kind_name}'"))) }
                else if database.lookup.contains_key(key) { Some((i + 1, "duplicate key".into())) } else { None };
            let mut fields = BTreeMap::new();
            i += 1;
            while lines[i] != "}" {
                if error.is_none() {
                    let (name, expression) = lines[i][2..].split_once(" = ").unwrap();
                    let expression = expression.strip_suffix(',').unwrap_or(expression);
                    let result = evaluate(expression, &macros).and_then(|value| if fields.contains_key(name) { Err(format!("duplicate field '{name}'")) } else { Ok(value) });
                    match result {
                        Ok(value) => { fields.insert(name.to_owned(), normalize(&value)); },
                        Err(reason) => error = Some((i + 1, reason)),
                    }
                }
                i += 1;
            }
            if error.is_none() {
                for &name in REQUIRED[kind.unwrap()] {
                    if !fields.contains_key(name) && !(kind == Some(1) && name == "author" && fields.contains_key("editor")) {
                        error = Some((i + 1, format!("missing field '{name}'"))); break;
                    }
                }
            }
            if let Some((line_number, reason)) = error { database.output.push(format!("ERROR line {line_number}: {key}: {reason}")); errors += 1; }
            else {
                database.lookup.insert(key.into(), database.entries.len());
                database.entries.push(Entry::new(key.into(), kind.unwrap(), fields));
            }
            i += 1;
        }
        database.output.push(format!("LOADED entries={} macros={macro_count} errors={errors}", database.entries.len()));
        let mut assigned = vec![false; database.entries.len()];
        for i in 0..database.entries.len() {
            if assigned[i] { continue; }
            let mut group: Vec<_> = (i..database.entries.len()).filter(|&j| database.entries[i].primary() == database.entries[j].primary() && database.entries[i].fields["year"] == database.entries[j].fields["year"]).collect();
            group.sort_by(|&a, &b| (&database.entries[a].sort_title, &database.entries[a].key).cmp(&(&database.entries[b].sort_title, &database.entries[b].key)));
            for (index, &j) in group.iter().enumerate() { assigned[j] = true; if group.len() >= 2 { database.entries[j].suffix = Some((b'a' + index as u8) as char); } }
        }
        database
    }
    fn ieee_order(&self) -> (Vec<usize>, Vec<usize>) {
        let cited: BTreeSet<_> = self.record.iter().copied().collect();
        let mut order = self.record.clone();
        order.extend(self.lookup.values().copied().filter(|index| !cited.contains(index)));
        let mut numbers = vec![0; self.entries.len()];
        for (i, &index) in order.iter().enumerate() { numbers[index] = i + 1; }
        (order, numbers)
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum CitationKind { Parenthetical, Narrative, Author, Year }
struct Citation { start: usize, end: usize, kind: CitationKind, keys: Vec<usize> }
impl Database {
    fn citation_text(&self, citation: &Citation, style: Style, numbers: &[usize]) -> String {
        let parenthetical = citation.kind == CitationKind::Parenthetical;
        if citation.kind == CitationKind::Author || citation.kind == CitationKind::Year || style == Style::Mla || (style == Style::Ieee && !parenthetical) {
            let parts: Vec<_> = citation.keys.iter().map(|&index| {
                let entry = &self.entries[index];
                if citation.kind == CitationKind::Year { entry.year_label(style) }
                else if style == Style::Ieee && citation.kind == CitationKind::Narrative { format!("{} [{}]", entry.short_name(style, false), numbers[index]) }
                else { entry.short_name(style, false) }
            }).collect();
            let text = parts.join(if citation.kind == CitationKind::Year { ", " } else { "; " });
            return if style == Style::Mla && parenthetical { format!("({text})") } else { text };
        }
        let mut parts = Vec::new();
        if style == Style::Ieee {
            let mut sorted: Vec<_> = citation.keys.iter().map(|&i| numbers[i]).collect();
            sorted.sort_unstable();
            let mut i = 0;
            while i < sorted.len() {
                let mut end = i + 1;
                while end < sorted.len() && sorted[end] == sorted[end - 1] + 1 { end += 1; }
                if end - i >= 3 { parts.push(format!("[{}]-[{}]", sorted[i], sorted[end - 1])); }
                else { parts.extend(sorted[i..end].iter().map(|n| format!("[{n}]"))); }
                i = end;
            }
            return parts.join(", ");
        }
        let mut keys = citation.keys.clone();
        if parenthetical { keys.sort_by(|&a, &b| self.entries[a].sort_key().cmp(&self.entries[b].sort_key())); }
        let mut i = 0;
        while i < keys.len() {
            let name = self.entries[keys[i]].short_name(style, parenthetical);
            let mut end = i + 1;
            while end < keys.len() && self.entries[keys[end]].short_name(style, parenthetical) == name { end += 1; }
            let years = keys[i..end].iter().map(|&j| self.entries[j].year_label(style)).collect::<Vec<_>>().join(", ");
            parts.push(if parenthetical { format!("{name}{}{years}", if style == Style::Apa { ", " } else { " " }) } else { format!("{name} ({years})") });
            i = end;
        }
        let text = parts.join("; ");
        if parenthetical { format!("({text})") } else { text }
    }
    fn cite(&mut self, style: Style, text: &str) -> Result<String, String> {
        let mut citations = Vec::new();
        let mut position = 0;
        while let Some(offset) = text[position..].find('\\') {
            let start = position + offset;
            let brace = start + text[start..].find('{').unwrap();
            let end = brace + text[brace..].find('}').unwrap();
            let kind = match &text[start + 1..brace] { "citet" => CitationKind::Narrative, "citeauthor" => CitationKind::Author, "citeyear" => CitationKind::Year, _ => CitationKind::Parenthetical };
            let mut keys = Vec::new();
            let mut seen = BTreeSet::new();
            for key in text[brace + 1..end].split(',') {
                let &index = self.lookup.get(key).ok_or_else(|| format!("unknown key '{key}'"))?;
                if seen.insert(index) { keys.push(index); }
            }
            citations.push(Citation { start, end: end + 1, kind, keys }); position = end + 1;
        }
        let mut recorded: BTreeSet<_> = self.record.iter().copied().collect();
        for citation in &citations { for &index in &citation.keys { if recorded.insert(index) { self.record.push(index); } } }
        let (_, numbers) = self.ieee_order();
        let mut result = String::new(); position = 0;
        for citation in &citations {
            result.push_str(&text[position..citation.start]); result.push_str(&self.citation_text(citation, style, &numbers)); position = citation.end;
        }
        result.push_str(&text[position..]); Ok(result)
    }
    fn keygen(&self) -> Vec<String> {
        let mut counts = BTreeMap::new();
        let mut used = BTreeMap::new();
        for entry in &self.entries { *counts.entry(entry.base_key.as_str()).or_insert(0) += 1; }
        self.entries.iter().map(|entry| {
            let mut key = entry.base_key.clone();
            if counts[entry.base_key.as_str()] >= 2 {
                let index = used.entry(entry.base_key.as_str()).or_insert(0u32);
                key.push(char::from_u32('a' as u32 + *index).unwrap()); *index += 1;
            }
            format!("{} -> {key}", entry.key)
        }).collect()
    }
    fn check(&self) -> Vec<String> {
        let mut result = Vec::new();
        for (i, entry) in self.entries.iter().enumerate() {
            let mut warnings = Vec::new();
            if let Some(pages) = entry.fields.get("pages") {
                let pages = plain(pages);
                if pages.contains('-') && !pages.contains("--") { warnings.push("pages use a single hyphen".into()); }
                let parts: Vec<_> = pages.split('-').filter(|part| !part.is_empty()).collect();
                if parts.len() == 2 && parts.iter().all(|part| digits(part)) && parts[0].parse::<u32>().unwrap() > parts[1].parse::<u32>().unwrap() { warnings.push("pages are reversed".into()); }
            }
            if entry.year.len() != 4 || !digits(&entry.year) { warnings.push("year is not 4 digits".into()); }
            if !entry.plain_title.bytes().any(|c| c.is_ascii_lowercase()) && entry.plain_title.bytes().filter(u8::is_ascii_uppercase).count() >= 2 { warnings.push("title is all caps".into()); }
            if entry.kind == 0 && !entry.fields.contains_key("doi") { warnings.push("article has no doi".into()); }
            if let Some(previous) = self.entries[..i].iter().find(|other| other.lower_title == entry.lower_title) { warnings.push(format!("same title as {}", previous.key)); }
            warnings.extend(entry.unknown_fields().into_iter().map(|name| format!("unknown field '{name}'")));
            result.extend(warnings.into_iter().map(|warning| format!("WARN {}: {warning}", entry.key)));
        }
        result.push(format!("CHECK warnings={}", result.len())); result
    }
    fn export(&self, key: &str) -> Result<Vec<String>, String> {
        let &index = self.lookup.get(key).ok_or_else(|| format!("unknown key '{key}'"))?;
        let entry = &self.entries[index];
        let mut names: Vec<_> = FIELDS.into_iter().filter(|name| entry.fields.contains_key(*name)).collect();
        names.extend(entry.unknown_fields());
        let mut result = vec![format!("@{}{{{key},", TYPES[entry.kind])];
        for (i, name) in names.iter().enumerate() { result.push(format!("  {name} = {{{}}}{}", entry.fields[*name], if i + 1 == names.len() { "" } else { "," })); }
        result.push("}".into()); Ok(result)
    }
    fn stats(&self) -> Vec<String> {
        let mut types = BTreeMap::new();
        let mut years = BTreeMap::new();
        let mut authors = BTreeSet::new();
        let mut pairs = BTreeMap::new();
        for entry in &self.entries {
            *types.entry(TYPES[entry.kind]).or_insert(0usize) += 1;
            *years.entry(entry.year.as_str()).or_insert(0usize) += 1;
            if let Some(list) = &entry.authors {
                let names: BTreeSet<_> = list.names.iter().map(|name| name.text(false, false)).collect();
                authors.extend(names.iter().cloned());
                let names: Vec<_> = names.into_iter().collect();
                for a in 0..names.len() { for b in a + 1..names.len() { *pairs.entry((names[a].clone(), names[b].clone())).or_insert(0usize) += 1; } }
            }
        }
        let mut result = vec![format!("ENTRIES {}", self.entries.len())];
        result.extend(types.iter().map(|(kind, count)| format!("TYPE {kind} {count}")));
        result.extend(years.iter().map(|(year, count)| format!("YEAR {year} {count}")));
        result.push(format!("AUTHORS {}", authors.len()));
        let mut best_count = 0;
        let mut best = None;
        for (pair, &count) in &pairs { if count > best_count { best = Some(pair); best_count = count; } }
        result.push(match best { Some((a, b)) => format!("PAIR {a} & {b} {best_count}"), None => "PAIR none".into() }); result
    }
    fn command(&mut self, line: &str) -> Result<Vec<String>, String> {
        let command = line.split(' ').next().unwrap();
        let words: Vec<_> = if command == "CITE" || command == "SEARCH" { line.splitn(3, ' ').collect() } else { line.split(' ').collect() };
        let arity = match command { "FORMAT" => None, "BIBLIOGRAPHY" | "EXPORT" => Some(1), "CITE" | "SEARCH" => Some(2), "KEYGEN" | "CHECK" | "STATS" => Some(0), _ => return Err(format!("unknown command '{command}'")) };
        if arity.map_or(words.len() < 3, |n| words.len() != n + 1) { return Err("wrong number of arguments".into()); }
        let style = if matches!(command, "FORMAT" | "BIBLIOGRAPHY" | "CITE") { Style::parse(words[1]).ok_or_else(|| format!("unknown style '{}'", words[1]))? } else { Style::Apa };
        match command {
            "FORMAT" => {
                let (_, numbers) = self.ieee_order();
                Ok(words[2..].iter().map(|key| match self.lookup.get(*key) {
                    Some(&index) => self.entries[index].reference(style, numbers[index], false),
                    None => format!("ERROR unknown key '{key}'"),
                }).collect())
            },
            "BIBLIOGRAPHY" => {
                let (mut order, numbers) = self.ieee_order();
                if style != Style::Ieee { order.sort_by(|&a, &b| self.entries[a].sort_key().cmp(&self.entries[b].sort_key())); }
                let mut result = vec![if style == Style::Mla { "Works Cited" } else { "References" }.into()];
                for (i, &index) in order.iter().enumerate() {
                    let repeated = i > 0 && matches!(style, Style::Chicago | Style::Mla) && self.entries[index].primary() == self.entries[order[i - 1]].primary();
                    result.push(self.entries[index].reference(style, numbers[index], repeated));
                }
                Ok(result)
            },
            "CITE" => Ok(vec![self.cite(style, words[2])?]),
            "KEYGEN" => Ok(self.keygen()), "CHECK" => Ok(self.check()), "EXPORT" => self.export(words[1]), "STATS" => Ok(self.stats()),
            "SEARCH" => {
                let needle = words[2].to_ascii_lowercase();
                let matches: Vec<_> = self.entries.iter().filter(|entry| entry.fields.get(words[1]).is_some_and(|value| plain(value).to_ascii_lowercase().contains(&needle))).map(|entry| entry.key.as_str()).collect();
                Ok(vec![if matches.is_empty() { "MATCHES 0".into() } else { format!("MATCHES {}: {}", matches.len(), matches.join(" ")) }])
            }, _ => unreachable!(),
        }
    }
}
fn main() {
    let mut input = String::new(); io::stdin().read_to_string(&mut input).unwrap();
    let lines: Vec<_> = input.lines().collect();
    let separator = lines.iter().position(|&line| line == "%%").unwrap();
    let mut database = Database::read(&lines[..separator]);
    let count: usize = lines[separator + 1].parse().unwrap();
    for line in &lines[separator + 2..separator + 2 + count] {
        match database.command(line) { Ok(output) => database.output.extend(output), Err(error) => database.output.push(format!("ERROR {error}")) }
    }
    println!("{}", database.output.join("\n"));
}
