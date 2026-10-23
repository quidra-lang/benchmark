use std::cmp::Ordering;
use std::collections::BTreeMap;
use std::io::{self, Read};

#[derive(Clone)]
enum Value {
    Absent,
    String(String),
    Integer(i64),
    Boolean(bool),
    List(Vec<Value>),
    Map(BTreeMap<String, Value>),
}

fn identifier(s: &str) -> bool {
    let mut b = s.bytes();
    b.next().is_some_and(|c| c.is_ascii_alphabetic() || c == b'_')
        && b.all(|c| c.is_ascii_alphanumeric() || c == b'_')
}

fn subscript(s: &str) -> bool {
    s == "0" || (!s.is_empty() && s.as_bytes()[0] != b'0' && s.bytes().all(|c| c.is_ascii_digit()))
}

fn integer_argument(s: &str) -> Option<i64> {
    let digits = s.strip_prefix('-').unwrap_or(s);
    if (1..=9).contains(&digits.len()) && digits.bytes().all(|c| c.is_ascii_digit()) {
        s.parse().ok()
    } else {
        None
    }
}

#[derive(Clone)]
enum Part {
    Key(String),
    Index(usize),
}

fn key_parts(s: &str) -> Option<Vec<(Part, String)>> {
    let b = s.as_bytes();
    let mut at = 0;
    let mut result = Vec::new();
    loop {
        let start = at;
        while at < b.len() && (b[at].is_ascii_alphanumeric() || b[at] == b'_') {
            at += 1;
        }
        if !identifier(&s[start..at]) { return None; }
        result.push((Part::Key(s[start..at].into()), s[..at].into()));
        loop {
            if at == b.len() { return Some(result); }
            match b[at] {
                b'.' => { at += 1; break; }
                b'[' => {
                    let start = at + 1;
                    let end = start + s[start..].find(']')?;
                    if !subscript(&s[start..end]) { return None; }
                    at = end + 1;
                    result.push((Part::Index(s[start..end].parse().ok()?), s[..at].into()));
                }
                _ => return None,
            }
        }
    }
}

fn scalar(s: &str, at: &mut usize) -> Option<Value> {
    let b = s.as_bytes();
    if b.get(*at) == Some(&b'"') {
        *at += 1;
        let mut value = String::new();
        while *at < b.len() {
            let c = b[*at];
            *at += 1;
            if c == b'"' { return Some(Value::String(value)); }
            if c == b'\\' {
                let escaped = *b.get(*at)?;
                *at += 1;
                value.push(match escaped { b'"' => '"', b'\\' => '\\', b'n' => '\n', _ => return None });
            } else {
                value.push(c as char);
            }
        }
        return None;
    }
    let start = *at;
    while *at < b.len() && b[*at] != b',' && b[*at] != b']' { *at += 1; }
    let word = &s[start..*at];
    match word {
        "true" => Some(Value::Boolean(true)),
        "false" => Some(Value::Boolean(false)),
        _ => {
            let digits = word.strip_prefix('-').unwrap_or(word);
            if word != "-0" && subscript(digits) {
                word.parse().ok().map(Value::Integer)
            } else { None }
        }
    }
}

fn parse_value(s: &str) -> Option<Value> {
    if s == "{}" { return Some(Value::Map(BTreeMap::new())); }
    if s == "[]" { return Some(Value::List(Vec::new())); }
    let mut at = 0;
    if s.starts_with('[') {
        at = 1;
        let mut values = Vec::new();
        loop {
            values.push(scalar(s, &mut at)?);
            if s.as_bytes().get(at) == Some(&b']') {
                return (at + 1 == s.len()).then_some(Value::List(values));
            }
            if !s[at..].starts_with(", ") { return None; }
            at += 2;
        }
    }
    let value = scalar(s, &mut at)?;
    (at == s.len()).then_some(value)
}

fn child<'a>(value: &'a Value, part: &Part) -> Option<&'a Value> {
    match (value, part) {
        (Value::Map(map), Part::Key(key)) => map.get(key),
        (Value::List(list), Part::Index(index)) => list.get(*index),
        _ => None,
    }
}

