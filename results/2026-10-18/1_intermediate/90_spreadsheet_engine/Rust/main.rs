use std::collections::BTreeSet;
use std::io::{self, Read};
use std::rc::Rc;

type Tree = Rc<Node>;
#[derive(Clone, PartialEq, Eq)]
struct Reference { col: i32, row: i32, flags: u8 }
#[derive(Clone, PartialEq, Eq)]
enum Node {
    Empty, Int(i64), Text(String), Error(&'static str), Name(String),
    Ref(Reference), Range(Reference, Reference), Invalid,
    Call(String, Vec<Tree>), Neg(Tree), Binary(String, Tree, Tree), Formula(Tree),
}
fn num(n: i64) -> Tree { Rc::new(Node::Int(n)) }
fn text(s: String) -> Tree { Rc::new(Node::Text(s)) }
fn error(s: &'static str) -> Tree { Rc::new(Node::Error(s)) }
fn invalid() -> Tree { Rc::new(Node::Invalid) }
fn empty() -> Tree { Rc::new(Node::Empty) }
fn id(r: &Reference) -> usize { (r.row * 26 + r.col) as usize }
fn label(i: usize) -> String { format!("{}{}", (b'A' + (i % 26) as u8) as char, i / 26 + 1) }
fn inside(r: &Reference) -> bool { (0..26).contains(&r.col) && (0..99).contains(&r.row) }
fn normalized(a: &Reference, b: &Reference) -> (Reference, Reference) {
    let (mut a,mut b)=(a.clone(),b.clone());
    if a.col>b.col { std::mem::swap(&mut a.col,&mut b.col);let ac=a.flags&1;let bc=b.flags&1;a.flags=(a.flags&2)|bc;b.flags=(b.flags&2)|ac; }
    if a.row>b.row { std::mem::swap(&mut a.row,&mut b.row);let ar=a.flags&2;let br=b.flags&2;a.flags=(a.flags&1)|br;b.flags=(b.flags&1)|ar; }
    (a,b)
}
#[derive(Clone)]
struct Area { a: Reference, b: Reference }
impl Area {
    fn cells(&self) -> Vec<usize> { (self.a.row..=self.b.row).flat_map(|r|(self.a.col..=self.b.col).map(move |c|(r*26+c) as usize)).collect() }
    fn contains(&self,r: &Reference) -> bool { (self.a.col..=self.b.col).contains(&r.col)&&(self.a.row..=self.b.row).contains(&r.row) }
}
fn valid_row(s: &str) -> bool { let b=s.as_bytes();(b.len()==1||b.len()==2)&&b[0]>=b'1'&&b[0]<=b'9'&&(b.len()==1||b[1].is_ascii_digit()) }
fn address(s: &str) -> Result<Reference,String> {
    let b=s.as_bytes();if b.len()<2||!b[0].is_ascii_uppercase()||!valid_row(&s[1..]) {return Err("bad address".into())}
    Ok(Reference{col:(b[0]-b'A') as i32,row:s[1..].parse::<i32>().unwrap()-1,flags:0})
}
fn area(s: &str) -> Result<Area,String> {
    let p:Vec<_>=s.split(':').collect();if p.len()>2{return Err("bad address".into())}
    let a=address(p[0])?;let b=if p.len()==1{a.clone()}else{address(p[1])?};let(a,b)=normalized(&a,&b);Ok(Area{a,b})
}
fn reference(s: &str) -> Option<Reference> {
    let b=s.as_bytes();let(mut i,mut f)=(0,0);
    if b.get(i)==Some(&b'$'){f|=1;i+=1}let c=*b.get(i)?;if !c.is_ascii_uppercase(){return None}i+=1;
    if b.get(i)==Some(&b'$'){f|=2;i+=1}if !valid_row(&s[i..]){return None}
    Some(Reference{col:(c-b'A') as i32,row:s[i..].parse::<i32>().ok()?-1,flags:f})
}
fn precedence(op: &str) -> i32 { match op {"="|"<>"|"<"|"<="|">"|">="=>0,"&"=>1,"+"|"-"=>2,"*"|"/"=>3,_=>-1} }
#[derive(Clone)]
enum Token { Value(Tree), Call(String), Symbol(String), End }
struct Parser { tokens: Vec<(Token,usize)>, at: usize }
fn syntax(p: usize) -> String { format!("syntax error at {p}") }
impl Parser {
    fn new(s: &str) -> Result<Self,String> {
        let bytes=s.as_bytes();let mut i=1;let mut tokens=Vec::new();
        while i<bytes.len() {
            let(p,ch)=(i+1,bytes[i]);if ch==b' '{i+=1;continue}
            let token;
            if ch.is_ascii_digit() {
                let mut j=i;while j<bytes.len()&&bytes[j].is_ascii_digit(){j+=1}if j-i>=10{return Err(syntax(p))}
                token=Token::Value(num(s[i..j].parse().unwrap()));i=j;
            } else if ch==b'"' {
                let j=s[i+1..].find('"').map(|v|i+1+v).ok_or_else(||syntax(p))?;
                token=Token::Value(text(s[i+1..j].into()));i=j+1;
            } else if ch.is_ascii_alphabetic()||ch==b'$' {
                let mut j=i;while j<bytes.len()&&(bytes[j].is_ascii_alphanumeric()||bytes[j]==b'$'){j+=1}
                let w=s[i..j].to_ascii_uppercase();i=j;
                if let Some(r)=reference(&w){token=Token::Value(Rc::new(Node::Ref(r)))}
                else if w.as_bytes()[0].is_ascii_uppercase()&&w.bytes().all(|c|c.is_ascii_alphanumeric()) {
                    token=if s[j..].trim_start_matches(' ').starts_with('('){Token::Call(w)}else{Token::Value(Rc::new(Node::Name(w)))};
                }else{return Err(syntax(p))}
            } else {
                let pair=&s[i..(i+2).min(s.len())];let op=if ["<>","<=",">="].contains(&pair){pair}else{&s[i..i+1]};
                if !b"+-*/&(),:=<>".contains(&ch){return Err(syntax(p))}token=Token::Symbol(op.into());i+=op.len();
            }
            tokens.push((token,p));
        }
        tokens.push((Token::End,s.len()+1));Ok(Self{tokens,at:0})
    }
    fn take(&mut self,op: &str) -> bool { if matches!(&self.tokens[self.at].0,Token::Symbol(s) if s==op){self.at+=1;true}else{false} }
    fn expect(&mut self,op: &str) -> Result<(),String> { if self.take(op){Ok(())}else{Err(syntax(self.tokens[self.at].1))} }
    fn expression(&mut self,level: i32) -> Result<Tree,String> {
        if level==4{return self.primary()}let mut a=self.expression(level+1)?;
        while let Token::Symbol(op)=self.tokens[self.at].0.clone() {
            if precedence(&op)!=level{break}self.at+=1;let b=self.expression(level+1)?;a=Rc::new(Node::Binary(op,a,b));
        }Ok(a)
    }
    fn primary(&mut self) -> Result<Tree,String> {
        if self.take("-"){return Ok(Rc::new(Node::Neg(self.primary()?)))}
        let(t,p)=self.tokens[self.at].clone();self.at+=1;
        match t {
            Token::Value(x)=>{
                if let Node::Ref(a)=x.as_ref(){if self.take(":"){
                    let Token::Value(y)=self.tokens[self.at].0.clone() else{return Err(syntax(self.tokens[self.at].1))};
                    let Node::Ref(b)=y.as_ref() else{return Err(syntax(self.tokens[self.at].1))};self.at+=1;let(a,b)=normalized(a,b);return Ok(Rc::new(Node::Range(a,b)))
                }}Ok(x)
            }
            Token::Call(name)=>{self.expect("(")?;let mut args=Vec::new();if !self.take(")"){args.push(self.expression(0)?);while self.take(","){args.push(self.expression(0)?)}self.expect(")")?}Ok(Rc::new(Node::Call(name,args)))}
            Token::Symbol(op) if op=="("=>{let a=self.expression(0)?;self.expect(")")?;Ok(a)}
            _=>Err(syntax(p)),
        }
    }
    fn parse(mut self) -> Result<Tree,String> {let a=self.expression(0)?;if !matches!(self.tokens[self.at].0,Token::End){return Err(syntax(self.tokens[self.at].1))}Ok(a)}
}
fn reference_text(r: &Reference) -> String {format!("{}{}{}{}",if r.flags&1!=0{"$"}else{""},(b'A'+r.col as u8) as char,if r.flags&2!=0{"$"}else{""},r.row+1)}
fn canonical(x: &Tree) -> String {
    match x.as_ref() {
        Node::Int(n)=>n.to_string(),Node::Text(s)=>format!("\"{s}\""),Node::Name(s)=>s.clone(),Node::Invalid=>"#REF!".into(),
        Node::Ref(r)=>reference_text(r),Node::Range(a,b)=>format!("{}:{}",reference_text(a),reference_text(b)),
        Node::Call(name,args)=>format!("{}({})",name,args.iter().map(canonical).collect::<Vec<_>>().join(",")),
        Node::Neg(a)=>if matches!(a.as_ref(),Node::Binary(..)){format!("-({})",canonical(a))}else{format!("-{}",canonical(a))},
        Node::Binary(op,a,b)=>{
            let(mut left,mut right)=(canonical(a),canonical(b));
            if let Node::Binary(p,..)=a.as_ref(){if precedence(p)<precedence(op){left=format!("({left})")}}
            if let Node::Binary(p,..)=b.as_ref(){if precedence(p)<=precedence(op){right=format!("({right})")}}
            format!("{left}{op}{right}")
        }
        _=>unreachable!(),
    }
}
fn display(x: &Tree) -> String {match x.as_ref(){Node::Empty=>String::new(),Node::Int(n)=>n.to_string(),Node::Text(s)=>s.clone(),Node::Error(s)=>(*s).into(),_=>unreachable!()}}
fn notation(x: &Tree) -> String {match x.as_ref(){Node::Empty=>"(empty)".into(),Node::Formula(a)=>format!("={}",canonical(a)),Node::Text(s)=>format!("\"{s}\""),_=>display(x)}}
fn number(x: &Tree) -> Tree {match x.as_ref(){Node::Empty=>num(0),Node::Text(_)|Node::Range(..)=>error("#VALUE!"),_=>x.clone()}}
fn string_value(x: &Tree) -> Tree {match x.as_ref(){Node::Empty=>text(String::new()),Node::Int(n)=>text(n.to_string()),Node::Range(..)=>error("#VALUE!"),_=>x.clone()}}
fn rewrite(x: &Tree,f: &impl Fn(&Node)->Tree) -> Tree {
    match x.as_ref(){
        Node::Ref(_)|Node::Range(..)=>f(x.as_ref()),Node::Formula(a)=>Rc::new(Node::Formula(rewrite(a,f))),
        Node::Call(name,args)=>Rc::new(Node::Call(name.clone(),args.iter().map(|a|rewrite(a,f)).collect())),
        Node::Neg(a)=>Rc::new(Node::Neg(rewrite(a,f))),Node::Binary(op,a,b)=>Rc::new(Node::Binary(op.clone(),rewrite(a,f),rewrite(b,f))),_=>x.clone(),
    }
}
fn dependencies(x: &Tree,out: &mut BTreeSet<usize>){
    match x.as_ref(){Node::Ref(r)=>{out.insert(id(r));},Node::Range(a,b)=>out.extend(Area{a:a.clone(),b:b.clone()}.cells()),Node::Call(_,args)=>for a in args{dependencies(a,out)},Node::Neg(a)|Node::Formula(a)=>dependencies(a,out),Node::Binary(_,a,b)=>{dependencies(a,out);dependencies(b,out)},_=>()}
}
fn evaluate(x: &Tree,values: &[Tree]) -> Tree {
    match x.as_ref(){
        Node::Int(_)|Node::Text(_)|Node::Range(..)=>x.clone(),Node::Ref(r)=>values[id(r)].clone(),Node::Name(_)=>error("#NAME?"),Node::Invalid=>error("#REF!"),
        Node::Neg(a)=>{let a=number(&evaluate(a,values));match a.as_ref(){Node::Error(_)=>a.clone(),Node::Int(n)=>num(-n),_=>unreachable!()}},
        Node::Binary(op,a,b)=>{
            let(mut a,mut b)=(evaluate(a,values),evaluate(b,values));if matches!(a.as_ref(),Node::Error(_)){return a}if matches!(b.as_ref(),Node::Error(_)){return b}
            if precedence(op)==0 {
                if matches!(a.as_ref(),Node::Range(..))||matches!(b.as_ref(),Node::Range(..)){return error("#VALUE!")}
                let blank=if matches!(a.as_ref(),Node::Text(_))||matches!(b.as_ref(),Node::Text(_)){text(String::new())}else{num(0)};
                if matches!(a.as_ref(),Node::Empty){a=blank.clone()}if matches!(b.as_ref(),Node::Empty){b=blank}
                let c=match(a.as_ref(),b.as_ref()){(Node::Int(a),Node::Int(b))=>a.cmp(b),(Node::Text(a),Node::Text(b))=>a.cmp(b),(Node::Int(_),Node::Text(_))=>std::cmp::Ordering::Less,_=>std::cmp::Ordering::Greater};
                let yes=match op.as_str(){"="=>c.is_eq(),"<>"=>!c.is_eq(),"<"=>c.is_lt(),"<="=>!c.is_gt(),">"=>c.is_gt(),_=>!c.is_lt()};return num(i64::from(yes))
            }
            if op=="&"{a=string_value(&a);b=string_value(&b)}else{a=number(&a);b=number(&b)}
            if matches!(a.as_ref(),Node::Error(_)){return a}if matches!(b.as_ref(),Node::Error(_)){return b}
            if let(Node::Text(a),Node::Text(b))=(a.as_ref(),b.as_ref()){return text(format!("{a}{b}"))}
            let(Node::Int(a),Node::Int(b))=(a.as_ref(),b.as_ref())else{unreachable!()};
            match op.as_str(){"+"=>num(a+b),"-"=>num(a-b),"*"=>num(a*b),_=>if *b==0{error("#DIV/0!")}else{num(a/b)}}
        }
        Node::Call(name,args)=>{
            if ["SUM","MIN","MAX","COUNT","AVERAGE","AND","OR","CONCAT"].contains(&name.as_str()){
                if args.is_empty(){return error("#VALUE!")}let mut items=Vec::new();
                for a in args{let v=evaluate(a,values);if let Node::Range(a,b)=v.as_ref(){items.extend(Area{a:a.clone(),b:b.clone()}.cells().iter().map(|i|values[*i].clone()))}else{items.push(v)}}
                let ns:Vec<i64>=items.iter().filter_map(|v|if let Node::Int(n)=v.as_ref(){Some(*n)}else{None}).collect();
                if name=="COUNT"{return num(ns.len() as i64)}for v in &items{if matches!(v.as_ref(),Node::Error(_)){return v.clone()}}
                if name=="CONCAT"{return text(items.iter().map(|v|display(&string_value(v))).collect::<String>())}
                let sum:i64=ns.iter().sum();return match name.as_str(){
                    "SUM"=>num(sum),"MIN"=>num(*ns.iter().min().unwrap_or(&0)),"MAX"=>num(*ns.iter().max().unwrap_or(&0)),
                    "AVERAGE"=>if ns.is_empty(){error("#DIV/0!")}else{num(sum/ns.len() as i64)},
                    "AND"=>if ns.is_empty(){error("#VALUE!")}else{num(i64::from(ns.iter().all(|n|*n!=0)))},
                    _=>if ns.is_empty(){error("#VALUE!")}else{num(i64::from(ns.iter().any(|n|*n!=0)))},
                }
            }
            if name=="IF"{
                if args.len()!=2&&args.len()!=3{return error("#VALUE!")}let c=number(&evaluate(&args[0],values));
                return match c.as_ref(){Node::Error(_)=>c.clone(),Node::Int(n)=>if *n!=0{evaluate(&args[1],values)}else if args.len()==3{evaluate(&args[2],values)}else{num(0)},_=>unreachable!()}
            }
            if !["ABS","NOT","LEN"].contains(&name.as_str()){return error("#NAME?")}if args.len()!=1{return error("#VALUE!")}
            let v=evaluate(&args[0],values);let v=if name=="LEN"{string_value(&v)}else{number(&v)};
            match v.as_ref(){Node::Error(_)=>v.clone(),Node::Text(s)=>num(s.len() as i64),Node::Int(n)=>num(if name=="ABS"{n.abs()}else{i64::from(*n==0)}),_=>unreachable!()}
        }
        _=>unreachable!(),
    }
}
struct Graph<'a>{deps:&'a [Vec<usize>],formulas:&'a [bool],index:Vec<usize>,low:Vec<usize>,on:Vec<bool>,cyclic:Vec<bool>,stack:Vec<usize>,serial:usize}
impl Graph<'_>{
    fn visit(&mut self,i:usize){
        self.index[i]=self.serial;self.low[i]=self.serial;self.serial+=1;self.stack.push(i);self.on[i]=true;
        for j in self.deps[i].clone(){if self.formulas[j]{if self.index[j]==usize::MAX{self.visit(j);self.low[i]=self.low[i].min(self.low[j])}else if self.on[j]{self.low[i]=self.low[i].min(self.index[j])}}}
        if self.low[i]==self.index[i]{let mut part=Vec::new();loop{let j=self.stack.pop().unwrap();self.on[j]=false;part.push(j);if j==i{break}}if part.len()>1||self.deps[i].contains(&i){for j in part{self.cyclic[j]=true}}}
    }
}
fn calculate(i:usize,contents:&[Tree],deps:&[Vec<usize>],cyclic:&[bool],done:&mut [bool],values:&mut [Tree]){
    let Node::Formula(tree)=contents[i].as_ref()else{return};if done[i]{return}done[i]=true;if cyclic[i]{values[i]=error("#CYCLE!");return}
    for j in &deps[i]{calculate(*j,contents,deps,cyclic,done,values)}let v=evaluate(tree,values);values[i]=match v.as_ref(){Node::Empty=>num(0),Node::Range(..)=>error("#VALUE!"),_=>v.clone()};
}
struct Sheet{contents:Vec<Tree>,values:Vec<Tree>,deps:Vec<Vec<usize>>,history:Vec<(String,Vec<Tree>)>}
impl Sheet{
    fn new()->Self{Self{contents:vec![empty();2574],values:vec![empty();2574],deps:vec![Vec::new();2574],history:Vec::new()}}
    fn replace(&mut self,next:Vec<Tree>)->usize{
        let old=self.values.clone();self.contents=next;let formulas:Vec<_>=self.contents.iter().map(|x|matches!(x.as_ref(),Node::Formula(_))).collect();
        self.deps=self.contents.iter().map(|x|{let mut out=BTreeSet::new();if matches!(x.as_ref(),Node::Formula(_)){dependencies(x,&mut out)}out.into_iter().collect()}).collect();
        self.values=self.contents.iter().map(|x|if matches!(x.as_ref(),Node::Formula(_)){empty()}else{x.clone()}).collect();
        let mut graph=Graph{deps:&self.deps,formulas:&formulas,index:vec![usize::MAX;2574],low:vec![0;2574],on:vec![false;2574],cyclic:vec![false;2574],stack:Vec::new(),serial:0};
        for i in 0..2574{if formulas[i]&&graph.index[i]==usize::MAX{graph.visit(i)}}let mut done=vec![false;2574];
        for i in 0..2574{calculate(i,&self.contents,&self.deps,&graph.cyclic,&mut done,&mut self.values)}
        old.iter().zip(&self.values).filter(|(a,b)|a!=b).count()
    }
    fn describe(&self,i:usize)->String{format!("{}: {} -> {}",label(i),notation(&self.contents[i]),notation(&self.values[i]))}
    fn execute(&mut self,line:&str)->Result<Vec<String>,String>{
        let(name,rest)=line.split_once(' ').unwrap_or((line,""));
        match name{
            "SHOW"=>return Ok(vec![self.describe(id(&address(rest)?))]),
            "LIST"=>{let out:Vec<_>=(0..2574).filter(|i|!matches!(self.contents[*i].as_ref(),Node::Empty)).map(|i|self.describe(i)).collect();return Ok(if out.is_empty(){vec!["(no cells)".into()]}else{out})},
            "DEPS"=>{let i=id(&address(rest)?);let ds:Vec<_>=(0..2574).filter(|j|self.deps[*j].contains(&i)).collect();let fmt=|xs:&[usize]|if xs.is_empty(){"none".into()}else{xs.iter().map(|i|label(*i)).collect::<Vec<_>>().join(",")};return Ok(vec![format!("{rest}: precedents={} dependents={}",fmt(&self.deps[i]),fmt(&ds))])},
            "PRINT"=>{
                let g=area(rest)?;let rw=(g.b.row+1).to_string().len();let widths:Vec<_>=(g.a.col..=g.b.col).map(|c|(g.a.row..=g.b.row).map(|r|display(&self.values[(r*26+c) as usize]).len()).max().unwrap().max(1)).collect();
                let sep=format!("+{}+{}","-".repeat(rw),widths.iter().map(|w|"-".repeat(*w)+"+").collect::<String>());
                let header=format!("|{}|{}"," ".repeat(rw),widths.iter().enumerate().map(|(j,w)|format!("{:<width$}|",(b'A'+g.a.col as u8+j as u8) as char,width=*w)).collect::<String>());
                let mut out=vec![sep.clone(),header,sep.clone()];for r in g.a.row..=g.b.row{let mut row=format!("|{:>width$}|",r+1,width=rw);for(j,w)in widths.iter().enumerate(){let v=&self.values[(r*26+g.a.col) as usize+j];let s=display(v);row+=&if matches!(v.as_ref(),Node::Int(_)){format!("{s:>width$}|",width=*w)}else{format!("{s:<width$}|",width=*w)}}out.push(row)}out.push(sep);return Ok(out)
            }
            "UNDO"=>{let(command,old)=self.history.pop().ok_or("nothing to undo")?;return Ok(vec![format!("UNDO {command} changed={}",self.replace(old))])},_=>()
        }
        let mut next=self.contents.clone();let mut target=0;
        match name{
            "SET"=>{
                let(a,s)=rest.split_once(' ').unwrap();target=id(&address(a)?);
                next[target]=if s.starts_with('='){Rc::new(Node::Formula(Parser::new(s)?.parse()?))}
                else if s.len()>=2&&s.starts_with('"')&&s.ends_with('"')&&!s[1..s.len()-1].contains('"'){text(s[1..s.len()-1].into())}
                else if s=="0"||{let d=s.strip_prefix('-').unwrap_or(s);d.len()<=9&&!d.is_empty()&&d.as_bytes()[0]>=b'1'&&d.as_bytes()[0]<=b'9'&&d.bytes().all(|c|c.is_ascii_digit())}{num(s.parse().unwrap())}
                else{return Err("bad value".into())};
            }
            "CLEAR"=>for i in area(rest)?.cells(){next[i]=empty()},
            "COPY"|"MOVE"=>{
                let(a,b)=rest.split_once(' ').unwrap();let source=area(a)?;let dest=address(b)?;let(dc,dr)=(dest.col-source.a.col,dest.row-source.a.row);
                let shift=|r:&Reference,relative:bool|Reference{col:r.col+if relative&&r.flags&1!=0{0}else{dc},row:r.row+if relative&&r.flags&2!=0{0}else{dr},flags:r.flags};
                let destination=Area{a:shift(&source.a,false),b:shift(&source.b,false)};if !inside(&destination.a)||!inside(&destination.b){return Err("out of grid".into())}
                let transform=|x:&Node|->Tree{match x{
                    Node::Ref(r)=>{if name=="COPY"{let r=shift(r,true);if inside(&r){Rc::new(Node::Ref(r))}else{invalid()}}else if source.contains(r){Rc::new(Node::Ref(shift(r,false)))}else if destination.contains(r){invalid()}else{Rc::new(x.clone())}},
                    Node::Range(a,b)=>{if name=="MOVE"&&!(source.contains(a)&&source.contains(b)){return Rc::new(x.clone())}let(a,b)=(shift(a,name=="COPY"),shift(b,name=="COPY"));if inside(&a)&&inside(&b){let(a,b)=normalized(&a,&b);Rc::new(Node::Range(a,b))}else{invalid()}},_=>unreachable!()
                }};
                if name=="MOVE"{next=next.iter().map(|x|rewrite(x,&transform)).collect()}let ids=source.cells();let moving:Vec<_>=ids.iter().map(|i|if name=="COPY"{rewrite(&self.contents[*i],&transform)}else{next[*i].clone()}).collect();
                if name=="MOVE"{for i in &ids{next[*i]=empty()}}for(i,x)in ids.into_iter().zip(moving){next[(i as i32+dr*26+dc) as usize]=x}
            }
            "INSERTROW"|"DELETEROW"|"INSERTCOL"|"DELETECOL"=>{
                let row=name.ends_with("ROW");let insert=name.starts_with("INSERT");let limit=if row{99}else{26};
                let at=if row{if !valid_row(rest){return Err("bad address".into())}rest.parse::<i32>().unwrap()-1}else{if rest.len()!=1||!rest.as_bytes()[0].is_ascii_uppercase(){return Err("bad address".into())}(rest.as_bytes()[0]-b'A') as i32};
                let axis=|r:&Reference|if row{r.row}else{r.col};let change=|r:&Reference,v:i32|Reference{col:if row{r.col}else{v},row:if row{v}else{r.row},flags:r.flags};
                if insert&&(0..2574).any(|i|!matches!(self.contents[i].as_ref(),Node::Empty)&&(if row{i as i32/26}else{i as i32%26})==limit-1){return Err(format!("last {} not empty",if row{"row"}else{"column"}))}
                let transform=|x:&Node|->Tree{match x{
                    Node::Ref(r)=>{let v=axis(r);if !insert&&v==at{return invalid()}let n=v+if insert{i32::from(v>=at)}else{-i32::from(v>at)};if n>=limit{invalid()}else{Rc::new(Node::Ref(change(r,n)))}},
                    Node::Range(a,b)=>{let(u,v)=(axis(a),axis(b));if !insert&&u==at&&v==at{return invalid()}let c=u+if insert{i32::from(u>=at)}else{-i32::from(u>at)};let d=v+if insert{i32::from(v>=at)}else{-i32::from(v>=at)};if d>=limit{invalid()}else{Rc::new(Node::Range(change(a,c),change(b,d)))}},_=>unreachable!()
                }};
                next=vec![empty();2574];for i in 0..2574{if matches!(self.contents[i].as_ref(),Node::Empty){continue}let r=Reference{col:(i%26) as i32,row:(i/26) as i32,flags:0};let v=axis(&r);if !insert&&v==at{continue}let t=change(&r,v+if insert{i32::from(v>=at)}else{-i32::from(v>at)});next[id(&t)]=rewrite(&self.contents[i],&transform)}
            }
            _=>return Err("unknown command".into()),
        }
        self.history.push((name.into(),self.contents.clone()));let changed=self.replace(next);Ok(vec![format!("{}{} changed={changed}",name,if name=="SET"{format!(" {}={}",label(target),notation(&self.values[target]))}else{String::new()})])
    }
}
fn main(){let mut input=String::new();io::stdin().read_to_string(&mut input).unwrap();let mut lines=input.lines();let n:usize=lines.next().unwrap().parse().unwrap();let mut sheet=Sheet::new();let mut output=String::new();for line in lines.take(n){match sheet.execute(line){Ok(rows)=>for row in rows{output+=&row;output.push('\n')},Err(e)=>{output+="ERROR ";output+=&e;output.push('\n')}}}print!("{output}");}
