use std::cell::RefCell;
use std::collections::{BTreeMap, BTreeSet};
use std::io::{self, Read};
use std::rc::Rc;

type Expanded<T> = Result<T, String>;

fn words(s: &str) -> Vec<String> {
    s.split(' ').filter(|w| !w.is_empty()).map(str::to_string).collect()
}

fn unique(xs: Vec<String>) -> Vec<String> {
    let mut seen = BTreeSet::new();
    xs.into_iter().filter(|s| seen.insert(s.clone())).collect()
}

fn stem(pattern: &str,word: &str) -> Option<String> {
    if let Some(i) = pattern.find('%') {
        let a = &pattern[..i];
        let b = &pattern[i+1..];
        if word.len() >= a.len()+b.len() && word.starts_with(a) && word.ends_with(b) {
            Some(word[a.len()..word.len()-b.len()].into())
        } else {
            None
        }
    } else if pattern == word {
        Some(String::new())
    } else {
        None
    }
}

fn substitute(s: &str,m: &str) -> String {
    s.replacen('%',m,1)
}

fn replace_word(w: &str,p: &str,r: &str) -> String {
    stem(p,w).map_or_else(||w.into(),|m| if p.contains('%') {
        substitute(r,&m)
    } else {
        r.into()
    })
}

fn wildcard(pattern: &str,word: &str) -> bool {
    let mut previous = vec![false;word.len()+1];
    previous[0] = true;
    for c in pattern.bytes() {
        let mut next = vec![false;word.len()+1];
        if c == b'*' {
            next[0] = previous[0];
        }
        for (i,b) in word.bytes().enumerate() {
            let j = i+1;
            next[j] = if c == b'*' {
                previous[j] || (b != b'/' && next[j-1])
            } else {
                previous[j-1] && (if c == b'?' {
                    b != b'/'
                } else {
                    c == b
                })
            };
        }
        previous = next;
    }
    previous[word.len()]
}
#[derive(Clone)]
struct Variable {
    simple: bool,
    value: String
}
#[derive(Clone)]
struct RecipeLine {
    number: usize,
    text: String
}

type Recipe = Rc<RefCell<Vec<RecipeLine>>>;
#[derive(Clone)]
struct Rule {
    target: String,
    deps: Vec<String>,
    recipe: Option<Recipe>,
    stem: String
}

impl Rule {
    fn new(target: String,deps: Vec<String>) -> Self {
        Self {
            target,deps,recipe:None,stem:String::new()
        }
    }
}

struct Current {
    targets: Vec<String>,
    patterns: Vec<usize>,
    recipe: Option<Recipe>
}

struct Condition {
    outer: bool,
    value: bool,
    had_else: bool,
    line: usize
}

enum Scope {
    Foreach(String,String), Call(Vec<String>)
}

struct Simulator {
    files: BTreeMap<String,i64>,
    clock: i64,
    loaded: bool,
    variables: BTreeMap<String,Variable>,
    rules: BTreeMap<String,Rule>,
    patterns: Vec<Rule>,
    phony: BTreeSet<String>,
    goal: Option<String>,
    output: Vec<String>,
    location: String,
    scopes: Vec<Scope>,
    expanding: BTreeSet<String>,
    automatic: BTreeMap<String,String>
}

fn function_limits(name: &str) -> Option<(usize,usize)> {
    match name {
        "subst"|"patsubst"|"wordlist"|"foreach" => Some((3,3)), "findstring"|"filter"|"filter-out"|"word"|"addsuffix"|"addprefix" => Some((2,2)), "if" => Some((2,3)), "call" => Some((1,usize::MAX)), "strip"|"sort"|"words"|"firstword"|"lastword"|"dir"|"notdir"|"suffix"|"basename"|"wildcard"|"value"|"info"|"warning"|"error" => Some((1,1)), _ => None
    }
}