fn assign(container: &mut Value, parts: &[(Part, String)], value: Value) -> Result<(), String> {
    let (part, prefix) = &parts[0];
    if let (Value::List(list), Part::Index(index)) = (&*container, part) {
        if *index > list.len() { return Err(format!("index gap at '{prefix}'")); }
    }
    if parts.len() == 1 {
        match (container, part) {
            (Value::Map(map), Part::Key(key)) => { map.insert(key.clone(), value); }
            (Value::List(list), Part::Index(index)) => {
                if *index == list.len() { list.push(value); } else { list[*index] = value; }
            }
            _ => unreachable!(),
        }
        return Ok(());
    }
    let map_needed = matches!(parts[1].0, Part::Key(_));
    let empty = if map_needed { Value::Map(BTreeMap::new()) } else { Value::List(Vec::new()) };
    let next = match (container, part) {
        (Value::Map(map), Part::Key(key)) => map.entry(key.clone()).or_insert(empty),
        (Value::List(list), Part::Index(index)) => {
            if *index == list.len() { list.push(empty); }
            &mut list[*index]
        }
        _ => unreachable!(),
    };
    if !matches!((&*next, map_needed), (Value::Map(_), true) | (Value::List(_), false)) {
        return Err(format!("type conflict at '{prefix}'"));
    }
    assign(next, &parts[1..], value)
}

fn remove(container: &mut Value, parts: &[(Part, String)]) -> bool {
    let part = &parts[0].0;
    if parts.len() == 1 {
        return match (container, part) {
            (Value::Map(map), Part::Key(key)) => map.remove(key).is_some(),
            (Value::List(list), Part::Index(index)) if *index < list.len() => { list.remove(*index); true }
            _ => false,
        };
    }
    let next = match (container, part) {
        (Value::Map(map), Part::Key(key)) => map.get_mut(key),
        (Value::List(list), Part::Index(index)) => list.get_mut(*index),
        _ => None,
    };
    next.is_some_and(|v| remove(v, &parts[1..]))
}

fn stringify(value: &Value) -> Result<String, String> {
    Ok(match value {
        Value::Absent => String::new(),
        Value::String(s) => s.clone(),
        Value::Integer(n) => n.to_string(),
        Value::Boolean(b) => b.to_string(),
        Value::List(list) => list.iter().map(stringify).collect::<Result<Vec<_>, _>>()?.join(", "),
        Value::Map(_) => return Err("cannot render map".into()),
    })
}

fn truthy(value: &Value) -> bool {
    match value {
        Value::Absent => false,
        Value::String(s) => !s.is_empty(),
        Value::Integer(n) => *n != 0,
        Value::Boolean(b) => *b,
        Value::List(list) => !list.is_empty(),
        Value::Map(map) => !map.is_empty(),
    }
}

fn number(value: &Value, filter: &str) -> Result<i64, String> {
    match value {
        Value::Absent => Ok(0),
        Value::Integer(n) => Ok(*n),
        Value::String(s) => integer_argument(s).ok_or_else(|| format!("not a number for '{filter}'")),
        _ => Err(format!("not a number for '{filter}'")),
    }
}

fn quoted_split(s: &str, separator: char) -> Vec<&str> {
    let mut quoted = false;
    let mut start = 0;
    let mut result = Vec::new();
    for (at, c) in s.char_indices() {
        if c == '\'' { quoted = !quoted; }
        if c == separator && !quoted { result.push(&s[start..at]); start = at + 1; }
    }
    result.push(&s[start..]);
    result
}

fn valid_name(s: &str) -> bool {
    s == "." || ["@index", "@number", "@first", "@last"].contains(&s)
        || s.split('.').all(|p| identifier(p) || subscript(p))
}

#[derive(Clone)]
struct Filter { name: String, args: Vec<Value> }
#[derive(Clone)]
struct Expression { name: String, filters: Vec<Filter> }

