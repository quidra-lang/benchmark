use std::collections::BTreeMap;
use std::fmt::Write as FmtWrite;
use std::io::{self, Read, Write};

type Result<T> = std::result::Result<T, String>;
const MAX_UNSIGNED: i64 = 9_007_199_254_740_991;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Scalar { Uint32, Uint64, Sint32, Sint64, Bool, Fixed32, Sfixed32, Fixed64, String, Bytes }

impl Scalar {
    fn wire(self) -> u8 {
        match self {
            Self::Fixed64 => 1,
            Self::String | Self::Bytes => 2,
            Self::Fixed32 | Self::Sfixed32 => 5,
            _ => 0,
        }
    }
    fn contains(self, number: i64) -> bool {
        match self {
            Self::Uint32 | Self::Fixed32 => (0..=4_294_967_295).contains(&number),
            Self::Uint64 | Self::Fixed64 => (0..=MAX_UNSIGNED).contains(&number),
            Self::Sint32 | Self::Sfixed32 => (-2_147_483_648..=2_147_483_647).contains(&number),
            Self::Sint64 => (-4_503_599_627_370_496..=4_503_599_627_370_495).contains(&number),
            _ => true,
        }
    }
}

struct Field {
    number: i64,
    name: String,
    typ: usize,
    required: bool,
    repeated: bool,
    packed: bool,
    group: Option<String>,
}
enum Definition { Scalar(Scalar), Enum(BTreeMap<i64, String>), Message(Vec<Field>) }
struct Type { name: String, definition: Definition }
struct Schema { types: Vec<Type>, names: BTreeMap<String, usize> }

impl Schema {
    fn fields(&self, typ: usize) -> &[Field] {
        match &self.types[typ].definition { Definition::Message(fields) => fields, _ => &[] }
    }
    fn is_message(&self, typ: usize) -> bool { matches!(&self.types[typ].definition, Definition::Message(_)) }
    fn scalar(&self, typ: usize) -> Option<Scalar> {
        match &self.types[typ].definition { Definition::Scalar(value) => Some(*value), _ => None }
    }
    fn wire(&self, typ: usize) -> u8 {
        match &self.types[typ].definition { Definition::Scalar(value) => value.wire(), Definition::Enum(_) => 0, Definition::Message(_) => 2 }
    }
    fn enum_name(&self, typ: usize, number: i64) -> Option<&str> {
        match &self.types[typ].definition { Definition::Enum(values) => values.get(&number).map(String::as_str), _ => None }
    }
    fn read(lines: &mut std::str::Lines<'_>) -> Self {
        let mut schema = Self { types: Vec::new(), names: BTreeMap::new() };
        for (name, scalar) in [
            ("uint32", Scalar::Uint32), ("uint64", Scalar::Uint64), ("sint32", Scalar::Sint32),
            ("sint64", Scalar::Sint64), ("bool", Scalar::Bool), ("fixed32", Scalar::Fixed32),
            ("sfixed32", Scalar::Sfixed32), ("fixed64", Scalar::Fixed64), ("string", Scalar::String), ("bytes", Scalar::Bytes),
        ] {
            schema.names.insert(name.into(), schema.types.len());
            schema.types.push(Type { name: name.into(), definition: Definition::Scalar(scalar) });
        }
        let mut pending = Vec::new();
        let mut current = 0;
        for line in lines.by_ref() {
            if line == "END SCHEMA" { break; }
            let words: Vec<_> = line.split(' ').collect();
            match words[0] {
                "ENUM" | "MESSAGE" => {
                    current = schema.types.len();
                    schema.names.insert(words[1].into(), current);
                    let definition = if words[0] == "ENUM" { Definition::Enum(BTreeMap::new()) } else { Definition::Message(Vec::new()) };
                    schema.types.push(Type { name: words[1].into(), definition });
                }
                "VALUE" => if let Definition::Enum(values) = &mut schema.types[current].definition {
                    values.insert(words[2].parse().unwrap(), words[1].into());
                },
                "FIELD" => if let Definition::Message(fields) = &mut schema.types[current].definition {
                    pending.push((current, fields.len(), words[2].to_owned()));
                    let mode = words.get(4).copied().unwrap_or("");
                    fields.push(Field {
                        number: words[1].parse().unwrap(), name: words[3].into(), typ: 0,
                        required: mode == "REQUIRED", repeated: mode == "REPEATED",
                        packed: mode == "REPEATED" && words.len() == 6,
                        group: (mode == "ONEOF").then(|| words[5].to_owned()),
                    });
                },
                _ => {},
            }
        }
        for (owner, index, name) in pending {
            if let Definition::Message(fields) = &mut schema.types[owner].definition { fields[index].typ = schema.names[&name]; }
        }
        for typ in &mut schema.types {
            if let Definition::Message(fields) = &mut typ.definition { fields.sort_by_key(|field| field.number); }
        }
        schema
    }
}

