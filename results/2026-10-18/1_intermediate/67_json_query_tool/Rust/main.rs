use std::cmp::Ordering;
use std::collections::BTreeSet;
use std::io::{self, Read};
#[derive(Clone)]
enum Value {
    Object(Vec<(String, Value)>),
    Array(Vec<Value>),
    String(String),
    Number(i64),
    Boolean(bool),
    Null,
}
fn identifier(s: &str) -> bool {
    let mut b = s.bytes();
    b.next().is_some_and(|c| c.is_ascii_alphabetic() || c == b'_')
    && b.all(|c| c.is_ascii_alphanumeric() || c == b'_')
}
fn integer(s: &str) -> Option<i64> {
    if s == "0" {
        return Some(0);
    }
    let digits = s.strip_prefix('-').unwrap_or(s);
    if (1..=9).contains(&digits.len()) && digits.as_bytes()[0] != b'0' && digits.bytes().all(|c| c.is_ascii_digit()) {
        s.parse().ok()
    } else {
        None
    }
}
fn quote(s: &str, q: char) -> String {
    let mut out = q.to_string();
    for c in s.chars() {
        if c == q || c == '\\' {
            out.push('\\');
            out.push(c);
        }
        else {
            match c {
                '\x08' => out.push_str("\\b"), '\x0c' => out.push_str("\\f"), '\n' => out.push_str("\\n"),
                '\r' => out.push_str("\\r"), '\t' => out.push_str("\\t"),
                c if (c as u32) < 32 || c == '\x7f' => out.push_str(&format!("\\u{:04x}", c as u32)),
                _ => out.push(c),
            }
        }
    }
    out.push(q);
    out
}
impl Value {
    fn kind(&self) -> &str {
        match self {
            Self::Object(_) => "object", Self::Array(_) => "array", Self::String(_) => "string", Self::Number(_) => "number", Self::Boolean(_) => "boolean", Self::Null => "null"
        }
    }
    fn compact(&self) -> String {
        match self {
            Self::Object(o) => format!("{{{}}}", o.iter().map(|(k,v)| format!("{}:{}", quote(k,'"'), v.compact())).collect::<Vec<_>>().join(",")),
            Self::Array(a) => format!("[{}]", a.iter().map(Value::compact).collect::<Vec<_>>().join(",")),
            Self::String(s) => quote(s,'"'), Self::Number(n) => n.to_string(), Self::Boolean(b) => b.to_string(), Self::Null => "null".into(),
        }
    }
    fn pretty(&self, indent: &str) -> String {
        let next = format!("{indent}  ");
        match self {
            Self::Object(o) if !o.is_empty() => format!("{{\n{}\n{indent}}}", o.iter().map(|(k,v)| format!("{next}{}: {}", quote(k,'"'), v.pretty(&next))).collect::<Vec<_>>().join(",\n")),
            Self::Array(a) if !a.is_empty() => format!("[\n{}\n{indent}]", a.iter().map(|v| format!("{next}{}",v.pretty(&next))).collect::<Vec<_>>().join(",\n")),
            _ => self.compact(),
        }
    }
    fn children(&self) -> usize {
        match self {
            Self::Object(o) => o.len(), Self::Array(a) => a.len(), _ => 0
        }
    }
    fn child(&self, i: usize) -> &Value {
        match self {
            Self::Object(o) => &o[i].1, Self::Array(a) => &a[i], _ => unreachable!()
        }
    }
    fn length(&self) -> Option<usize> {
        match self {
            Self::Object(o) => Some(o.len()), Self::Array(a) => Some(a.len()), Self::String(s) => Some(s.len()), _ => None
        }
    }
    fn size_depth(&self) -> (usize,usize) {
        let mut count = 1;
        let mut depth = 1;
        for i in 0..self.children() {
            let (n,d) = self.child(i).size_depth();
            count += n;
            depth = depth.max(d+1);
        }
        (count,depth)
    }
    fn equals(&self, other: &Value) -> bool {
        match (self,other) {
            (Self::Null,Self::Null) => true, (Self::Boolean(a),Self::Boolean(b)) => a==b,
            (Self::Number(a),Self::Number(b)) => a==b, (Self::String(a),Self::String(b)) => a==b,
            (Self::Array(a),Self::Array(b)) => a.len()==b.len() && a.iter().zip(b).all(|(x,y)| x.equals(y)),
            (Self::Object(a),Self::Object(b)) => a.len()==b.len() && a.iter().all(|(k,v)| b.iter().find(|(key,_)| key==k).is_some_and(|(_,x)| v.equals(x))),
            _ => false,
        }
    }
}
struct ParseError {
    position: usize, reason: String
}
struct Parser<'a> {
    text: &'a str, at: usize
}
impl<'a> Parser<'a> {
    fn error(&self, reason: impl Into<String>) -> ParseError {
        ParseError {
            position:self.at, reason:reason.into()
        }
    }
    fn current(&self) -> Option<u8> {
        self.text.as_bytes().get(self.at).copied()
    }
    fn skip(&mut self) {
        while matches!(self.current(),Some(b' '|b'\n')) {
            self.at+=1;
        }
    }
    fn string(&mut self) -> Result<String,ParseError> {
        self.at+=1;
        let mut out=String::new();
        loop {
            match self.current() {
                None | Some(b'\n') => return Err(self.error("unterminated string")),
                Some(b'"') => {
                    self.at+=1;
                    return Ok(out);
                }
                Some(b'\\') => {
                    let start=self.at;
                    let e=self.text.as_bytes().get(self.at+1).copied();
                    match e {
                        None | Some(b'\n') => {
                            self.at+=1;
                            return Err(self.error("unterminated string"));
                        }
                        Some(b'u') => {
                            let digits=self.text.as_bytes().get(self.at+2..self.at+6).filter(|d|d.iter().all(|c|c.is_ascii_hexdigit())).ok_or_else(||self.error("bad unicode escape"))?;
                            let n=u32::from_str_radix(std::str::from_utf8(digits).unwrap(),16).unwrap();
                            if n>127 {
                                return Err(self.error("non-ascii escape"));
                            }
                            out.push(char::from_u32(n).unwrap());
                            self.at+=6;
                        }
                        Some(c) => {
                            let decoded=match c {
                                b'"'=> '"', b'\\'=>'\\', b'/'=>'/', b'b'=>'\x08', b'f'=>'\x0c', b'n'=>'\n', b'r'=>'\r', b't'=>'\t', _=>return Err(ParseError {
                                    position:start,reason:format!("invalid escape '\\{}'",c as char)
                                })
                            };
                            out.push(decoded);
                            self.at+=2;
                        }
                    }
                }
                Some(c) => {
                    out.push(c as char);
                    self.at+=1;
                }
            }
        }
    }
    fn value(&mut self) -> Result<Value,ParseError> {
        self.skip();
        match self.current() {
            None => Err(self.error("unexpected end of input")),
            Some(b'"') => self.string().map(Value::String),
            Some(b'{') => {
                self.at+=1;
                self.skip();
                let mut object=Vec::new();
                if self.current()==Some(b'}') {
                    self.at+=1;
                    return Ok(Value::Object(object));
                }
                loop {
                    self.skip();
                    let start=self.at;
                    match self.current() {
                        None=>return Err(self.error("unexpected end of input")),Some(b'"')=>{
                        },_=>return Err(self.error("expected key"))
                    }
                    let key=self.string()?;
                    if object.iter().any(|(k,_)| k==&key) {
                        return Err(ParseError {
                            position:start,reason:format!("duplicate key {}",quote(&key,'"'))
                        });
                    }
                    self.skip();
                    match self.current() {
                        None=>return Err(self.error("unexpected end of input")),Some(b':')=>self.at+=1,_=>return Err(self.error("expected ':'"))
                    }
                    let value=self.value()?;
                    object.push((key,value));
                    self.skip();
                    match self.current() {
                        Some(b'}')=>{
                            self.at+=1;
                            break
                        },None=>return Err(self.error("unexpected end of input")),Some(b',')=>self.at+=1,_=>return Err(self.error("expected ',' or '}'"))
                    }
                    self.skip();
                    if self.current()==Some(b'}') {
                        return Err(self.error("trailing comma"));
                    }
                }
                Ok(Value::Object(object))
            }
            Some(b'[') => {
                self.at+=1;
                self.skip();
                let mut array=Vec::new(); if self.current()==Some(b']') {
                    self.at+=1;
                    return Ok(Value::Array(array));
                }
                loop {
                    array.push(self.value()?);
                    self.skip();
                    match self.current() {
                        Some(b']')=>{
                            self.at+=1;
                            break
                        },None=>return Err(self.error("unexpected end of input")),Some(b',')=>self.at+=1,_=>return Err(self.error("expected ',' or ']'"))
                    }
                    self.skip(); if self.current()==Some(b']') {
                        return Err(self.error("trailing comma"));
                    }
                }
                Ok(Value::Array(array))
            }
            Some(c) if c==b'-' || c.is_ascii_digit() => {
                let start=self.at;
                if c==b'-' {
                    self.at+=1;
                }
                let digits=self.at;
                while self.current().is_some_and(|c|c.is_ascii_digit()) {
                    self.at+=1;
                }
                if self.at==digits {
                    return Err(ParseError {
                        position:start,reason:"invalid number".into()
                    });
                }
                if self.at-digits>=2 && self.text.as_bytes()[digits]==b'0' {
                    return Err(ParseError {
                        position:digits,reason:"leading zero".into()
                    });
                }
                if self.current()==Some(b'.') {
                    return Err(self.error("fraction not allowed"));
                }
                if matches!(self.current(),Some(b'e'|b'E')) {
                    return Err(self.error("exponent not allowed"));
                }
                if self.at-digits>=10 {
                    return Err(ParseError {
                        position:start,reason:"number out of range".into()
                    });
                }
                Ok(Value::Number(self.text[start..self.at].parse().unwrap()))
            }
            Some(c) if c.is_ascii_alphabetic() => {
                let start=self.at;
                while self.current().is_some_and(|c|c.is_ascii_alphabetic()) {
                    self.at+=1;
                }
                match &self.text[start..self.at] {
                    "null"=>Ok(Value::Null),"true"=>Ok(Value::Boolean(true)),"false"=>Ok(Value::Boolean(false)),word=>Err(ParseError {
                        position:start,reason:format!("invalid literal '{word}'")
                    })
                }
            }
            Some(c) => Err(self.error(format!("unexpected character '{}'",c as char))),
        }
    }
    fn whole(text: &'a str) -> Result<Value,ParseError> {
        let mut parser=Self {
            text,at:0
        };
        let value=parser.value()?;
        parser.skip();
        if parser.at!=text.len() {
            return Err(parser.error("trailing characters"));
        }
        Ok(value)
    }
}
#[derive(Clone)]
enum Selector {
    Key(String), Index(i64), All, Slice(Option<i64>,Option<i64>)
}
#[derive(Clone)]
struct Segment {
    descendant: bool, selector: Selector
}
fn quoted_key(s: &str, at: &mut usize) -> Option<String> {
    let b=s.as_bytes();
    if b.get(*at)!=Some(&b'\'') {
        return None;
    }
    *at+=1;
    let mut out=String::new();
    while *at<b.len() {
        let c=b[*at];
        *at+=1;
        if c==b'\'' {
            return Some(out);
        }
        if c!=b'\\' {
            out.push(c as char);
            continue;
        }
        let c=*b.get(*at)?;
        *at+=1;
        if c==b'u' {
            let digits=b.get(*at..*at+4)?;
            if !digits.iter().all(|c|c.is_ascii_hexdigit()) {
                return None;
            }
            let n=u32::from_str_radix(std::str::from_utf8(digits).ok()?,16).ok()?;
            if n>127 {
                return None;
            }
            out.push(char::from_u32(n)?);
            *at+=4;
        } else {
            out.push(match c {
                b'\''=>'\'',b'\\'=>'\\',b'/'=>'/',b'b'=>'\x08',b'f'=>'\x0c',b'n'=>'\n',b'r'=>'\r',b't'=>'\t',_=>return None
            });
        }
    }
    None
}
fn path(s: &str, field: bool) -> Option<Vec<Segment>> {
    let b=s.as_bytes();
    if b.first()!=Some(&if field {
        b'@'
    } else {
        b'$'
    }) {
        return None;
    }
    let mut at=1;
    let mut segments=Vec::new();
    while at<b.len() {
        let mut descendant=false;
        if b[at]==b'.' {
            at+=1;
            if b.get(at)==Some(&b'.') {
                if field {
                    return None;
                }
                descendant=true;
                at+=1;
            }
            else if b.get(at)==Some(&b'[') {
                return None;
            }
        }
        else if b[at]!=b'[' {
            return None;
        }
        else {
            // A bracket selector does not need a preceding dot.
        }
        let selector=if b.get(at)==Some(&b'[') {
            at+=1;
            if b.get(at)==Some(&b'\'') {
                let key=quoted_key(s,&mut at)?; if b.get(at)!=Some(&b']') {
                    return None;
                }
                at+=1;
                Selector::Key(key)
            }
            else {
                let end=at+s[at..].find(']')?;
                let item=&s[at..end];
                at=end+1;
                if item=="*" && !field {
                    Selector::All
                }
                else if let Some((a,b))=item.split_once(':') {
                    if field {
                        return None;
                    }
                    Selector::Slice(if a.is_empty() {
                        None
                    } else {
                        Some(integer(a)?)
                    },if b.is_empty() {
                        None
                    } else {
                        Some(integer(b)?)
                    })
                }
                else {
                    Selector::Index(integer(item)?)
                }
            }
        } else if b.get(at)==Some(&b'*') && !field {
            at+=1;
            Selector::All
        }
        else {
            let start=at;
            while at<b.len() && (b[at].is_ascii_alphanumeric() || b[at]==b'_') {
                at+=1;
            }
            let key=&s[start..at];
            if !identifier(key) {
                return None;
            }
            Selector::Key(key.into())
        };
        segments.push(Segment {
            descendant,selector
        });
    }
    Some(segments)
}
// Child positions preserve document order even when object keys are renamed.
type Location = Vec<usize>;
fn value_at<'a>(root: &'a Value, location: &[usize]) -> &'a Value {
    let mut v=root;
    for &i in location {
        v=v.child(i);
    }
    v
}
fn value_at_mut<'a>(root: &'a mut Value, location: &[usize]) -> &'a mut Value {
    if location.is_empty() {
        return root;
    }
    let next=match root {
        Value::Object(o)=>&mut o[location[0]].1,Value::Array(a)=>&mut a[location[0]],_=>unreachable!()
    };
    value_at_mut(next,&location[1..])
}
fn notation(root: &Value, location: &[usize]) -> String {
    let mut out="$".to_string();
    let mut value=root;
    for &i in location {
        match value {
            Value::Object(o)=>{
                let key=&o[i].0;
                if identifier(key) {
                    out.push('.');
                    out+=key;
                } else {
                    out+=&format!("[{}]",quote(key,'\''));
                }
            },_=>out+=&format!("[{i}]")
        }
        value=value.child(i);
    }
    out
}
fn preorder(root: &Value, location: &Location, out: &mut Vec<Location>) {
    out.push(location.clone());
    for i in 0..value_at(root,location).children() {
        let mut child=location.clone();
        child.push(i);
        preorder(root,&child,out);
    }
}
fn selection(value: &Value, selector: &Selector) -> Vec<usize> {
    match (value,selector) {
        (Value::Object(o),Selector::Key(k)) => o.iter().position(|(key,_)|key==k).into_iter().collect(),
        (Value::Object(_)|Value::Array(_),Selector::All) => (0..value.children()).collect(),
        (Value::Array(a),Selector::Index(i)) => {
            let j=if *i<0 {
                a.len() as i64+i
            } else {
                *i
            };
            if j>=0 && j<a.len() as i64 {
                vec![j as usize]
            } else {
                Vec::new()
            }
        },
        (Value::Array(a),Selector::Slice(start,end)) => {
            let n=a.len() as i64;
            let bound=|x:i64| (if x<0 {
                x+n
            } else {
                x
            }).clamp(0,n);
            let a=bound(start.unwrap_or(0));
            let b=bound(end.unwrap_or(n));
            (a..b).map(|i|i as usize).collect()
        },
        _=>Vec::new(),
    }
}
fn apply(root: &Value, matches: Vec<Location>, segment: &Segment) -> Vec<Location> {
    let mut out=Vec::new();
    for location in matches {
        let mut parents=Vec::new();
        if segment.descendant {
            preorder(root,&location,&mut parents);
        } else {
            parents.push(location);
        }
        for parent in parents {
            for i in selection(value_at(root,&parent),&segment.selector) {
                let mut next=parent.clone();
                next.push(i);
                out.push(next);
            }
        }
    }
    out
}
fn evaluate(root: &Value, path: &[Segment]) -> Vec<Location> {
    let mut matches=vec![Vec::new()];
    for segment in path {
        matches=apply(root,matches,segment);
    }
    matches
}
fn field_value<'a>(root: &'a Value, field: &[Segment]) -> Option<&'a Value> {
    let mut value=root;
    for segment in field {
        let i=*selection(value,&segment.selector).first()?;
        value=value.child(i);
    }
    Some(value)
}
fn sort_order(a: Option<&Value>, b: Option<&Value>) -> Ordering {
    let rank=|v:Option<&Value>|match v {
        Some(Value::Null)=>0,Some(Value::Number(_))=>1,Some(Value::String(_))=>2,_=>3
    };
    let order=rank(a).cmp(&rank(b));
    if order!=Ordering::Equal {
        return order;
    }
    match (a,b) {
        (Some(Value::Number(a)),Some(Value::Number(b)))=>a.cmp(b),(Some(Value::String(a)),Some(Value::String(b)))=>a.cmp(b),_=>Ordering::Equal
    }
}
fn merge(target: &mut Value, source: &Value) {
    if let (Value::Object(t),Value::Object(m))=(target,source) {
        for (key,value) in m {
            if let Some((_,old))=t.iter_mut().find(|(k,_)|k==key) {
                if matches!((&*old,value),(Value::Object(_),Value::Object(_))) {
                    merge(old,value);
                } else {
                    *old=value.clone();
                }
            }
            else {
                t.push((key.clone(),value.clone()));
            }
        }
    }
}
struct Tool {
    root: Value, history: Vec<Value>
}
impl Tool {
    fn load(&mut self, text: &str) {
        match Parser::whole(text) {
            Ok(value)=>{
                let (nodes,depth)=value.size_depth();
                self.history.push(self.root.clone());
                self.root=value;
                println!("LOADED nodes={nodes} depth={depth}");
            }
            Err(error)=>{
                let prefix=&text[..error.position];
                let line=prefix.bytes().filter(|&c|c==b'\n').count()+1;
                let col=prefix.rsplit('\n').next().unwrap().len()+1;
                println!("PARSE ERROR line {line} col {col}: {}",error.reason);
            }
        }
    }
    fn command(&mut self, line: &str) -> Result<Vec<String>,String> {
        let (command,arg)=line.split_once(' ').map_or((line,None),|(c,a)|(c,Some(a)));
        let known=["GET","COMPACT","PRETTY","TYPE","LENGTH","KEYS","FLATTEN","COUNT","SUM","MIN","MAX","AVG","FILTER","SET","DELETE","INSERT","MERGE","SORT","RENAME","UNDO"];
        if !known.contains(&command) {
            return Err(format!("ERROR unknown command '{command}'"));
        }
        let words:Vec<_>=arg.map_or(Vec::new(),|a|if ["SET","MERGE"].contains(&command) {
            a.splitn(2,' ').collect()
        } else if command=="INSERT" {
            a.splitn(3,' ').collect()
        } else if command=="FILTER" {
            a.splitn(4,' ').collect()
        } else {
            a.split(' ').collect()
        });
        let shape=match command {
            "UNDO"=>words.is_empty(),"COMPACT"|"PRETTY"|"FLATTEN"=>words.len()<=1,"SET"|"MERGE"|"RENAME"=>words.len()==2,"INSERT"=>words.len()==3,"FILTER"=>words.len()>=3 && (if words[2]=="EXISTS" {
                words.len()==3
            } else {
                words.len()==4
            }),"SORT"=>(1..=3).contains(&words.len()) && (words.len()<3 || (words[1]!="DESC" && words[2]=="DESC")),_=>words.len()==1
        };
        if !shape {
            return Err("ERROR bad arguments".into());
        }
        if command=="UNDO" {
            self.root=self.history.pop().ok_or("ERROR nothing to undo")?;
            return Ok(vec![format!("UNDO {}",self.history.len())]);
        }
        let parsed=path(words.first().copied().unwrap_or("$"),false).ok_or("ERROR bad path")?;
        let mut field=Vec::new();
        let mut index=0;
        let mut rename=String::new();
        let mut supplied=None;
        if command=="FILTER" || command=="SORT" {
            let f=if command=="FILTER" {
                words[1]
            } else {
                words.get(1).filter(|&&s|s!="DESC").copied().unwrap_or("@")
            };
            field=path(f,true).ok_or("ERROR bad field")?;
        }
        if command=="FILTER" && !["==","!=","<","<=",">",">=","EXISTS"].contains(&words[2]) {
            return Err("ERROR bad operator".into());
        }
        if command=="INSERT" {
            index=integer(words[1]).ok_or("ERROR bad index")?;
        }
        if command=="RENAME" {
            rename=if identifier(words[1]) {
                words[1].into()
            } else {
                let mut at=0;
                let key=quoted_key(words[1],&mut at).ok_or("ERROR bad key")?;
                if at!=words[1].len() {
                    return Err("ERROR bad key".into());
                }
                key
            };
        }
        let json=match command {
            "SET"|"MERGE"=>Some(words[1]),"INSERT"=>Some(words[2]),"FILTER" if words[2]!="EXISTS"=>Some(words[3]),_=>None
        };
        if let Some(text)=json {
            supplied=Some(Parser::whole(text).map_err(|e|format!("PARSE ERROR col {}: {}",e.position+1,e.reason))?);
        }
        if command=="MERGE" && !matches!(supplied,Some(Value::Object(_))) {
            return Err("ERROR merge value is not an object".into());
        }
        let matches=evaluate(&self.root,&parsed);
        let required=match command {
            "FILTER"|"INSERT"|"SORT"=>Some("array"),"MERGE"|"KEYS"=>Some("object"),_=>None
        };
        for location in &matches {
            let value=value_at(&self.root,location);
            let loc=notation(&self.root,location);
            if let Some(kind)=required {
                if value.kind()!=kind {
                    return Err(format!("ERROR not an {kind} at {loc}"));
                }
            }
            if command=="LENGTH" && value.length().is_none() {
                return Err(format!("ERROR no length at {loc}"));
            }
            if command=="RENAME" && (location.is_empty() || !matches!(value_at(&self.root,&location[..location.len()-1]),Value::Object(_))) {
                return Err(format!("ERROR not a member at {loc}"));
            }
        }
        if command=="INSERT" {
            for location in &matches {
                let n=value_at(&self.root,location).children() as i64;
                if index < -n-1 || index>n {
                    return Err(format!("ERROR index out of range at {}",notation(&self.root,location)));
                }
            }
        }
        let mut output=Vec::new();
        match command {
            "COUNT"=>return Ok(vec![format!("COUNT {}",matches.len())]),
            "SUM"|"MIN"|"MAX"|"AVG"=>{
                let nums:Vec<_>=matches.iter().filter_map(|l|if let Value::Number(n)=value_at(&self.root,l) {
                    Some(*n)
                } else {
                    None
                }).collect();
                let sum:i64=nums.iter().sum();
                let text=match command {
                    "SUM"=>sum.to_string(),"MIN"=>nums.iter().min().map_or("null".into(),|n|n.to_string()),"MAX"=>nums.iter().max().map_or("null".into(),|n|n.to_string()),_=>if nums.is_empty() {
                        "null".into()
                    } else {
                        let n=nums.len() as i64;
                        let q=(sum.abs()*200+n)/(2*n);
                        format!("{}{}.{:02}",if sum<0 && q>0 {
                            "-"
                        } else {
                            ""
                        },q/100,q%100)
                    }
                };
                return Ok(vec![format!("{command} {text}")]);
            }
            "GET"|"COMPACT"|"PRETTY"|"TYPE"|"LENGTH"|"KEYS"|"FLATTEN"|"FILTER"=>{
                for location in &matches {
                    let value=value_at(&self.root,location);
                    let loc=notation(&self.root,location);
                    match command {
                        "GET"=>output.push(format!("{loc} = {}",value.compact())),"COMPACT"=>output.push(value.compact()),"PRETTY"=>output.push(value.pretty("")),"TYPE"=>output.push(format!("{loc} {}",value.kind())),"LENGTH"=>output.push(format!("{loc} {}",value.length().unwrap())),
                        "KEYS"=>if let Value::Object(o)=value {
                            output.push(format!("{loc} {}",Value::Array(o.iter().map(|(k,_)|Value::String(k.clone())).collect()).compact()));
                        },
                        "FLATTEN"=>{
                            let mut descendants=Vec::new();
                            preorder(&self.root,location,&mut descendants);
                            for leaf in descendants {
                                let v=value_at(&self.root,&leaf);
                                if v.children()==0 {
                                    output.push(format!("{} = {}",notation(&self.root,&leaf),v.compact()));
                                }
                            }
                        },
                        _=>for i in 0..value.children() {
                            let element=value.child(i);
                            let f=field_value(element,&field);
                            let r=supplied.as_ref();
                            let equal=f.zip(r).is_some_and(|(a,b)|a.equals(b));
                            let comparison=f.zip(r).and_then(|(a,b)|match (a,b) {
                                (Value::Number(a),Value::Number(b))=>Some(a.cmp(b)),(Value::String(a),Value::String(b))=>Some(a.cmp(b)),_=>None
                            });
                            let good=match words[2] {
                                "EXISTS"=>f.is_some(),"=="=>equal,"!="=>!equal,"<"=>comparison==Some(Ordering::Less),"<="=>comparison.is_some_and(|c|c!=Ordering::Greater),">"=>comparison==Some(Ordering::Greater),_=>comparison.is_some_and(|c|c!=Ordering::Less)
                            };
                            if good {
                                let mut child=location.clone();
                                child.push(i);
                                output.push(format!("{} = {}",notation(&self.root,&child),element.compact()));
                            }
                        },
                    }
                }
                if output.is_empty() {
                    output.push("no match".into());
                }
                return Ok(output);
            }
            _=>{
            }
        }
        if command=="DELETE" && parsed.is_empty() {
            return Err("ERROR cannot delete root".into());
        }
        let mut targets=matches;
        let new_key=if command=="SET" {
            parsed.last().and_then(|s|if !s.descendant {
                if let Selector::Key(k)=&s.selector {
                    Some(k.clone())
                } else {
                    None
                }
            } else {
                None
            })
        } else {
            None
        };
        if command=="SET" && !parsed.is_empty() {
            if let Some(key)=&new_key {
                targets=Vec::new();
                for parent in evaluate(&self.root,&parsed[..parsed.len()-1]) {
                    if let Value::Object(o)=value_at(&self.root,&parent) {
                        let mut target=parent;
                        target.push(o.iter().position(|(k,_)|k==key).unwrap_or(o.len()));
                        targets.push(target);
                    }
                }
            }
        }
        let targets:BTreeSet<_>=targets.into_iter().collect();
        let count=targets.len();
        let mut changed=self.root.clone();
        for location in targets.iter().rev() {
            if command=="SET" {
                if location.is_empty() {
                    changed=supplied.as_ref().unwrap().clone();
                }
                else {
                    let (&i,parent)=location.split_last().unwrap();
                    match value_at_mut(&mut changed,parent) {
                        Value::Object(o)=>{
                            if i==o.len() {
                                o.push((new_key.as_ref().unwrap().clone(),supplied.as_ref().unwrap().clone()));
                            } else {
                                o[i].1=supplied.as_ref().unwrap().clone();
                            }
                        },Value::Array(a)=>a[i]=supplied.as_ref().unwrap().clone(),_=>unreachable!()
                    }
                }
            } else if command=="DELETE" {
                let (&i,parent)=location.split_last().unwrap();
                match value_at_mut(&mut changed,parent) {
                    Value::Object(o)=>{
                        o.remove(i);
                    },Value::Array(a)=>{
                        a.remove(i);
                    },_=>unreachable!()
                }
            }
            else if command=="RENAME" {
                let (&i,parent)=location.split_last().unwrap();
                if let Value::Object(o)=value_at_mut(&mut changed,parent) {
                    if o[i].0!=rename && o.iter().any(|(k,_)|k==&rename) {
                        return Err(format!("ERROR key exists at {}",notation(&self.root,location)));
                    }
                    o[i].0=rename.clone();
                }
            } else {
                let target=value_at_mut(&mut changed,location);
                match command {
                    "MERGE"=>merge(target,supplied.as_ref().unwrap()),
                    "INSERT"=>if let Value::Array(a)=target {
                        let j=if index<0 {
                            a.len() as i64+1+index
                        } else {
                            index
                        };
                        a.insert(j as usize,supplied.as_ref().unwrap().clone());
                    },
                    "SORT"=>if let Value::Array(a)=target {
                        let desc=words.last()==Some(&"DESC");
                        a.sort_by(|a,b| {
                            let order=sort_order(field_value(a,&field),field_value(b,&field));
                            if desc {
                                order.reverse()
                            } else {
                                order
                            }
                        });
                    },
                    _=>unreachable!(),
                }
            }
        }
        self.history.push(self.root.clone());
        self.root=changed;
        Ok(vec![format!("{command} {count}")])
    }
}
fn main() {
    let mut input=String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let lines:Vec<_>=input.lines().collect();
    let mut at=0;
    let mut tool=Tool {
        root:Value::Null,history:Vec::new()
    };
    loop {
        let start=at;
        while lines[at]!="%%" {
            at+=1;
        }
        tool.load(&lines[start..at].join("\n"));
        at+=1;
        while lines[at]!="LOAD" && lines[at]!="END" {
            match tool.command(lines[at]) {
                Ok(output)=>for line in output {
                    println!("{line}");
                },Err(error)=>println!("{error}")
            }
            at+=1;
        }
        if lines[at]=="END" {
            break;
        }
        at+=1;
    }
}