fn expression(s: &str) -> Result<Expression, String> {
    let pieces = quoted_split(s, '|');
    let name = pieces[0].trim_matches(' ');
    if !valid_name(name) { return Err(format!("invalid name '{name}'")); }
    let mut filters = Vec::new();
    for piece in &pieces[1..] {
        let items = quoted_split(piece.trim_matches(' '), ':');
        let f = items[0];
        let no_args = ["upper", "lower", "title", "trim", "length", "first", "last", "reverse", "items", "comma", "sum", "min", "max"];
        if !no_args.contains(&f) && !["default", "eq", "pad", "lpad", "truncate", "replace", "join", "sort", "pluck", "add", "sub", "mul", "div", "mod", "gt", "lt"].contains(&f) {
            return Err(format!("unknown filter '{f}'"));
        }
        let args: Option<Vec<Value>> = items[1..].iter().map(|a| {
            if a.len() >= 2 && a.starts_with('\'') && a.ends_with('\'') && !a[1..a.len()-1].contains('\'') {
                Some(Value::String(a[1..a.len()-1].into()))
            } else { integer_argument(a).map(Value::Integer) }
        }).collect();
        let args = args.ok_or_else(|| format!("bad arguments for '{f}'"))?;
        let string = |i: usize| matches!(args.get(i), Some(Value::String(_)));
        let integer = |i: usize| matches!(args.get(i), Some(Value::Integer(_)));
        let nonnegative = |i: usize| matches!(args.get(i), Some(Value::Integer(n)) if *n >= 0);
        let good = if no_args.contains(&f) { args.is_empty() } else {
            match f {
                "default" | "eq" => args.len() == 1,
                "pad" | "lpad" => (args.len() == 1 || args.len() == 2) && nonnegative(0) && (args.len() == 1 || matches!(&args[1], Value::String(s) if s.len() == 1)),
                "truncate" => args.len() == 1 && nonnegative(0),
                "replace" => args.len() == 2 && matches!(&args[0], Value::String(s) if !s.is_empty()) && string(1),
                "join" | "pluck" => args.len() == 1 && string(0),
                "sort" => args.is_empty() || (args.len() == 1 && string(0)),
                "div" | "mod" => args.len() == 1 && matches!(args[0], Value::Integer(n) if n != 0),
                _ => args.len() == 1 && integer(0),
            }
        };
        if !good { return Err(format!("bad arguments for '{f}'")); }
        filters.push(Filter { name: f.into(), args });
    }
    Ok(Expression { name: name.into(), filters })
}

fn sort_order(a: &Value, b: &Value) -> Ordering {
    fn rank(v: &Value) -> u8 { match v { Value::Absent => 0, Value::Integer(_) => 1, Value::String(_) => 2, Value::Boolean(_) => 3, _ => 4 } }
    let order = rank(a).cmp(&rank(b));
    if order != Ordering::Equal { return order; }
    match (a, b) {
        (Value::Integer(a), Value::Integer(b)) => a.cmp(b),
        (Value::String(a), Value::String(b)) => a.cmp(b),
        (Value::Boolean(a), Value::Boolean(b)) => a.cmp(b),
        _ => Ordering::Equal,
    }
}