enum Value { Number(i64), Boolean(bool), Binary(Vec<u8>), Message(Message) }
struct Unknown { number: i64, wire: u8, integer: i64, bytes: Vec<u8> }
struct Message { typ: usize, fields: Vec<Vec<Value>>, unknown: Vec<Unknown> }

impl Message {
    fn new(typ: usize, schema: &Schema) -> Self {
        Self { typ, fields: (0..schema.fields(typ).len()).map(|_| Vec::new()).collect(), unknown: Vec::new() }
    }
    fn choose(&mut self, index: usize, schema: &Schema) {
        let fields = schema.fields(self.typ);
        if let Some(group) = &fields[index].group {
            for (i, field) in fields.iter().enumerate() {
                if i != index && field.group.as_ref() == Some(group) { self.fields[i].clear(); }
            }
        }
    }
    fn apply(&mut self, index: usize, mut values: Vec<Value>, schema: &Schema) {
        if values.is_empty() { return; }
        self.choose(index, schema);
        let field = &schema.fields(self.typ)[index];
        let old = &mut self.fields[index];
        if field.repeated { old.extend(values); }
        else if schema.is_message(field.typ) && !old.is_empty() {
            if let (Value::Message(existing), Value::Message(incoming)) = (&mut old[0], values.pop().unwrap()) { existing.merge(incoming, schema); }
        } else { *old = values; }
    }
    fn merge(&mut self, incoming: Message, schema: &Schema) {
        for (i, values) in incoming.fields.into_iter().enumerate() { self.apply(i, values, schema); }
        self.unknown.extend(incoming.unknown);
    }
    fn required(&self, schema: &Schema, prefix: &str) -> Result<()> {
        for (i, field) in schema.fields(self.typ).iter().enumerate() {
            let values = &self.fields[i];
            let path = format!("{prefix}{}", field.name);
            if field.required && values.is_empty() { return Err(format!("missing required field {path}")); }
            for (j, value) in values.iter().enumerate() {
                if let Value::Message(child) = value {
                    let next = if field.repeated { format!("{path}[{j}].") } else { format!("{path}.") };
                    child.required(schema, &next)?;
                }
            }
        }
        Ok(())
    }
}