impl Simulator {
    fn new() -> Self {
        Self {
            files:BTreeMap::new(),clock:0,loaded:false,variables:BTreeMap::new(),rules:BTreeMap::new(),patterns:Vec::new(),phony:BTreeSet::new(),goal:None,output:Vec::new(),location:"make".into(),scopes:Vec::new(),expanding:BTreeSet::new(),automatic:BTreeMap::new()
        }
    }
    fn diagnostic(&mut self,reason: &str) {
        self.output.push(format!("{}: *** {}.  Stop.",self.location,reason));
    }
    fn tick(&mut self,n: &str) {
        self.clock += 1;
        self.files.insert(n.into(),self.clock);
    }
    fn clear(&mut self) {
        self.loaded=false;
        self.variables.clear();
        self.rules.clear();
        self.patterns.clear();
        self.phony.clear();
        self.goal=None;
        self.scopes.clear();
        self.expanding.clear();
        self.automatic.clear();
    }
    fn closing(s: &str,start: usize) -> Expanded<usize> {
        let b=s.as_bytes();
        let opening=b[start];
        let close=if opening==b'(' {
            b')'
        } else {
            b'}'
        };
        let mut depth=0;
        for (i,&c) in b.iter().enumerate().skip(start) {
            if c==opening {
                depth+=1;
            }
            if c==close {
                depth-=1;
                if depth==0 {
                    return Ok(i);
                }
            }
        }
        Err("unterminated variable reference".into())
    }
    fn outside(s: &str) -> Expanded<BTreeMap<u8,usize>> {
        let mut result=BTreeMap::new();
        let b=s.as_bytes();
        let mut i=0;
        while i<b.len() {
            if b[i]==b'$' {
                if i+1<b.len() && (b[i+1]==b'(' || b[i+1]==b'{') {
                    i=Self::closing(s,i+1)?+1;
                } else {
                    i=(i+2).min(b.len());
                }
            } else {
                if b"=:;".contains(&b[i]) {
                    result.entry(b[i]).or_insert(i);
                }
                i+=1;
            }
        }
        Ok(result)
    }
    fn value(&mut self,name: &str) -> Expanded<String> {
        for scope in self.scopes.iter().rev() {
            match scope {
                Scope::Foreach(n,v) if n==name=>return Ok(v.clone()),Scope::Call(values) if !name.is_empty() && name.bytes().all(|b|b.is_ascii_digit())=>return Ok(values.get(name.parse::<usize>().unwrap()).cloned().unwrap_or_default()),_=> {
                }
            }
        }
        if let Some(v)=self.automatic.get(name) {
            return Ok(v.clone());
        }
        let Some(v)=self.variables.get(name).cloned() else {
            return Ok(String::new());
        };
        if v.simple {
            return Ok(v.value);
        }
        if !self.expanding.insert(name.into()) {
            return Err(format!("Recursive variable '{}' references itself (eventually)",name));
        }
        let result=self.expand(&v.value);
        self.expanding.remove(name);
        result
    }
    fn expand(&mut self,s: &str) -> Expanded<String> {
        let b=s.as_bytes();
        let mut out=String::new();
        let mut i=0;
        while i<b.len() {
            if b[i]!=b'$' {
                out.push(b[i] as char);
                i+=1;
                continue;
            }
            if i+1==b.len() {
                break;
            }
            let c=b[i+1];
            if c==b'$' {
                out.push('$');
                i+=2;
            } else if c==b'(' || c==b'{' {
                let end=Self::closing(s,i+1)?;
                out.push_str(&self.reference(&s[i+2..end],c)?);
                i=end+1;
            } else {
                out.push_str(&self.value(&s[i+1..i+2])?);
                i+=2;
            }
        }
        Ok(out)
    }
    fn reference(&mut self,content: &str,opening: u8) -> Expanded<String> {
        if let Some(space)=content.find(' ') {
            if function_limits(&content[..space]).is_some() {
                return self.function(&content[..space],content[space+1..].trim_start_matches(' '),opening);
            }
        }
        let n=self.expand(content)?;
        if let Some(colon)=n.find(':') {
            if let Some(equal)=n[colon+1..].find('=').map(|i|i+colon+1) {
                let mut p=n[colon+1..equal].to_string();
                let mut r=n[equal+1..].to_string();
                if !p.contains('%') {
                    p.insert(0,'%');
                    r.insert(0,'%');
                }
                return Ok(words(&self.value(&n[..colon])?).iter().map(|w|replace_word(w,&p,&r)).collect::<Vec<_>>().join(" "));
            }
        }
        self.value(&n)
    }
    fn arguments(text: &str,opening: u8,maximum: usize) -> Vec<String> {
        let close=if opening==b'(' {
            b')'
        } else {
            b'}'
        };
        let mut depth=0;
        let mut start=0;
        let mut result=Vec::new();
        for (i,c) in text.bytes().enumerate() {
            if c==opening {
                depth+=1;
            }
            if c==close {
                depth-=1;
            }
            if c==b',' && depth==0 && result.len()<maximum-1 {
                result.push(text[start..i].into());
                start=i+1;
            }
        }
        result.push(text[start..].into());
        result
    }
    fn function(&mut self,name: &str,text: &str,opening: u8) -> Expanded<String> {
        let (minimum,maximum)=function_limits(name).unwrap();
        let raw=Self::arguments(text,opening,maximum);
        if raw.len()<minimum {
            return Err(format!("insufficient number of arguments ({}) to function '{}'",raw.len(),name));
        }
        if name=="foreach" {
            let n=self.expand(&raw[0])?.trim_matches(' ').to_string();
            let list=words(&self.expand(&raw[1])?);
            let mut result=Vec::new();
            for word in list {
                self.scopes.push(Scope::Foreach(n.clone(),word));
                let expanded=self.expand(&raw[2]);
                self.scopes.pop();
                result.push(expanded?);
            }
            return Ok(result.join(" "));
        }
        if name=="if" {
            let condition=self.expand(&raw[0])?;
            return if !condition.trim_matches(' ').is_empty() {
                self.expand(&raw[1])
            } else if raw.len()==3 {
                self.expand(&raw[2])
            } else {
                Ok(String::new())
            };
        }
        let mut args=Vec::new();
        for r in &raw {
            let s=self.expand(r)?;
            args.push(if name=="subst" || name=="call" {
                s
            } else {
                s.trim_matches(' ').into()
            });
        }
        let list=|i:usize|words(&args[i]);
        let result=match name {
            "call"=> {
                let n=args[0].trim_matches(' ');
                let Some(v)=self.variables.get(n).cloned()else {
                    return Ok(String::new());
                };
                if v.simple {
                    return Ok(v.value);
                }
                let mut values=vec![n.to_string()];
                values.extend_from_slice(&args[1..]);
                self.scopes.push(Scope::Call(values));
                let expanded=self.expand(&v.value);
                self.scopes.pop();
                return expanded;
            },
            "value"=>self.variables.get(&args[0]).map(|v|v.value.clone()).unwrap_or_default(),"info"=> {
                self.output.push(args[0].clone());
                String::new()
            },"warning"=> {
                self.output.push(format!("{}: {}",self.location,args[0]));
                String::new()
            },"error"=>return Err(args[0].clone()),
            "subst"=>if args[0].is_empty() {
                args[2].clone()
            } else {
                args[2].replace(args[0].as_str(),args[1].as_str())
            },"patsubst"=>list(2).iter().map(|w|replace_word(w,&args[0],&args[1])).collect::<Vec<_>>().join(" "),"strip"=>list(0).join(" "),"findstring"=>if args[1].contains(args[0].as_str()) {
                args[0].clone()
            } else {
                String::new()
            },
            "filter"|"filter-out"=>list(1).into_iter().filter(|w|list(0).iter().any(|p|stem(p,w).is_some())==(name=="filter")).collect::<Vec<_>>().join(" "),"sort"=>list(0).into_iter().collect::<BTreeSet<_>>().into_iter().collect::<Vec<_>>().join(" "),
            "word"=> {
                let n=&args[0];
                if n.is_empty() || !n.bytes().all(|b|b.is_ascii_digit()) {
                    return Err(format!("non-numeric first argument to 'word' function: '{}'",n));
                }
                let i:usize=n.parse().unwrap();
                if i==0 {
                    return Err("first argument to 'word' function must be greater than 0".into());
                }
                list(1).get(i-1).cloned().unwrap_or_default()
            },
            "wordlist"=> {
                let a=&args[0];
                let b=&args[1];
                if a.is_empty() || !a.bytes().all(|b|b.is_ascii_digit()) {
                    return Err(format!("non-numeric first argument to 'wordlist' function: '{}'",a));
                }
                if b.is_empty() || !b.bytes().all(|b|b.is_ascii_digit()) {
                    return Err(format!("non-numeric second argument to 'wordlist' function: '{}'",b));
                }
                let start:usize=a.parse().unwrap();
                let end:usize=b.parse().unwrap();
                if start==0 {
                    return Err(format!("invalid first argument to 'wordlist' function: '{}'",a));
                }
                list(2).into_iter().enumerate().filter(|(i,_)|i+1>=start && i+1<=end).map(|(_,s)|s).collect::<Vec<_>>().join(" ")
            },
            "words"=>list(0).len().to_string(),"firstword"=>list(0).first().cloned().unwrap_or_default(),"lastword"=>list(0).last().cloned().unwrap_or_default(),
            "dir"=>list(0).iter().map(|w|w.rfind('/').map_or("./".into(),|i|w[..i+1].to_string())).collect::<Vec<_>>().join(" "),"notdir"=>list(0).iter().map(|w|w[w.rfind('/').map_or(0,|i|i+1)..].to_string()).collect::<Vec<_>>().join(" "),
            "suffix"=>list(0).iter().filter_map(|w|w.rfind('.').filter(|&i|w.rfind('/').is_none_or(|j|i>j)).map(|i|w[i..].to_string())).collect::<Vec<_>>().join(" "),"basename"=>list(0).iter().map(|w|w.rfind('.').filter(|&i|w.rfind('/').is_none_or(|j|i>j)).map_or(w.clone(),|i|w[..i].into())).collect::<Vec<_>>().join(" "),
            "addsuffix"=>list(1).iter().map(|w|w.clone()+&args[0]).collect::<Vec<_>>().join(" "),"addprefix"=>list(1).iter().map(|w|args[0].clone()+w).collect::<Vec<_>>().join(" "),"wildcard"=>list(0).iter().flat_map(|p|self.glob(p)).collect::<Vec<_>>().join(" "),_=>unreachable!()
        };
        Ok(result)
    }
    fn glob(&self,pattern: &str) -> Vec<String> {
        if pattern.contains('*') || pattern.contains('?') {
            self.files.keys().filter(|n|wildcard(pattern,n)).cloned().collect()
        } else if self.files.contains_key(pattern) {
            vec![pattern.into()]
        } else {
            Vec::new()
        }
    }
    fn register(&mut self,n: &str,deps: Vec<String>) {
        let rule=self.rules.entry(n.into()).or_insert_with(||Rule::new(n.into(),Vec::new()));
        for d in unique(deps) {
            if !rule.deps.contains(&d) {
                rule.deps.push(d);
            }
        }
        if self.goal.is_none() && !n.starts_with('.') {
            self.goal=Some(n.into());
        }
    }
    fn add_recipe(&mut self,current: &mut Current,line: RecipeLine) {
        if current.targets.is_empty() && current.patterns.is_empty() {
            return;
        }
        if current.recipe.is_none() {
            let fresh=Rc::new(RefCell::new(Vec::new()));
            for n in &current.targets {
                let rule=self.rules.get_mut(n).unwrap();
                if let Some(old)=&rule.recipe {
                    self.output.push(format!("Makefile:{}: warning: overriding recipe for target '{}'",line.number,n));
                    self.output.push(format!("Makefile:{}: warning: ignoring old recipe for target '{}'",old.borrow()[0].number,n));
                }
                rule.recipe=Some(fresh.clone());
            }
            for &i in &current.patterns {
                self.patterns[i].recipe=Some(fresh.clone());
            }
            current.recipe=Some(fresh);
        }
        current.recipe.as_ref().unwrap().borrow_mut().push(line);
    }
    fn load(&mut self,body: &[String]) {
        self.clear();
        let result=self.load_body(body);
        if let Err(reason)=result {
            self.diagnostic(&reason);
            self.clear();
        }
        self.location="make".into();
        self.scopes.clear();
        self.expanding.clear();
        self.automatic.clear();
    }
    fn load_body(&mut self,body: &[String]) -> Expanded<()> {
        let mut current:Option<Current>=None;
        let mut conditions:Vec<Condition>=Vec::new();
        let active=|stack:&[Condition]|stack.last().is_none_or(|c|c.outer && c.value);
        let mut i=0;
        while i<body.len() {
            let line_number=i+1;
            self.location=format!("Makefile:{}",line_number);
            let mut text=body[i].clone();
            i+=1;
            if text.starts_with('>') {
                if !active(&conditions) {
                    continue;
                }
                let rule=current.as_mut().ok_or("recipe commences before first target")?;
                self.add_recipe(rule,RecipeLine {
                    number:line_number,text:text[1..].trim_start_matches(' ').into()
                });
                continue;
            }
            while text.ends_with('\\') && i<body.len() {
                text.pop();
                text=text.trim_end_matches(' ').to_string()+" "+body[i].trim_start_matches(' ');
                i+=1;
            }
            text=text.split('#').next().unwrap().trim_matches(' ').into();
            let(first,rest)=text.split_once(' ').unwrap_or((&text,""));
            let rest=rest.trim_matches(' ');
            match first {
                "ifdef"|"ifndef"|"ifeq"|"ifneq"=> {
                    let outer=active(&conditions);
                    let mut truth=false;
                    if outer {
                        if first=="ifdef" || first=="ifndef" {
                            let n=self.expand(rest)?.trim_matches(' ').to_string();
                            truth=self.variables.get(&n).is_some_and(|v|!v.value.is_empty());
                            if first=="ifndef" {
                                truth=!truth;
                            }
                        } else {
                            if rest.len()<2 || !rest.starts_with('(') || !rest.ends_with(')') {
                                return Err("invalid syntax in conditional".into());
                            }
                            let inner=&rest[1..rest.len()-1];
                            let mut depth=0;
                            let mut comma=None;
                            for(j,c)in inner.bytes().enumerate() {
                                if c==b'(' {
                                    depth+=1;
                                }
                                if c==b')' {
                                    depth-=1;
                                }
                                if c==b',' && depth==0 {
                                    comma=Some(j);
                                    break;
                                }
                            }
                            let comma=comma.ok_or("invalid syntax in conditional")?;
                            let left=self.expand(&inner[..comma])?.trim_matches(' ').to_string();
                            let right=self.expand(&inner[comma+1..])?.trim_matches(' ').to_string();
                            truth=(left==right)==(first=="ifeq");
                        }
                    }
                    conditions.push(Condition {
                        outer,value:truth,had_else:false,line:line_number
                    });
                    continue;
                },"else"=> {
                    let top=conditions.last_mut().ok_or("extraneous 'else'")?;
                    if top.had_else {
                        return Err("only one 'else' per conditional".into());
                    }
                    top.value=!top.value;
                    top.had_else=true;
                    continue;
                },"endif"=> {
                    conditions.pop().ok_or("extraneous 'endif'")?;
                    continue;
                },_=> {
                }
            }
            if text.is_empty() || !active(&conditions) {
                continue;
            }
            let positions=Self::outside(&text)?;
            let equal=positions.get(&b'=').copied();
            let colon=positions.get(&b':').copied();
            if equal.is_some_and(|eq|colon.is_none_or(|col|col+1>=eq)) {
                let eq=equal.unwrap();
                let special=eq>0 && b":+?".contains(&text.as_bytes()[eq-1]);
                let op=if special {
                    &text[eq-1..eq+1]
                } else {
                    "="
                };
                let n=text[..eq-usize::from(special)].trim_matches(' ');
                let rhs=text[eq+1..].trim_matches(' ');
                if n.is_empty() {
                    return Err("empty variable name".into());
                }
                let old=self.variables.get(n).cloned();
                match op {
                    "="=> {
                        self.variables.insert(n.into(),Variable {
                            simple:false,value:rhs.into()
                        });
                    },":="=> {
                        let value=self.expand(rhs)?;
                        self.variables.insert(n.into(),Variable {
                            simple:true,value
                        });
                    },"?="=>if old.is_none() {
                        self.variables.insert(n.into(),Variable {
                            simple:false,value:rhs.into()
                        });
                    },"+="=> {
                        let v=if let Some(old)=old {
                            let a=if old.simple {
                                self.expand(rhs)?
                            } else {
                                rhs.into()
                            };
                            Variable {
                                simple:old.simple,value:if old.value.is_empty() {
                                    a
                                } else {
                                    old.value+" "+&a
                                }
                            }
                        } else {
                            Variable {
                                simple:false,value:rhs.into()
                            }
                        };
                        self.variables.insert(n.into(),v);
                    },_=>unreachable!()
                }
                current=None;
            } else if let Some(colon)=colon {
                let targets=unique(words(&self.expand(&text[..colon])?));
                let mut remainder=text[colon+1..].to_string();
                let semi=Self::outside(&remainder)?.get(&b';').copied();
                let inline=semi.map(|j|remainder[j+1..].trim_start_matches(' ').to_string());
                if let Some(j)=semi {
                    remainder.truncate(j);
                }
                let second=Self::outside(&remainder)?.get(&b':').copied();
                let target_pattern=if let Some(j)=second {
                    Some(self.expand(&remainder[..j])?.trim_matches(' ').to_string())
                } else {
                    None
                };
                if let Some(j)=second {
                    remainder=remainder[j+1..].into();
                }
                let deps=words(&self.expand(&remainder)?);
                let mut registered=Vec::new();
                let mut implicit=Vec::new();
                if targets.len()==1 && targets[0]==".PHONY" {
                    self.phony.extend(deps);
                } else if let Some(pattern)=target_pattern {
                    if !pattern.contains('%') {
                        return Err("target pattern contains no '%'".into());
                    }
                    for t in targets {
                        if let Some(m)=stem(&pattern,&t).filter(|m|!m.is_empty()) {
                            self.register(&t,deps.iter().map(|d|substitute(d,&m)).collect());
                            self.rules.get_mut(&t).unwrap().stem=m;
                            registered.push(t);
                        } else {
                            self.output.push(format!("Makefile:{}: target '{}' doesn't match the target pattern",line_number,t));
                        }
                    }
                } else if targets.iter().any(|t|t.contains('%')) {
                    if targets.iter().any(|t|!t.contains('%')) {
                        return Err("mixed implicit and normal rules".into());
                    }
                    for t in targets {
                        implicit.push(self.patterns.len());
                        self.patterns.push(Rule::new(t,deps.clone()));
                    }
                } else {
                    for t in targets {
                        self.register(&t,deps.clone());
                        registered.push(t);
                    }
                }
                let mut rule=Current {
                    targets:registered,patterns:implicit,recipe:None
                };
                if let Some(text)=inline {
                    self.add_recipe(&mut rule,RecipeLine {
                        number:line_number,text
                    });
                }
                current=Some(rule);
            } else if !self.expand(&text)?.trim_matches(' ').is_empty() {
                return Err("missing separator".into());
            }
        }
        if let Some(top)=conditions.last() {
            self.location=format!("Makefile:{}",top.line);
            return Err("missing 'endif'".into());
        }
        self.loaded=true;
        self.output.push(format!("Makefile loaded: lines={} variables={} targets={} patterns={} goal={}",body.len(),self.variables.len(),self.rules.len(),self.patterns.iter().filter(|r|r.recipe.is_some()).count(),self.goal.as_deref().unwrap_or("(none)")));
        Ok(())
    }
    fn determine(&self,t: &str) -> Determined {
        let explicit=self.rules.get(t);
        if let Some(r)=explicit.filter(|r|r.recipe.is_some()) {
            return Determined {
                deps:r.deps.clone(),recipe:r.recipe.clone(),stem:r.stem.clone(),source:false,absent:false
            };
        }
        if !self.phony.contains(t) {
            let mut candidates=self.patterns.iter().enumerate().filter_map(|(i,r)|if r.recipe.is_some() {
                stem(&r.target,t).filter(|m|!m.is_empty()).map(|m|(r,m,i))
            } else {
                None
            }).collect::<Vec<_>>();
            candidates.sort_by_key(|(_,m,i)|(m.len(),*i));
            for(r,m,_)in candidates {
                let mut deps=r.deps.iter().map(|d|substitute(d,&m)).collect::<Vec<_>>();
                if deps.iter().all(|d|self.files.contains_key(d)||self.rules.contains_key(d)) {
                    if let Some(r)=explicit {
                        deps.extend_from_slice(&r.deps);
                    }
                    return Determined {
                        deps:unique(deps),recipe:r.recipe.clone(),stem:m,source:false,absent:false
                    };
                }
            }
        }
        if explicit.is_some() || self.phony.contains(t) {
            return Determined {
                deps:explicit.map_or(Vec::new(),|r|r.deps.clone()),recipe:None,stem:explicit.map_or(String::new(),|r|r.stem.clone()),source:false,absent:false
            };
        }
        Determined {
            deps:Vec::new(),recipe:None,stem:String::new(),source:self.files.contains_key(t),absent:!self.files.contains_key(t)
        }
    }
    fn make(&mut self,args: &[String]) {
        let mut options=BTreeSet::new();
        let mut goals=Vec::new();
        for arg in args {
            if arg.starts_with('-') {
                for c in arg[1..].chars() {
                    if !"nBkis".contains(c) {
                        self.output.push(format!("make: invalid option -- '{}'",c));
                        return;
                    }
                    options.insert(c);
                }
            } else {
                goals.push(arg.clone());
            }
        }
        if goals.is_empty() {
            if !self.loaded {
                self.output.push("make: *** No targets specified and no makefile found.  Stop.".into());
                return;
            }
            if let Some(goal)=&self.goal {
                goals.push(goal.clone());
            } else {
                self.output.push("make: *** No targets.  Stop.".into());
                return;
            }
        }
        let dry=options.contains(&'n');
        let original=if dry {
            Some((self.files.clone(),self.clock))
        } else {
            None
        };
        let mut build=Build {
            sim:self,options,results:BTreeMap::new(),used:BTreeMap::new(),being:BTreeSet::new(),runs:0
        };
        for g in goals {
            let before=build.runs;
            let result=match build.target(&g,None) {
                Ok(result)=>result,Err(())=>break
            };
            if result==Status::Success && before==build.runs {
                let text=if build.sim.phony.contains(&g)||build.used[&g].recipe.is_none() {
                    format!("make: Nothing to be done for '{}'.",g)
                } else {
                    format!("make: '{}' is up to date.",g)
                };
                build.sim.output.push(text);
            } else if result==Status::DependencyFailure {
                build.sim.output.push(format!("make: Target '{}' not remade because of errors.",g));
            }
        }
        if let Some((files,clock))=original {
            build.sim.files=files;
            build.sim.clock=clock;
        }
        build.sim.automatic.clear();
        build.sim.scopes.clear();
        build.sim.expanding.clear();
        build.sim.location="make".into();
    }
    fn command(&mut self,line: &str) {
        self.output.push(format!("$ {}",line));
        let w=words(line);
        match w[0].as_str() {
            "MAKE"=>self.make(&w[1..]),"TOUCH"=>for n in &w[1..] {
                self.tick(n);
            },"RM"=>for n in &w[1..] {
                if self.files.remove(n).is_none() {
                    self.output.push(format!("rm: cannot remove '{}': No such file or directory",n));
                }
            },"FILES"=> {
                self.output.push(format!("clock {}",self.clock));
                self.output.extend(self.files.iter().map(|(n,t)|format!("{} {}",n,t)));
            },"RULES" if self.loaded=> {
                for r in self.rules.values().chain(self.patterns.iter().filter(|r|r.recipe.is_some())) {
                    self.output.push(format!("{}:{}",r.target,r.deps.iter().map(|d|format!(" {}",d)).collect::<String>()));
                    if let Some(recipe)=&r.recipe {
                        self.output.extend(recipe.borrow().iter().map(|line|format!(">{}",line.text)));
                    }
                }
                if !self.phony.is_empty() {
                    self.output.push(format!(".PHONY:{}",self.phony.iter().map(|n|format!(" {}",n)).collect::<String>()));
                }
            },"VARS" if self.loaded=> {
                let names=self.variables.keys().cloned().collect::<Vec<_>>();
                for n in names {
                    match self.value(&n) {
                        Ok(s)=> {
                            let s=s.trim_matches(' ');
                            self.output.push(format!("{} {}{}",n,if self.variables[&n].simple {
                                ":="
                            } else {
                                "="
                            },if s.is_empty() {
                                String::new()
                            } else {
                                format!(" {}",s)
                            }));
                        },Err(reason)=> {
                            self.diagnostic(&reason);
                            break;
                        }
                    }
                }
            },"EXPAND"=>match self.expand(&line[7..]) {
                Ok(s)=>self.output.push(format!("[{}]",s)),Err(reason)=>self.diagnostic(&reason)
            },_=> {
            }
        }
    }
}
#[derive(Clone)]
struct Determined {
    deps: Vec<String>,
    recipe: Option<Recipe>,
    stem: String,
    source: bool,
    absent: bool
}
#[derive(Clone,Copy,PartialEq,Eq)]
enum Status {
    Success,Failure,DependencyFailure
}