fn apply_filter(value: Value, f: &Filter) -> Result<Value, String> {
    let name = f.name.as_str();
    let n = || if let Value::Integer(n) = f.args[0] { n } else { unreachable!() };
    let s = |i: usize| if let Value::String(s) = &f.args[i] { s.as_str() } else { unreachable!() };
    Ok(match name {
        "default" => if truthy(&value) { value } else { f.args[0].clone() },
        "eq" => Value::Boolean(stringify(&value)? == stringify(&f.args[0])?),
        "length" => Value::Integer(match &value { Value::List(v) => v.len(), Value::Map(v) => v.len(), _ => stringify(&value)?.len() } as i64),
        "first" | "last" => if let Value::List(list) = value { if name == "first" { list.first() } else { list.last() }.cloned().unwrap_or(Value::Absent) } else { value },
        "reverse" => match value { Value::List(mut list) => { list.reverse(); Value::List(list) }, Value::String(s) => Value::String(s.chars().rev().collect()), _ => value },
        "items" => if let Value::Map(map) = value {
            Value::List(map.into_iter().map(|(k,v)| Value::Map(BTreeMap::from([("key".into(), Value::String(k)), ("value".into(), v)]))).collect())
        } else { value },
        "sort" => if let Value::List(mut list) = value {
            let key = |v: &Value| if f.args.is_empty() { v.clone() } else if let Value::Map(m) = v { m.get(s(0)).cloned().unwrap_or(Value::Absent) } else { Value::Absent };
            list.sort_by(|a,b| sort_order(&key(a), &key(b)));
            Value::List(list)
        } else { value },
        "pluck" => if let Value::List(list) = value { Value::List(list.into_iter().map(|v| if let Value::Map(m) = v { m.get(s(0)).cloned().unwrap_or(Value::Absent) } else { Value::Absent }).collect()) } else { value },
        "sum" | "min" | "max" => if let Value::List(list) = value {
            let values = list.iter().map(|v| number(v, name)).collect::<Result<Vec<_>, _>>()?;
            match name { "sum" => Value::Integer(values.iter().sum()), "min" => values.into_iter().min().map_or(Value::Absent, Value::Integer), _ => values.into_iter().max().map_or(Value::Absent, Value::Integer) }
        } else { Value::Integer(number(&value, name)?) },
        "add" | "sub" | "mul" | "div" | "mod" | "gt" | "lt" => {
            let a = number(&value, name)?;
            let b = n();
            let floor = || { let q = a / b; if a % b != 0 && (a < 0) != (b < 0) { q - 1 } else { q } };
            match name { "add" => Value::Integer(a+b), "sub" => Value::Integer(a-b), "mul" => Value::Integer(a*b), "div" => Value::Integer(floor()), "mod" => Value::Integer(a-b*floor()), "gt" => Value::Boolean(a>b), _ => Value::Boolean(a<b) }
        }
        "comma" => {
            let a = number(&value, name)?;
            let digits = a.abs().to_string();
            let mut result = if a < 0 { "-".to_string() } else { String::new() };
            for (i,c) in digits.chars().enumerate() { if i > 0 && (digits.len()-i)%3 == 0 { result.push(','); } result.push(c); }
            Value::String(result)
        }
        "join" => Value::String(if let Value::List(list) = &value { list.iter().map(stringify).collect::<Result<Vec<_>, _>>()?.join(s(0)) } else { stringify(&value)? }),
        _ => {
            let text = stringify(&value)?;
            Value::String(match name {
                "upper" => text.to_ascii_uppercase(), "lower" => text.to_ascii_lowercase(), "trim" => text.trim_matches(' ').into(),
                "title" => { let mut first = true; text.chars().map(|c| { let result = if first { c.to_ascii_uppercase() } else { c.to_ascii_lowercase() }; first = c == ' '; result }).collect() },
                "pad" | "lpad" => { let padding = (if f.args.len() == 2 { s(1) } else { " " }).repeat((n() as usize).saturating_sub(text.len())); if name == "pad" { text + &padding } else { padding + &text } },
                "truncate" => if text.len() > n() as usize { format!("{}...", &text[..n() as usize]) } else { text },
                "replace" => text.replace(s(0), s(1)),
                _ => unreachable!(),
            })
        }
    })
}

#[derive(Clone)]
struct Token {
    kind: char,
    text: String,
    expr: Option<Expression>,
    line: usize,
    indent: String,
    end: usize,
}
type Source = Vec<(usize, String)>;
type Failure = (usize, String);