fn zigzag(value: i64) -> i64 { if value >= 0 { value * 2 } else { -value * 2 - 1 } }
fn unzigzag(value: i64) -> i64 { if value % 2 == 0 { value / 2 } else { -1 - value / 2 } }
fn put_varint(output: &mut Vec<u8>, mut value: i64) {
    while value >= 128 { output.push((value % 128 + 128) as u8); value /= 128; }
    output.push(value as u8);
}
fn encode_element(output: &mut Vec<u8>, typ: usize, value: &Value, schema: &Schema) {
    match value {
        Value::Message(message) => {
            let bytes = encode(message, schema); put_varint(output, bytes.len() as i64); output.extend(bytes);
        }
        Value::Binary(bytes) => { put_varint(output, bytes.len() as i64); output.extend(bytes); }
        _ => {
            let mut number = match value { Value::Number(n) => *n, Value::Boolean(b) => i64::from(*b), _ => unreachable!() };
            if matches!(schema.scalar(typ), Some(Scalar::Sint32 | Scalar::Sint64)) { number = zigzag(number); }
            if schema.scalar(typ) == Some(Scalar::Sfixed32) && number < 0 { number += 4_294_967_296; }
            let wire = schema.wire(typ);
            if wire == 0 { put_varint(output, number); }
            else { output.extend_from_slice(&number.to_le_bytes()[..if wire == 1 { 8 } else { 4 }]); }
        }
    }
}
fn encode_field(field: &Field, values: &[Value], schema: &Schema) -> Vec<u8> {
    let mut output = Vec::new();
    if values.is_empty() { return output; }
    if field.packed {
        let mut payload = Vec::new();
        for value in values { encode_element(&mut payload, field.typ, value, schema); }
        put_varint(&mut output, field.number * 8 + 2); put_varint(&mut output, payload.len() as i64); output.extend(payload);
    } else {
        for value in values {
            put_varint(&mut output, field.number * 8 + i64::from(schema.wire(field.typ)));
            encode_element(&mut output, field.typ, value, schema);
        }
    }
    output
}
fn encode(message: &Message, schema: &Schema) -> Vec<u8> {
    let mut output = Vec::new();
    for (i, field) in schema.fields(message.typ).iter().enumerate() { output.extend(encode_field(field, &message.fields[i], schema)); }
    for unknown in &message.unknown {
        put_varint(&mut output, unknown.number * 8 + i64::from(unknown.wire));
        if unknown.wire == 0 { put_varint(&mut output, unknown.integer); }
        else {
            if unknown.wire == 2 { put_varint(&mut output, unknown.bytes.len() as i64); }
            output.extend(&unknown.bytes);
        }
    }
    output
}
fn hex_digits(bytes: &[u8]) -> String { bytes.iter().map(|byte| format!("{byte:02x}")).collect() }
fn hex(bytes: &[u8]) -> String { if bytes.is_empty() { "-".into() } else { hex_digits(bytes) } }
fn byte_notation(bytes: &[u8]) -> String { format!("<{}>", hex_digits(bytes)) }
fn quote(bytes: &[u8], json: bool) -> String {
    let mut output = String::from("\"");
    for &byte in bytes {
        match byte {
            b'"' => output.push_str("\\\""), b'\\' => output.push_str("\\\\"), b'\n' => output.push_str("\\n"), b'\t' => output.push_str("\\t"),
            32..=126 => output.push(char::from(byte)),
            _ => { write!(output, "{}{:02x}", if json { "\\u00" } else { "\\x" }, byte).unwrap(); }
        }
    }
    output.push('"'); output
}
fn base64(bytes: &[u8]) -> String {
    const ALPHABET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut result = String::new();
    for chunk in bytes.chunks(3) {
        let number = u32::from(chunk[0]) * 65536 + u32::from(*chunk.get(1).unwrap_or(&0)) * 256 + u32::from(*chunk.get(2).unwrap_or(&0));
        result.push(char::from(ALPHABET[(number / 262144) as usize]));
        result.push(char::from(ALPHABET[(number / 4096 % 64) as usize]));
        result.push(if chunk.len() > 1 { char::from(ALPHABET[(number / 64 % 64) as usize]) } else { '=' });
        result.push(if chunk.len() > 2 { char::from(ALPHABET[(number % 64) as usize]) } else { '=' });
    }
    result
}
fn notation(typ: usize, value: &Value, json: bool, schema: &Schema) -> String {
    match value {
        Value::Number(number) => {
            if let Some(name) = schema.enum_name(typ, *number) { if json { format!("\"{name}\"") } else { name.into() } }
            else if json && matches!(schema.scalar(typ), Some(Scalar::Uint64 | Scalar::Sint64 | Scalar::Fixed64)) { format!("\"{number}\"") }
            else { number.to_string() }
        }
        Value::Boolean(state) => state.to_string(),
        Value::Binary(bytes) => if schema.scalar(typ) == Some(Scalar::String) { quote(bytes, json) }
            else if json { format!("\"{}\"", base64(bytes)) } else { byte_notation(bytes) },
        Value::Message(message) => message_notation(message, json, schema),
    }
}
fn sequence_notation(typ: usize, values: &[Value], json: bool, schema: &Schema) -> String {
    format!("[{}]", values.iter().map(|value| notation(typ, value, json, schema)).collect::<Vec<_>>().join(if json { "," } else { ", " }))
}
fn message_notation(message: &Message, json: bool, schema: &Schema) -> String {
    let mut items = Vec::new();
    for (i, field) in schema.fields(message.typ).iter().enumerate() {
        let values = &message.fields[i];
        if values.is_empty() { continue; }
        let key = if json {
            let mut name = String::new(); let mut uppercase = false;
            for c in field.name.chars() {
                if c == '_' { uppercase = true; }
                else { name.push(if uppercase { c.to_ascii_uppercase() } else { c }); uppercase = false; }
            }
            format!("\"{name}\":")
        } else { format!("{}: ", field.name) };
        let value = if field.repeated { sequence_notation(field.typ, values, json, schema) } else { notation(field.typ, &values[0], json, schema) };
        items.push(key + &value);
    }
    format!("{{{}}}", items.join(if json { "," } else { ", " }))
}
fn wire_name(wire: u8) -> &'static str { match wire { 0 => "varint", 1 => "i64", 2 => "len", _ => "i32" } }
fn text_contents(message: &Message, depth: usize, schema: &Schema, lines: &mut Vec<String>) {
    let indent = "  ".repeat(depth);
    for (i, field) in schema.fields(message.typ).iter().enumerate() {
        for value in &message.fields[i] {
            if let Value::Message(child) = value {
                lines.push(format!("{indent}{} {{", field.name)); text_contents(child, depth + 1, schema, lines); lines.push(format!("{indent}}}"));
            } else { lines.push(format!("{indent}{}: {}", field.name, notation(field.typ, value, false, schema))); }
        }
    }
    for unknown in &message.unknown {
        let raw = if unknown.wire == 0 { unknown.integer.to_string() } else { byte_notation(&unknown.bytes) };
        lines.push(format!("{indent}{}: {} {raw}", unknown.number, wire_name(unknown.wire)));
    }
}
fn text_message(message: &Message, schema: &Schema) -> Vec<String> {
    let mut lines = vec![format!("{} {{", schema.types[message.typ].name)];
    text_contents(message, 1, schema, &mut lines); lines.push("}".into()); lines
}

struct Raw<'a> { integer: i64, bytes: &'a [u8], position: usize, payload: usize }
struct Decoder<'a> { data: &'a [u8], schema: &'a Schema, explain: bool, lines: Vec<String> }
fn byte_error(reason: &str, position: usize) -> String { format!("{reason} at byte {position}") }