struct Build<'a> {
    sim: &'a mut Simulator,
    options: BTreeSet<char>,
    results: BTreeMap<String,Status>,
    used: BTreeMap<String,Determined>,
    being: BTreeSet<String>,
    runs: usize
}

impl Build<'_> {
    fn time(&self,t: &str) -> Option<i64> {
        if self.sim.phony.contains(t) {
            None
        } else {
            self.sim.files.get(t).copied()
        }
    }
    fn execute(&mut self,command: &str) -> usize {
        let w=words(command);
        match w[0].as_str() {
            "echo"=>self.sim.output.push(w[1..].join(" ")),"touch"=>for n in &w[1..] {
                self.sim.tick(n);
            },"rm"=> {
                let force=w.get(1).is_some_and(|s|s=="-f");
                let mut status=0;
                for p in &w[if force {
                    2
                } else {
                    1
                }..] {
                    let mut names=self.sim.glob(p);
                    if names.is_empty() {
                        names.push(p.clone());
                    }
                    for n in names {
                        if self.sim.files.remove(&n).is_none() && !force {
                            self.sim.output.push(format!("rm: cannot remove '{}': No such file or directory",n));
                            status=1;
                        }
                    }
                }
                return status;
            },"false"=>return 1,"exit"=>return w.get(1).map_or(0,|s|s.parse().unwrap()),_=> {
            }
        }
        0
    }
    fn run(&mut self,t: &str,d: &Determined,deps: &[String],fresh: &[String]) -> Result<Status,()> {
        self.sim.automatic=[("@",t.to_string()),("<",deps.first().cloned().unwrap_or_default()),("^",deps.join(" ")),("?",fresh.join(" ")),("*",d.stem.clone())].iter().map(|(n,v)|(n.to_string(),v.clone())).collect();
        let recipe=d.recipe.as_ref().unwrap().borrow().clone();
        let mut expanded=Vec::new();
        for line in recipe {
            self.sim.location=format!("Makefile:{}",line.number);
            match self.sim.expand(&line.text) {
                Ok(text)=>expanded.push((line,text)),Err(reason)=> {
                    self.sim.diagnostic(&reason);
                    self.sim.automatic.clear();
                    self.sim.location="make".into();
                    return Err(());
                }
            }
        }
        self.sim.automatic.clear();
        self.sim.location="make".into();
        let dry=self.options.contains(&'n');
        for(line,text)in expanded {
            let prefix=text.bytes().take_while(|b|b" @-".contains(b)).count();
            let flags=&text[..prefix];
            let command=text[prefix..].trim_end_matches(' ');
            if command.is_empty() {
                continue;
            }
            if dry || (!flags.contains('@')&&!self.options.contains(&'s')) {
                self.sim.output.push(command.into());
            }
            if dry {
                continue;
            }
            let status=self.execute(command);
            if status!=0 {
                if flags.contains('-')||self.options.contains(&'i') {
                    self.sim.output.push(format!("make: [Makefile:{}: {}] Error {} (ignored)",line.number,t,status));
                } else {
                    self.sim.output.push(format!("make: *** [Makefile:{}: {}] Error {}",line.number,t,status));
                    if !self.options.contains(&'k') {
                        return Err(());
                    }
                    return Ok(Status::Failure);
                }
            }
        }
        Ok(Status::Success)
    }
    fn target(&mut self,t: &str,parent: Option<&str>) -> Result<Status,()> {
        if let Some(status)=self.results.get(t) {
            return Ok(*status);
        }
        let d=self.sim.determine(t);
        self.used.insert(t.into(),d.clone());
        if d.absent {
            self.results.insert(t.into(),Status::Failure);
            let keep=self.options.contains(&'k');
            self.sim.output.push(format!("make: *** No rule to make target '{}'{}.{}",t,parent.map_or(String::new(),|p|format!(", needed by '{}'",p)),if keep {
                ""
            } else {
                "  Stop."
            }));
            return if keep {
                Ok(Status::Failure)
            } else {
                Err(())
            };
        }
        if d.source {
            self.results.insert(t.into(),Status::Success);
            return Ok(Status::Success);
        }
        self.being.insert(t.into());
        let mut deps=Vec::new();
        let mut failed=false;
        for q in &d.deps {
            if self.being.contains(q) {
                self.sim.output.push(format!("make: Circular {} <- {} dependency dropped.",t,q));
            } else {
                deps.push(q.clone());
                if self.target(q,Some(t))?!=Status::Success {
                    failed=true;
                }
            }
        }
        self.being.remove(t);
        let result=if failed {
            Status::DependencyFailure
        } else {
            let time=self.time(t);
            let fresh=deps.iter().filter(|n|self.options.contains(&'B')||time.is_none()||self.time(n).is_none()||self.time(n)>time).cloned().collect::<Vec<_>>();
            if d.recipe.is_none()||(!self.options.contains(&'B')&&time.is_some()&&fresh.is_empty()) {
                Status::Success
            } else {
                self.runs+=1;
                let status=self.run(t,&d,&deps,&fresh)?;
                if status==Status::Success&&!self.sim.phony.contains(t) {
                    self.sim.tick(t);
                }
                status
            }
        };
        self.results.insert(t.into(),result);
        Ok(result)
    }
}

fn main() {
    let mut input=String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let lines=input.lines().collect::<Vec<_>>();
    let mut sim=Simulator::new();
    let mut i=1;
    while lines[i]!="END FILES" {
        let w=words(lines[i]);
        let time:i64=w[1].parse().unwrap();
        sim.files.insert(w[0].clone(),time);
        sim.clock=sim.clock.max(time);
        i+=1;
    }
    i+=1;
    while lines[i]!="QUIT" {
        let line=lines[i];
        i+=1;
        if line=="MAKEFILE" {
            sim.output.push("$ MAKEFILE".into());
            let mut body=Vec::new();
            while lines[i]!="END MAKEFILE" {
                body.push(lines[i].to_string());
                i+=1;
            }
            i+=1;
            sim.load(&body);
        } else {
            sim.command(line);
        }
    }
    for line in sim.output {
        println!("{}",line);
    }
}