fn analyze(source: &Source) -> Result<Vec<Token>, Failure> {
    let mut open = "{{".to_string();
    let mut close = "}}".to_string();
    let mut stack: Vec<(String, usize)> = Vec::new();
    let mut tokens = Vec::new();
    for (line, text) in source {
        let mut row = Vec::new();
        let mut at = 0;
        while let Some(relative) = text[at..].find(&open) {
            let start = at + relative;
            row.push(Token { kind: 't', text: text[at..start].into(), expr: None, line: *line, indent: String::new(), end: 0 });
            let mut begin = start + open.len();
            let triple = text[begin..].starts_with('{');
            if triple { begin += 1; }
            let ending = if triple { format!("}}{close}") } else { close.clone() };
            let finish = begin + text[begin..].find(&ending).ok_or((*line, "unclosed tag".into()))?;
            let content = text[begin..finish].trim_matches(' ');
            at = finish + ending.len();
            let (kind, arg) = if triple { ('&', content) } else if content.as_bytes().first().is_some_and(|c| b"#^/!>&=".contains(c)) { (content.as_bytes()[0] as char, content[1..].trim_matches(' ')) } else { ('v', content) };
            let mut expr = None;
            match kind {
                'v' | '&' | '#' | '^' => {
                    let parsed = expression(arg).map_err(|e| (*line,e))?;
                    if kind == '#' || kind == '^' { stack.push((parsed.name.clone(), *line)); }
                    expr = Some(parsed);
                }
                '/' => {
                    if !valid_name(arg) { return Err((*line, format!("invalid name '{arg}'"))); }
                    let Some((name,_)) = stack.last() else { return Err((*line, format!("unexpected closing '{arg}'"))); };
                    if name != arg { return Err((*line, format!("mismatched closing '{arg}', expected '{name}'"))); }
                    stack.pop();
                }
                '>' => if !identifier(arg) { return Err((*line, format!("invalid name '{arg}'"))); },
                '=' => {
                    if content.len() < 2 || !content.ends_with('=') { return Err((*line, "invalid delimiters".into())); }
                    let pair: Vec<_> = content[1..content.len()-1].split(' ').filter(|s| !s.is_empty()).collect();
                    if pair.len() != 2 || pair.iter().any(|s| s.contains('=')) { return Err((*line, "invalid delimiters".into())); }
                    open = pair[0].into(); close = pair[1].into();
                }
                _ => {}
            }
            row.push(Token { kind, text: arg.into(), expr, line: *line, indent: String::new(), end: 0 });
        }
        row.push(Token { kind: 't', text: text[at..].into(), expr: None, line: *line, indent: String::new(), end: 0 });
        let tag_positions: Vec<_> = row.iter().enumerate().filter(|(_,t)| t.kind != 't').map(|(i,_)| i).collect();
        let standalone = tag_positions.len() == 1 && "#^/!>=".contains(row[tag_positions[0]].kind) && row.iter().filter(|t| t.kind == 't').all(|t| t.text.bytes().all(|c| c == b' '));
        if standalone {
            let position = tag_positions[0];
            let mut tag = row[position].clone();
            if tag.kind == '>' { tag.indent = row[..position].iter().map(|t| t.text.as_str()).collect(); }
            tokens.push(tag);
        } else {
            tokens.extend(row);
            tokens.push(Token { kind: 't', text: "\n".into(), expr: None, line: *line, indent: String::new(), end: 0 });
        }
    }
    if let Some((name,line)) = stack.last() { return Err((*line, format!("unclosed section '{name}'"))); }
    let mut openings = Vec::new();
    for i in 0..tokens.len() {
        if tokens[i].kind == '#' || tokens[i].kind == '^' { openings.push(i); }
        if tokens[i].kind == '/' { let start = openings.pop().unwrap(); tokens[start].end = i; }
    }
    Ok(tokens)
}

fn resolve(name: &str, contexts: &[Value], loops: &[(usize,usize)]) -> Option<Value> {
    if name == "." { return contexts.last().cloned(); }
    if name.starts_with('@') {
        let &(i,n) = loops.last()?;
        return Some(match name { "@index" => Value::Integer(i as i64), "@number" => Value::Integer(i as i64+1), "@first" => Value::Boolean(i==0), _ => Value::Boolean(i+1==n) });
    }
    let parts: Vec<_> = name.split('.').map(|p| if subscript(p) { Part::Index(p.parse().unwrap_or(usize::MAX)) } else { Part::Key(p.into()) }).collect();
    let mut value = contexts.iter().rev().find_map(|v| child(v, &parts[0]))?;
    for part in &parts[1..] { value = child(value, part)?; }
    Some(value.clone())
}