impl<'a> Decoder<'a> {
    fn varint(&self, position: &mut usize, end: usize) -> Result<i64> {
        let start = *position; let mut number = 0;
        for i in 0..8 {
            if *position >= end { return Err(byte_error("truncated varint", start)); }
            let byte = self.data[*position]; *position += 1;
            number += i64::from(byte & 127) << (7 * i);
            if byte < 128 {
                if number > MAX_UNSIGNED { return Err(byte_error("varint too large", start)); }
                return Ok(number);
            }
        }
        Err(byte_error("varint too long", start))
    }
    fn raw(&self, wire: u8, position: &mut usize, end: usize) -> Result<Raw<'a>> {
        let start = *position;
        if wire == 0 { return Ok(Raw { integer: self.varint(position, end)?, bytes: &[], position: start, payload: start }); }
        let length = if wire == 2 { self.varint(position, end)? } else if wire == 1 { 8 } else { 4 };
        if length > (end - *position) as i64 {
            return Err(byte_error(match wire { 2 => "length past end", 1 => "truncated i64", _ => "truncated i32" }, start));
        }
        let payload = *position; *position += length as usize;
        Ok(Raw { integer: 0, bytes: &self.data[payload..*position], position: start, payload })
    }
    fn convert(&self, typ: usize, raw: Raw<'_>) -> Result<Value> {
        let scalar = self.schema.scalar(typ);
        if matches!(scalar, Some(Scalar::String | Scalar::Bytes)) {
            if scalar == Some(Scalar::String) {
                if let Some(i) = raw.bytes.iter().position(|&byte| byte >= 128) { return Err(byte_error("invalid string", raw.payload + i)); }
            }
            return Ok(Value::Binary(raw.bytes.to_vec()));
        }
        let mut number = raw.integer;
        if matches!(self.schema.wire(typ), 1 | 5) {
            if scalar == Some(Scalar::Fixed64) && (raw.bytes[7] != 0 || raw.bytes[6] >= 32) { return Err(byte_error("value out of range", raw.position)); }
            number = raw.bytes.iter().rev().fold(0, |value, &byte| value * 256 + i64::from(byte));
        }
        if matches!(scalar, Some(Scalar::Sint32 | Scalar::Sint64)) { number = unzigzag(number); }
        if scalar == Some(Scalar::Sfixed32) && number >= 2_147_483_648 { number -= 4_294_967_296; }
        if scalar.is_some_and(|kind| !kind.contains(number)) || (scalar == Some(Scalar::Bool) && number > 1) { return Err(byte_error("value out of range", raw.position)); }
        if matches!(&self.schema.types[typ].definition, Definition::Enum(_)) && self.schema.enum_name(typ, number).is_none() { return Err(byte_error("unknown enum number", raw.position)); }
        Ok(if scalar == Some(Scalar::Bool) { Value::Boolean(number != 0) } else { Value::Number(number) })
    }
    fn message(&mut self, typ: usize, mut position: usize, end: usize, depth: usize) -> Result<Message> {
        let schema = self.schema;
        let mut message = Message::new(typ, schema);
        while position < end {
            let start = position; let tag = self.varint(&mut position, end)?;
            let number = tag / 8; let wire = (tag % 8) as u8;
            if number == 0 { return Err(byte_error("invalid field number", start)); }
            if !matches!(wire, 0 | 1 | 2 | 5) { return Err(byte_error("invalid wire type", start)); }
            let index = schema.fields(typ).iter().position(|field| field.number == number);
            let field = index.map(|i| &schema.fields(typ)[i]);
            let packed = field.is_some_and(|field| field.repeated && schema.wire(field.typ) != 2 && wire == 2);
            if field.is_some_and(|field| wire != schema.wire(field.typ) && !packed) { return Err(byte_error("wire type mismatch", start)); }
            let raw = self.raw(wire, &mut position, end)?;
            let mut header = format!("{}{start} {number} {} {}", "  ".repeat(depth), field.map_or("?", |field| field.name.as_str()), wire_name(wire));
            if wire == 2 { write!(header, " {}", raw.bytes.len()).unwrap(); }
            let Some(field) = field else {
                if self.explain {
                    let value = if wire == 0 { raw.integer.to_string() } else { byte_notation(raw.bytes) };
                    self.lines.push(format!("{header} {value}"));
                } else { message.unknown.push(Unknown { number, wire, integer: raw.integer, bytes: raw.bytes.to_vec() }); }
                continue;
            };
            let mut values = Vec::new();
            if schema.is_message(field.typ) {
                if self.explain { self.lines.push(header); }
                values.push(Value::Message(self.message(field.typ, raw.payload, raw.payload + raw.bytes.len(), depth + 1)?));
            } else {
                if packed {
                    let mut element = raw.payload; let limit = raw.payload + raw.bytes.len();
                    while element < limit { values.push(self.convert(field.typ, self.raw(schema.wire(field.typ), &mut element, limit)?)?); }
                } else { values.push(self.convert(field.typ, raw)?); }
                if self.explain {
                    if packed { header.push_str(" packed"); }
                    for value in &values { header.push(' '); header.push_str(&notation(field.typ, value, false, schema)); }
                    self.lines.push(header);
                }
            }
            if !self.explain { message.apply(index.unwrap(), values, schema); }
        }
        Ok(message)
    }
}
fn decode(typ: usize, bytes: &[u8], schema: &Schema) -> Result<Message> {
    let mut decoder = Decoder { data: bytes, schema, explain: false, lines: Vec::new() };
    let message = decoder.message(typ, 0, bytes.len(), 0)?; message.required(schema, "")?; Ok(message)
}

#[derive(Clone)]
enum TokenKind { Symbol(u8), Integer(i64), Name(String), String(Vec<u8>), Bytes(Vec<u8>), End }
#[derive(Clone)]
struct Token { kind: TokenKind, column: usize }
#[derive(PartialEq, Eq)]
enum Shape { None, Message, List, Integer, Boolean, Name, String, Bytes }
impl Token {
    fn shape(&self) -> Shape {
        match &self.kind {
            TokenKind::Symbol(b'{') => Shape::Message, TokenKind::Symbol(b'[') => Shape::List,
            TokenKind::Integer(_) => Shape::Integer,
            TokenKind::Name(name) => if name == "true" || name == "false" { Shape::Boolean } else { Shape::Name },
            TokenKind::String(_) => Shape::String, TokenKind::Bytes(_) => Shape::Bytes, _ => Shape::None,
        }
    }
}
fn column_error(reason: &str, column: usize) -> String { format!("{reason} at column {column}") }
fn hex_digit(byte: u8) -> Option<u8> {
    match byte { b'0'..=b'9' => Some(byte - b'0'), b'a'..=b'f' => Some(byte - b'a' + 10), _ => None }
}
fn tokenize(source: &str) -> Result<Vec<Token>> {
    let text = source.as_bytes(); let mut position = 0; let mut tokens = Vec::new();
    while position < text.len() {
        let c = text[position];
        if c == b' ' { position += 1; continue; }
        let start = position; position += 1;
        let syntax = || column_error("syntax error", start + 1);
        let kind = if b"{}[]:,".contains(&c) { TokenKind::Symbol(c) }
        else if c == b'"' {
            let mut bytes = Vec::new();
            while position < text.len() && text[position] != b'"' {
                let mut byte = text[position]; position += 1;
                if byte == b'\\' {
                    let escaped = *text.get(position).ok_or_else(syntax)?; position += 1;
                    byte = match escaped {
                        b'"' | b'\\' => escaped, b'n' => b'\n', b't' => b'\t',
                        b'x' => {
                            let high = text.get(position).copied().and_then(hex_digit).ok_or_else(syntax)?;
                            let low = text.get(position + 1).copied().and_then(hex_digit).ok_or_else(syntax)?;
                            if high >= 8 { return Err(syntax()); }
                            position += 2; high * 16 + low
                        }
                        _ => return Err(syntax()),
                    };
                }
                bytes.push(byte);
            }
            if position == text.len() { return Err(syntax()); }
            position += 1; TokenKind::String(bytes)
        } else if c == b'<' {
            let end = text[position..].iter().position(|&byte| byte == b'>').map(|i| position + i).ok_or_else(syntax)?;
            if (end - position) % 2 != 0 { return Err(syntax()); }
            let mut bytes = Vec::new();
            for pair in text[position..end].chunks(2) { bytes.push(hex_digit(pair[0]).ok_or_else(syntax)? * 16 + hex_digit(pair[1]).ok_or_else(syntax)?); }
            position = end + 1; TokenKind::Bytes(bytes)
        } else if c == b'-' || c.is_ascii_digit() {
            if c == b'-' && !text.get(position).is_some_and(u8::is_ascii_digit) { return Err(syntax()); }
            while text.get(position).is_some_and(u8::is_ascii_digit) { position += 1; }
            TokenKind::Integer(source[start..position].parse().unwrap())
        } else if c.is_ascii_alphabetic() || c == b'_' {
            while text.get(position).is_some_and(|byte| byte.is_ascii_alphanumeric() || *byte == b'_') { position += 1; }
            TokenKind::Name(source[start..position].into())
        } else { return Err(syntax()); };
        tokens.push(Token { kind, column: start + 1 });
    }
    tokens.push(Token { kind: TokenKind::End, column: text.len() + 1 }); Ok(tokens)
}
struct Parser<'a> { tokens: Vec<Token>, position: usize, schema: &'a Schema }
impl<'a> Parser<'a> {
    fn new(source: &str, schema: &'a Schema) -> Result<Self> { Ok(Self { tokens: tokenize(source)?, position: 0, schema }) }
    fn next(&self) -> &Token { &self.tokens[self.position] }
    fn symbol(&self, c: u8) -> bool { matches!(self.next().kind, TokenKind::Symbol(byte) if byte == c) }
    fn expect(&mut self, c: u8) -> Result<()> {
        if !self.symbol(c) { return Err(column_error("syntax error", self.next().column)); }
        self.position += 1; Ok(())
    }
    fn end(&self) -> Result<()> {
        if matches!(self.next().kind, TokenKind::End) { Ok(()) } else { Err(column_error("syntax error", self.next().column)) }
    }
    fn shape(&self, wanted: Shape) -> Result<()> {
        let actual = self.next().shape();
        if actual == Shape::None { Err(column_error("syntax error", self.next().column)) }
        else if actual != wanted { Err(column_error("type mismatch", self.next().column)) } else { Ok(()) }
    }
    fn element(&mut self, typ: usize) -> Result<Value> {
        let wanted = match &self.schema.types[typ].definition {
            Definition::Message(_) => Shape::Message, Definition::Enum(_) => Shape::Name,
            Definition::Scalar(kind) => match kind { Scalar::Bool => Shape::Boolean, Scalar::String => Shape::String, Scalar::Bytes => Shape::Bytes, _ => Shape::Integer },
        };
        self.shape(wanted)?;
        if self.schema.is_message(typ) { return Ok(Value::Message(self.message(typ)?)); }
        let token = self.next().clone(); self.position += 1;
        match token.kind {
            TokenKind::Integer(number) => {
                if !self.schema.scalar(typ).unwrap().contains(number) { return Err(column_error("out of range", token.column)); }
                Ok(Value::Number(number))
            }
            TokenKind::Name(name) => {
                if self.schema.scalar(typ) == Some(Scalar::Bool) { return Ok(Value::Boolean(name == "true")); }
                if let Definition::Enum(values) = &self.schema.types[typ].definition {
                    if let Some((&number, _)) = values.iter().find(|(_, value)| *value == &name) { return Ok(Value::Number(number)); }
                }
                Err(column_error("unknown enum value", token.column))
            }
            TokenKind::String(bytes) | TokenKind::Bytes(bytes) => Ok(Value::Binary(bytes)),
            _ => unreachable!(),
        }
    }
    fn field(&mut self, field: &Field) -> Result<Vec<Value>> {
        if !field.repeated { return Ok(vec![self.element(field.typ)?]); }
        self.shape(Shape::List)?; self.expect(b'[')?;
        let mut values = Vec::new();
        if !self.symbol(b']') {
            values.push(self.element(field.typ)?);
            while self.symbol(b',') { self.position += 1; values.push(self.element(field.typ)?); }
        }
        self.expect(b']')?; Ok(values)
    }
    fn message(&mut self, typ: usize) -> Result<Message> {
        self.expect(b'{')?;
        let schema = self.schema; let fields = schema.fields(typ);
        let mut message = Message::new(typ, schema); let mut seen = vec![false; fields.len()];
        if !self.symbol(b'}') {
            loop {
                let token = self.next();
                let TokenKind::Name(name) = &token.kind else { return Err(column_error("syntax error", token.column)); };
                let index = fields.iter().position(|field| &field.name == name).ok_or_else(|| column_error("unknown field", token.column))?;
                let field = &fields[index];
                if seen[index] { return Err(column_error("duplicate field", token.column)); }
                if let Some(group) = &field.group {
                    if fields.iter().enumerate().any(|(i, other)| seen[i] && other.group.as_ref() == Some(group)) { return Err(column_error("oneof conflict", token.column)); }
                }
                self.position += 1; seen[index] = true; self.expect(b':')?;
                message.fields[index] = self.field(field)?;
                if !self.symbol(b',') { break; }
                self.position += 1;
            }
        }
        let column = self.next().column; self.expect(b'}')?;
        for (i, field) in fields.iter().enumerate() {
            if field.required && !seen[i] { return Err(column_error(&format!("missing required field {}", field.name), column)); }
        }
        Ok(message)
    }
}

struct Segment { owner: usize, field: usize, index: Option<usize> }
impl Schema {
    fn path(&self, mut typ: usize, source: &str) -> Result<Vec<Segment>> {
        let parts: Vec<_> = source.split('.').collect(); let mut path = Vec::new();
        for (i, part) in parts.iter().enumerate() {
            let (name, index) = if let Some((name, suffix)) = part.split_once('[') {
                let digits = suffix.strip_suffix(']').ok_or("invalid path")?;
                if digits.is_empty() || digits.len() > 6 || !digits.bytes().all(|byte| byte.is_ascii_digit()) { return Err("invalid path".into()); }
                (name, Some(digits.parse::<usize>().unwrap()))
            } else { (*part, None) };
            let index_of_field = self.fields(typ).iter().position(|field| field.name == name).ok_or("invalid path")?;
            let field = &self.fields(typ)[index_of_field];
            if index.is_some() && !field.repeated { return Err("invalid path".into()); }
            if i + 1 < parts.len() && (!self.is_message(field.typ) || field.repeated && index.is_none()) { return Err("invalid path".into()); }
            path.push(Segment { owner: typ, field: index_of_field, index }); typ = field.typ;
        }
        Ok(path)
    }
    fn tree(&self, typ: usize, chain: &mut Vec<usize>, lines: &mut Vec<String>) {
        chain.push(typ);
        for field in self.fields(typ) {
            let mode = if field.required { "required ".into() } else if field.packed { "repeated packed ".into() }
                else if field.repeated { "repeated ".into() } else if let Some(group) = &field.group { format!("oneof {group} ") } else { String::new() };
            let mut line = format!("{}{} {}: {mode}{}", "  ".repeat(chain.len()), field.number, field.name, self.types[field.typ].name);
            if let Definition::Enum(values) = &self.types[field.typ].definition {
                write!(line, " ({})", values.iter().map(|(n, name)| format!("{name}={n}")).collect::<Vec<_>>().join(", ")).unwrap();
            }
            let recursive = self.is_message(field.typ) && chain.contains(&field.typ);
            if recursive { line.push_str(" (recursive)"); }
            lines.push(line);
            if self.is_message(field.typ) && !recursive { self.tree(field.typ, chain, lines); }
        }
        chain.pop();
    }
}
fn get_path(message: &Message, path: &[Segment], schema: &Schema) -> String {
    let mut current = Some(message);
    for (i, segment) in path.iter().enumerate() {
        let field = &schema.fields(segment.owner)[segment.field];
        let values = current.map_or(&[][..], |message| message.fields[segment.field].as_slice());
        if i + 1 == path.len() && field.repeated && segment.index.is_none() { return sequence_notation(field.typ, values, false, schema); }
        let value = values.get(segment.index.unwrap_or(0));
        if i + 1 == path.len() { return value.map_or_else(|| "(none)".into(), |value| notation(field.typ, value, false, schema)); }
        current = match value { Some(Value::Message(child)) => Some(child), _ => None };
    }
    unreachable!()
}
fn edit_path(message: &mut Message, path: &[Segment], replacement: Option<Vec<Value>>, schema: &Schema) -> Result<()> {
    let segment = &path[0]; let field = &schema.fields(message.typ)[segment.field];
    let index = segment.index.unwrap_or(0);
    if path.len() == 1 {
        if segment.index.is_some() {
            let values = &mut message.fields[segment.field];
            if index >= values.len() { if replacement.is_some() { return Err("index out of range".into()); } }
            else if let Some(mut replacement) = replacement { values[index] = replacement.pop().unwrap(); }
            else { values.remove(index); }
        } else if let Some(replacement) = replacement { message.choose(segment.field, schema); message.fields[segment.field] = replacement; }
        else { message.fields[segment.field].clear(); }
        return Ok(());
    }
    if index >= message.fields[segment.field].len() {
        if replacement.is_none() { return Ok(()); }
        if segment.index.is_some() { return Err("index out of range".into()); }
        message.choose(segment.field, schema); message.fields[segment.field].push(Value::Message(Message::new(field.typ, schema)));
    }
    if let Value::Message(child) = &mut message.fields[segment.field][index] { edit_path(child, &path[1..], replacement, schema)?; }
    Ok(())
}
fn equal(a: &Value, b: &Value) -> bool {
    match (a, b) { (Value::Number(x), Value::Number(y)) => x == y, (Value::Boolean(x), Value::Boolean(y)) => x == y, (Value::Binary(x), Value::Binary(y)) => x == y, _ => false }
}
fn differences(a: &Message, b: &Message, prefix: &str, schema: &Schema, lines: &mut Vec<String>) {
    for (i, field) in schema.fields(a.typ).iter().enumerate() {
        let x = &a.fields[i]; let y = &b.fields[i];
        for j in 0..x.len().max(y.len()) {
            let path = if field.repeated { format!("{prefix}{}[{j}]", field.name) } else { format!("{prefix}{}", field.name) };
            match (x.get(j), y.get(j)) {
                (Some(Value::Message(left)), Some(Value::Message(right))) => differences(left, right, &(path + "."), schema, lines),
                (Some(left), Some(right)) if equal(left, right) => {},
                (left, right) => {
                    let render = |value: Option<&Value>| value.map_or_else(|| "(none)".into(), |value| notation(field.typ, value, false, schema));
                    lines.push(format!("{path}: {} -> {}", render(left), render(right)));
                }
            }
        }
    }
}
fn parse_hex(source: &str) -> Result<Vec<u8>> {
    if source == "-" { return Ok(Vec::new()); }
    if source.is_empty() || source.len() % 2 != 0 { return Err("invalid hex".into()); }
    source.as_bytes().chunks(2).map(|pair| Ok(hex_digit(pair[0]).ok_or("invalid hex")? * 16 + hex_digit(pair[1]).ok_or("invalid hex")?)).collect()
}
fn rest(source: &str, count: usize) -> &str { source.splitn(count + 1, ' ').nth(count).unwrap() }

impl Schema {
    fn execute(&self, source: &str) -> Result<Vec<String>> {
        let words: Vec<_> = source.split(' ').collect(); let command = words[0];
        let count = match command {
            "VARINT" | "ZIGZAG" | "SCHEMA" => 2,
            "ENCODE" | "SIZE" | "DECODE" | "LITERAL" | "JSON" | "CANON" | "EXPLAIN" => 3,
            "GET" | "CLEAR" | "MERGE" | "DIFF" => 4, "PATCH" => 5, _ => return Err("unknown command".into()),
        };
        if words.len() < count || (!matches!(command, "ENCODE" | "SIZE" | "PATCH") && words.len() != count) { return Err("wrong number of arguments".into()); }
        if matches!(command, "VARINT" | "ZIGZAG") {
            let digits = words[1].strip_prefix('-').unwrap_or(words[1]);
            if digits.is_empty() || digits.len() > 18 || !digits.bytes().all(|byte| byte.is_ascii_digit()) { return Err("invalid number".into()); }
            let number: i64 = words[1].parse().unwrap();
            if (command == "VARINT" && !(0..=MAX_UNSIGNED).contains(&number)) || (command == "ZIGZAG" && !Scalar::Sint64.contains(number)) { return Err("invalid number".into()); }
            let value = if command == "ZIGZAG" { zigzag(number) } else { number };
            let mut bytes = Vec::new(); put_varint(&mut bytes, value);
            return Ok(vec![if command == "ZIGZAG" { format!("{value} {}", hex(&bytes)) } else { hex(&bytes) }]);
        }
        let typ = *self.names.get(words[1]).filter(|&&typ| self.is_message(typ)).ok_or("unknown message type")?;
        if command == "SCHEMA" {
            let mut lines = vec![self.types[typ].name.clone()]; self.tree(typ, &mut Vec::new(), &mut lines); return Ok(lines);
        }
        if matches!(command, "ENCODE" | "SIZE") {
            let mut parser = Parser::new(rest(source, 2), self)?; let message = parser.message(typ)?; parser.end()?;
            let encoded = encode(&message, self);
            if command == "ENCODE" { return Ok(vec![hex(&encoded)]); }
            let mut line = encoded.len().to_string();
            for (i, field) in self.fields(typ).iter().enumerate() {
                if !message.fields[i].is_empty() { write!(line, " {}={}", field.name, encode_field(field, &message.fields[i], self).len()).unwrap(); }
            }
            return Ok(vec![line]);
        }
        let mut first = parse_hex(words[2])?;
        let second = if matches!(command, "MERGE" | "DIFF") { parse_hex(words[3])? } else { Vec::new() };
        let path = if matches!(command, "GET" | "PATCH" | "CLEAR") { self.path(typ, words[3])? } else { Vec::new() };
        if command == "EXPLAIN" {
            let mut decoder = Decoder { data: &first, schema: self, explain: true, lines: Vec::new() };
            decoder.message(typ, 0, first.len(), 0)?;
            if first.is_empty() { decoder.lines.push("(empty)".into()); }
            return Ok(decoder.lines);
        }
        if command == "DIFF" {
            let a = decode(typ, &first, self).map_err(|error| error + " in first")?;
            let b = decode(typ, &second, self).map_err(|error| error + " in second")?;
            let mut lines = Vec::new(); differences(&a, &b, "", self, &mut lines);
            if lines.is_empty() { lines.push("SAME".into()); } return Ok(lines);
        }
        if command == "MERGE" { first.extend(second); }
        let mut message = decode(typ, &first, self)?;
        match command {
            "DECODE" | "MERGE" => Ok(text_message(&message, self)),
            "LITERAL" | "JSON" => Ok(vec![message_notation(&message, command == "JSON", self)]),
            "GET" => Ok(vec![get_path(&message, &path, self)]),
            _ => {
                if command == "PATCH" {
                    let last = path.last().unwrap(); let field = &self.fields(last.owner)[last.field];
                    let mut parser = Parser::new(rest(source, 4), self)?;
                    let replacement = if field.repeated && last.index.is_none() { parser.field(field)? } else { vec![parser.element(field.typ)?] };
                    parser.end()?; edit_path(&mut message, &path, Some(replacement), self)?; message.required(self, "")?;
                } else if command == "CLEAR" { edit_path(&mut message, &path, None, self)?; message.required(self, "")?; }
                Ok(vec![hex(&encode(&message, self))])
            }
        }
    }
}

fn main() {
    let mut input = String::new(); io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines(); let schema = Schema::read(&mut lines);
    let count: usize = lines.next().unwrap().parse().unwrap();
    let mut output = io::BufWriter::new(io::stdout().lock());
    for source in lines.take(count) {
        match schema.execute(source) {
            Ok(lines) => for line in lines { writeln!(output, "{line}").unwrap(); },
            Err(error) => writeln!(output, "ERROR {error}").unwrap(),
        }
    }
}