fn escape(s: &str) -> String {
    s.chars().map(|c| match c { '&' => "&amp;".into(), '<' => "&lt;".into(), '>' => "&gt;".into(), '"' => "&quot;".into(), '\'' => "&#39;".into(), _ => c.to_string() }).collect()
}

fn render(tokens: &[Token], start: usize, end: usize, contexts: &mut Vec<Value>, loops: &mut Vec<(usize,usize)>, partials: &BTreeMap<String, Source>, strict: bool, depth: usize) -> Result<String, Failure> {
    let mut result = String::new();
    let mut at = start;
    while at < end {
        let tag = &tokens[at];
        match tag.kind {
            't' => result.push_str(&tag.text),
            'v' | '&' | '#' | '^' => {
                let expr = tag.expr.as_ref().unwrap();
                let found = resolve(&expr.name, contexts, loops);
                if strict && (tag.kind == 'v' || tag.kind == '&') && found.is_none() { return Err((tag.line, format!("missing '{}'", expr.name))); }
                let mut value = found.unwrap_or(Value::Absent);
                for filter in &expr.filters { value = apply_filter(value, filter).map_err(|e| (tag.line,e))?; }
                if tag.kind == 'v' || tag.kind == '&' {
                    let text = stringify(&value).map_err(|e| (tag.line,e))?;
                    result.push_str(&if tag.kind == 'v' { escape(&text) } else { text });
                } else {
                    if tag.kind == '^' {
                        if !truthy(&value) { result.push_str(&render(tokens, at+1, tag.end, contexts, loops, partials, strict, depth)?); }
                    } else if let Value::List(list) = value {
                        let n = list.len();
                        for (i,item) in list.into_iter().enumerate() {
                            contexts.push(item); loops.push((i,n));
                            let text = render(tokens, at+1, tag.end, contexts, loops, partials, strict, depth)?;
                            contexts.pop(); loops.pop(); result.push_str(&text);
                        }
                    } else if truthy(&value) {
                        contexts.push(value);
                        let text = render(tokens, at+1, tag.end, contexts, loops, partials, strict, depth)?;
                        contexts.pop(); result.push_str(&text);
                    }
                    at = tag.end;
                }
            }
            '>' => {
                let source = partials.get(&tag.text).ok_or((tag.line, format!("unknown partial '{}'",tag.text)))?;
                if depth == 8 { return Err((tag.line, format!("partial depth exceeded at '{}'",tag.text))); }
                let indented = source.iter().map(|(line,text)| (*line, if text.is_empty() { text.clone() } else { tag.indent.clone()+text })).collect();
                let parsed = analyze(&indented)?;
                result.push_str(&render(&parsed, 0, parsed.len(), contexts, loops, partials, strict, depth+1)?);
            }
            _ => {}
        }
        at += 1;
    }
    Ok(result)
}

fn dump(value: &Value, path: &str, leaves: &mut Vec<String>) {
    match value {
        Value::Map(map) if !map.is_empty() => for (key,v) in map { dump(v, &if path.is_empty() { key.clone() } else { format!("{path}.{key}") }, leaves); },
        Value::List(list) if !list.is_empty() => for (i,v) in list.iter().enumerate() { dump(v, &format!("{path}[{i}]"), leaves); },
        _ if !path.is_empty() => {
            let notation = match value { Value::String(s) => format!("\"{}\"", s.replace('\\',"\\\\").replace('"',"\\\"").replace('\n',"\\n")), Value::Map(_) => "{}".into(), Value::List(_) => "[]".into(), _ => stringify(value).unwrap() };
            leaves.push(format!("{path} = {notation}"));
        }
        _ => {}
    }
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let lines: Vec<_> = input.lines().collect();
    let mut at = 0;
    let mut root = Value::Map(BTreeMap::new());
    let mut partials = BTreeMap::new();
    let mut templates = BTreeMap::new();
    let mut strict = false;
    while at < lines.len() {
        let command = lines[at];
        let line_number = at+1;
        at += 1;
        if command == "END" { break; }
        if command == "DATA" {
            let mut set = 0;
            let mut unset = 0;
            let mut errors = Vec::new();
            while lines[at] != "ENDDATA" {
                let line = lines[at];
                let number = at+1;
                at += 1;
                if line.is_empty() || line.starts_with('#') { continue; }
                let deletion = line.starts_with("UNSET ");
                let parsed = if deletion { Ok((&line[6..], None)) } else { line.split_once(" = ").map(|(k,v)| (k,Some(v))).ok_or("bad line".to_string()) };
                let operation = parsed.and_then(|(key,notation)| {
                    let parts = key_parts(key).ok_or_else(|| format!("bad key '{key}'"))?;
                    if let Some(notation) = notation {
                        let value = parse_value(notation).ok_or_else(|| format!("bad value '{notation}'"))?;
                        let mut changed = root.clone();
                        assign(&mut changed, &parts, value)?;
                        root = changed;
                    } else if !remove(&mut root, &parts) { return Err(format!("no value at '{key}'")); }
                    Ok(())
                });
                match operation { Ok(()) => if deletion { unset += 1; } else { set += 1; }, Err(reason) => errors.push(format!("ERROR line {number}: {reason}")) }
            }
            at += 1;
            println!("DATA set={set} unset={unset} errors={}", errors.len());
            for error in errors { println!("{error}"); }
        } else if command.starts_with("PARTIAL ") || command.starts_with("TEMPLATE ") {
            let partial = command.starts_with("PARTIAL ");
            let name = command.split_once(' ').unwrap().1;
            let end = if partial { "ENDPARTIAL" } else { "ENDTEMPLATE" };
            let mut source = Source::new();
            while lines[at] != end { source.push((at+1,lines[at].into())); at += 1; }
            at += 1;
            if partial {
                match analyze(&source) {
                    Err((line,reason)) => println!("PARTIAL {name} ERROR line {line}: {reason}"),
                    Ok(_) => { let action = if partials.contains_key(name) { "REPLACED" } else { "DEFINED" }; println!("PARTIAL {name} {action} lines={}",source.len()); partials.insert(name.into(),source); }
                }
            } else {
                templates.insert(name.to_string(), source);
                output_template(name, templates.get(name).unwrap(), &root, &partials, strict);
            }
        } else if let Some(name) = command.strip_prefix("RENDER ") {
            if let Some(source) = templates.get(name) { output_template(name, source, &root, &partials, strict); }
            else { println!("TEMPLATE {name} ERROR line {line_number}: unknown template '{name}'"); }
        } else if command == "DUMP" {
            let mut leaves = Vec::new(); dump(&root,"",&mut leaves);
            println!("DUMP leaves={}",leaves.len()); for leaf in leaves { println!("{leaf}"); }
        } else if command == "RESET" {
            root = Value::Map(BTreeMap::new()); partials.clear(); templates.clear(); println!("RESET");
        } else {
            strict = command == "STRICT ON"; println!("{command}");
        }
    }
}

fn output_template(name: &str, source: &Source, root: &Value, partials: &BTreeMap<String,Source>, strict: bool) {
    let result = analyze(source).and_then(|tokens| render(&tokens,0,tokens.len(),&mut vec![root.clone()],&mut Vec::new(),partials,strict,0));
    match result {
        Err((line,reason)) => println!("TEMPLATE {name} ERROR line {line}: {reason}"),
        Ok(text) => {
            let lines = if text.is_empty() { 0 } else { text.bytes().filter(|&c| c==b'\n').count() + usize::from(!text.ends_with('\n')) };
            println!("TEMPLATE {name} OK lines={lines} chars={}",text.len());
            if !text.is_empty() { print!("{text}"); if !text.ends_with('\n') { println!(); } }
        }
    }
}
