mod lexer;
mod parser;
mod doc_builder;
mod printer;
mod report;
use std::collections::{BTreeMap,BTreeSet};
use std::fs;
use lexer::{Token,Comment,Error};
use parser::Node;
use doc_builder::{Document,Builder,concat,text,nest,align,line,softline,hardline,suffix,break_parent,if_break};
#[derive(Clone)] struct Profile{
    values:BTreeMap<String,String>
}
impl Profile{
    fn yes(&self,key:&str)->bool{
        self.values[key]=="yes"
    }
    fn number(&self,key:&str)->usize{
        self.values[key].parse().unwrap()
    }
    fn kr(&self)->bool{
        self.values["brace_style"]=="kr"
    }
}
fn attach(lexed:lexer::Lexed)->(Vec<Token>,usize){
    let mut tokens=lexed.tokens;
    for(k,&(is_token,index))in lexed.order.iter().enumerate(){
        if is_token{
            continue;
        }
        let mut c=lexed.comments[index].clone();
        let previous=lexed.order[..k].iter().rev().find(|p|p.0).map(|p|p.1);
        let next=lexed.order[k+1..].iter().find(|p|p.0).map(|p|p.1);
        let next_line=lexed.order.get(k+1).map(|&(token,i)|if token{
            tokens[i].line
        }else{
            lexed.comments[i].line
        });
        c.own=c.line_comment||next_line.map_or(true,|line|line>c.line);
        let trailing=previous.map_or(false,|i|tokens[i].line==c.line)&&next.map_or(true,|i|tokens[i].line>c.line);
        if trailing{
            tokens[previous.unwrap()].trailing.push(c);
        }else{
            let next=next.unwrap_or(tokens.len()-1);
            tokens[next].leading.push(c);
        }
    }
    (tokens,lexed.comments.len())
}
fn check_comments(items:&[Node],tokens:&[Token])->Result<(),Error>{
    fn walk(n:&Node,allowed:&mut BTreeSet<usize>,tails:&mut BTreeSet<usize>){
        match n.kind.as_str(){
            "block"=>{
                allowed.insert(n.tokens[1]);
                for c in &n.children{
                    allowed.insert(c.start);
                }
            },"switch"=>{
                allowed.insert(n.tokens[4]);
                for c in n.children.iter().skip(1){
                    allowed.insert(c.tokens[0]);
                    let first=usize::from(c.kind=="case");
                    for s in c.children.iter().skip(first){
                        allowed.insert(s.start);
                    }
                }
            },"if"=>{
                if n.children[1].kind!="block"{
                    allowed.insert(n.children[1].start);
                }
                if n.children.len()==3&&n.children[2].kind!="block"&&n.children[2].kind!="if"{
                    allowed.insert(n.children[2].start);
                }
            },"while"=>{
                if n.children[1].kind!="block"{
                    allowed.insert(n.children[1].start);
                }
            },"for"=>{
                if n.children[3].kind!="block"{
                    allowed.insert(n.children[3].start);
                }
            },"params"|"args"|"initlist"=>{
                for c in &n.children{
                    allowed.insert(c.start);
                }
                if let Some(t)=n.trailing{
                    tails.insert(t);
                }
            },_=>()
        }
        for c in &n.children{
            walk(c,allowed,tails);
        }
    }
    let mut allowed=BTreeSet::new();
    let mut tails=BTreeSet::new();
    allowed.insert(tokens.len()-1);
    for item in items{
        allowed.insert(item.start);
        walk(item,&mut allowed,&mut tails);
    }
    for(i,t)in tokens.iter().enumerate(){
        for c in &t.leading{
            if c.own&&!allowed.contains(&i)||tails.contains(&i){
                return Err(Error{
                    line:c.line,
                    column:c.column,
                    message:"comment not allowed here".into()
                });
            }
        }
    }
    Ok(())
}
struct Construction{
    tokens:Vec<Token>,
    original_trailing:Vec<bool>,
    profile:Profile,
    docs:Builder
}
impl Construction{
    fn space(&self)->Document{
        text(if self.profile.yes("space_around_operators"){
            " "
        }else{
            ""
        })
    }
    fn keyword_space(&self)->Document{
        text(if self.profile.yes("space_after_keyword"){
            " "
        }else{
            ""
        })
    }
    fn operator_line(&self)->Document{
        if self.profile.yes("space_around_operators"){
            line()
        }else{
            softline()
        }
    }
    fn separator(&self,blank:usize)->Document{
        concat((0..=blank.min(self.profile.number("max_blank_lines"))).map(|_|hardline()).collect())
    }
    fn preblank(&self,t:usize)->usize{
        self.tokens[t].leading.first().map_or(self.tokens[t].blank,|c|c.blank)
    }
    fn comments(&self,comments:&[Comment],next:Option<usize>)->Document{
        let mut parts=Vec::new();
        for(i,c)in comments.iter().enumerate(){
            parts.push(text(c.text.clone()));
            let blank=comments.get(i+1).map(|c|c.blank).or(next);
            if let Some(blank)=blank{
                if c.own{
                    parts.push(self.separator(blank));
                }else{
                    parts.push(text(" "));
                }
            }
        }
        concat(parts)
    }
    fn trailing(&self,t:usize)->Document{
        if self.tokens[t].trailing.is_empty(){
            text("")
        }else{
            suffix(self.tokens[t].trailing.iter().map(|c|c.text.clone()).collect::<Vec<_>>().join(" "))
        }
    }
    fn token_with(&self,t:usize,leading:&[Comment])->Document{
        concat(vec![self.comments(leading,Some(self.tokens[t].blank)),text(self.tokens[t].text.clone()),self.trailing(t)])
    }
    fn token(&self,t:usize)->Document{
        self.token_with(t,&self.tokens[t].leading)
    }
    fn group(&mut self,d:Document)->Document{
        self.docs.group(d)
    }
    fn level(&self,n:&Node)->usize{
        match n.kind.as_str(){
            "conditional"=>0,"binary"=>parser::precedence(&self.tokens[n.tokens[0]].text),"unary"=>7,_=>8
        }
    }
    fn open(&mut self,node:&Node,k:usize)->Node{
        let mut n=node.clone();
        while self.profile.yes("remove_parens")&&n.kind=="paren"&&self.level(&n.children[0])>=k&&self.tokens[n.tokens[0]].leading.is_empty()&&self.tokens[n.tokens[1]].leading.is_empty(){
            let child=n.children.remove(0);
            let mut first=std::mem::take(&mut self.tokens[n.tokens[0]].trailing);
            first.extend(std::mem::take(&mut self.tokens[child.start].trailing));
            self.tokens[child.start].trailing=first;
            let last=std::mem::take(&mut self.tokens[n.tokens[1]].trailing);
            self.tokens[child.end].trailing.extend(last);
            n=child;
        }
        n
    }
    fn list(&mut self,n:&Node)->Document{
        let open=n.tokens[0];
        let close=*n.tokens.last().unwrap();
        if n.children.is_empty(){
            return concat(vec![self.token(open),self.token(close)]);
        }
        let mut inside=vec![softline()];
        for(i,child)in n.children.iter().enumerate(){
            if i>0{
                inside.push(self.token(n.tokens[i]));
                inside.push(line());
            }
            let d=if n.kind=="params"{
                self.parameter(child)
            }else if n.kind=="initlist"{
                self.initializer(child)
            }else{
                self.expression(child,0)
            };
            inside.push(d);
        }
        if n.kind=="initlist"{
            inside.push(if_break(",",""));
            if let Some(t)=n.trailing{
                inside.push(self.trailing(t));
            }
        }
        let forced=self.original_trailing[n.start..n.end].iter().any(|&v|v);
        let d=concat(vec![if forced{
            break_parent()
        }else{
            text("")
        },self.token(open),nest(self.profile.number("indent"),concat(inside)),softline(),self.token(close)]);
        self.group(d)
    }
    fn parameter(&mut self,n:&Node)->Document{
        let mut parts=vec![self.token(n.tokens[0]),text(" "),self.token(n.tokens[1])];
        for d in &n.children{
            parts.push(self.token(d.tokens[0]));
            parts.push(self.token(d.tokens[1]));
        }
        concat(parts)
    }
    fn declaration(&mut self,n:&Node)->Document{
        let mut parts=vec![self.token(n.tokens[0]),text(" "),self.token(n.tokens[1])];
        let mut initializer=None;
        for c in &n.children{
            if c.kind=="dimension"{
                parts.push(self.token(c.tokens[0]));
                if let Some(e)=c.children.first(){
                    parts.push(self.expression(e,0));
                }
                parts.push(self.token(c.tokens[1]));
            }else{
                initializer=Some(c);
            }
        }
        for &t in n.tokens.iter().skip(2){
            if self.tokens[t].text=="="{
                parts.push(self.space());
                parts.push(self.token(t));
                parts.push(self.space());
                parts.push(self.initializer(initializer.unwrap()));
            }else{
                parts.push(self.token(t));
            }
        }
        concat(parts)
    }
    fn initializer(&mut self,n:&Node)->Document{
        if n.kind=="initlist"{
            self.list(n)
        }else{
            self.expression(n,0)
        }
    }
    fn closing(&self,t:usize)->(Vec<Comment>,Vec<Comment>){
        let comments=&self.tokens[t].leading;
        let split=comments.iter().rposition(|c|c.own).map_or(0,|i|i+1);
        (comments[..split].to_vec(),comments[split..].to_vec())
    }
    fn block(&mut self,n:&Node)->Document{
        let close=n.tokens[1];
        let(h,g)=self.closing(close);
        if n.children.is_empty()&&h.is_empty(){
            return concat(vec![self.token(n.tokens[0]),self.token_with(close,&g)]);
        }
        let mut inside=vec![hardline()];
        for(i,s)in n.children.iter().enumerate(){
            if i>0{
                inside.push(self.separator(self.preblank(s.start)));
            }
            inside.push(self.statement(s));
        }
        if !h.is_empty(){
            if !n.children.is_empty(){
                inside.push(self.separator(h[0].blank));
            }
            inside.push(self.comments(&h,None));
        }
        concat(vec![self.token(n.tokens[0]),nest(self.profile.number("indent"),concat(inside)),hardline(),self.token_with(close,&g)])
    }
    fn body(&mut self,n:&Node)->Document{
        let separator=if self.profile.kr(){
            text(" ")
        }else{
            hardline()
        };
        if n.kind=="block"{
            let b=self.block(n);
            concat(vec![separator,b])
        }else if self.profile.yes("add_braces"){
            let d=self.statement(n);
            concat(vec![separator,text("{"),nest(self.profile.number("indent"),concat(vec![hardline(),d])),hardline(),text("}")])
        }else{
            let d=self.statement(n);
            nest(self.profile.number("indent"),concat(vec![hardline(),d]))
        }
    }
    fn simple(&mut self,n:&Node)->Document{
        if n.kind=="assign"{
            let left=self.expression(&n.children[0],0);
            let right=self.expression(&n.children[1],0);
            concat(vec![left,self.space(),self.token(n.tokens[0]),self.space(),right])
        }else{
            self.expression(&n.children[0],0)
        }
    }
    fn clause(&mut self,n:&Node)->Document{
        let mut parts=vec![self.token(n.tokens[0])];
        let first=if n.kind=="case"{
            parts.push(text(" "));
            parts.push(self.expression(&n.children[0],0));
            1
        }else{
            0
        };
        parts.push(self.token(n.tokens[1]));
        if n.children.len()>first{
            let mut statements=vec![hardline()];
            for(i,s)in n.children[first..].iter().enumerate(){
                if i>0{
                    statements.push(self.separator(self.preblank(s.start)));
                }
                statements.push(self.statement(s));
            }
            parts.push(nest(self.profile.number("indent"),concat(statements)));
        }
        concat(parts)
    }
    fn statement(&mut self,n:&Node)->Document{
        match n.kind.as_str(){
            "block"=>self.block(n),"decl"=>self.declaration(n),"statement"=>{
                let d=self.simple(&n.children[0]);
                concat(vec![d,self.token(n.tokens[0])])
            },"break"|"continue"=>concat(n.tokens.iter().map(|&t|self.token(t)).collect()),"return"=>{
                let mut parts=vec![self.token(n.tokens[0])];
                if let Some(e)=n.children.first(){
                    parts.push(text(" "));
                    parts.push(self.expression(e,0));
                }
                parts.push(self.token(n.tokens[1]));
                concat(parts)
            },"while"|"if"=>{
                let condition=self.expression(&n.children[0],0);
                let body=self.body(&n.children[1]);
                let mut parts=vec![self.token(n.tokens[0]),self.keyword_space(),self.token(n.tokens[1]),condition,self.token(n.tokens[2]),body];
                if n.kind=="if"&&n.children.len()==3{
                    parts.push(if self.profile.kr()&&(n.children[1].kind=="block"||self.profile.yes("add_braces")){
                        text(" ")
                    }else{
                        hardline()
                    });
                    parts.push(self.token(n.tokens[3]));
                    if n.children[2].kind=="if"{
                        parts.push(text(" "));
                        parts.push(self.statement(&n.children[2]));
                    }else{
                        parts.push(self.body(&n.children[2]));
                    }
                }
                concat(parts)
            },"for"=>{
                let mut inner=Vec::new();
                let init=&n.children[0];
                if init.kind!="empty"{
                    inner.push(if init.kind=="decl"{
                        self.declaration(init)
                    }else{
                        self.simple(init)
                    });
                }
                inner.push(self.token(n.tokens[2]));
                if n.children[1].kind!="empty"{
                    inner.push(line());
                    inner.push(self.expression(&n.children[1],0));
                }
                inner.push(self.token(n.tokens[3]));
                if n.children[2].kind!="empty"{
                    inner.push(line());
                    inner.push(self.simple(&n.children[2]));
                }
                let group=self.group(align(concat(inner)));
                let body=self.body(&n.children[3]);
                concat(vec![self.token(n.tokens[0]),self.keyword_space(),self.token(n.tokens[1]),group,self.token(n.tokens[4]),body])
            },"switch"=>{
                let close=n.tokens[4];
                let(h,g)=self.closing(close);
                let condition=self.expression(&n.children[0],0);
                let mut parts=vec![self.token(n.tokens[0]),self.keyword_space(),self.token(n.tokens[1]),condition,self.token(n.tokens[2]),if self.profile.kr(){
                    text(" ")
                }else{
                    hardline()
                },self.token(n.tokens[3])];
                if n.children.len()>1||!h.is_empty(){
                    let mut inside=vec![hardline()];
                    for(i,c)in n.children[1..].iter().enumerate(){
                        if i>0{
                            inside.push(self.separator(self.preblank(c.start)));
                        }
                        inside.push(self.clause(c));
                    }
                    if !h.is_empty(){
                        if n.children.len()>1{
                            inside.push(self.separator(h[0].blank));
                        }
                        inside.push(self.comments(&h,None));
                    }
                    parts.push(nest(if self.profile.yes("indent_case_labels"){
                        self.profile.number("indent")
                    }else{
                        0
                    },concat(inside)));
                    parts.push(hardline());
                }
                parts.push(self.token_with(close,&g));
                concat(parts)
            },_=>unreachable!()
        }
    }
    fn function(&mut self,n:&Node)->Document{
        let parameters=self.list(&n.children[0]);
        let block=self.block(&n.children[1]);
        concat(vec![self.token(n.tokens[0]),text(" "),self.token(n.tokens[1]),parameters,hardline(),block])
    }
    fn postfix(&mut self,n:&Node)->Document{
        match n.kind.as_str(){
            "call"=>self.list(&n.children[1]),"index"=>{
                let index=self.expression(&n.children[1],0);
                concat(vec![self.token(n.tokens[0]),index,self.token(n.tokens[1])])
            },"member"=>concat(vec![self.token(n.tokens[0]),self.token(n.tokens[1])]),_=>unreachable!()
        }
    }
    fn expression(&mut self,node:&Node,k:usize)->Document{
        let n=self.open(node,k);
        match n.kind.as_str(){
            "atom"=>self.token(n.tokens[0]),"paren"=>{
                let inner=self.expression(&n.children[0],0);
                concat(vec![self.token(n.tokens[0]),inner,self.token(n.tokens[1])])
            },"unary"=>{
                let operand=self.expression(&n.children[0],8);
                concat(vec![self.token(n.tokens[0]),operand])
            },"binary"=>{
                let p=self.level(&n);
                let mut current=n;
                let mut entries=Vec::new();
                while current.kind=="binary"&&self.level(&current)==p{
                    entries.push((current.tokens[0],current.children[1].clone()));
                    current=self.open(&current.children[0],p);
                }
                entries.reverse();
                let head=self.expression(&current,p);
                let mut rest=Vec::new();
                for(op,right)in entries{
                    rest.push(self.operator_line());
                    rest.push(self.token(op));
                    rest.push(self.space());
                    rest.push(self.expression(&right,p+1));
                }
                let d=concat(vec![head,nest(self.profile.number("indent"),concat(rest))]);
                self.group(d)
            },"conditional"=>{
                let head=self.expression(&n.children[0],1);
                let mut current=n;
                let mut rest=Vec::new();
                loop{
                    rest.push(self.operator_line());
                    rest.push(self.token(current.tokens[0]));
                    rest.push(self.space());
                    rest.push(self.expression(&current.children[1],0));
                    rest.push(self.operator_line());
                    rest.push(self.token(current.tokens[1]));
                    rest.push(self.space());
                    let next=self.open(&current.children[2],0);
                    if next.kind=="conditional"{
                        rest.push(self.expression(&next.children[0],1));
                        current=next;
                    }else{
                        rest.push(self.expression(&next,0));
                        break;
                    }
                }
                let d=concat(vec![head,nest(self.profile.number("indent"),concat(rest))]);
                self.group(d)
            },"call"|"index"|"member"=>{
                let mut current=n;
                let mut operations=Vec::new();
                while ["call","index","member"].contains(&current.kind.as_str()){
                    let target=current.children[0].clone();
                    operations.push(current);
                    current=self.open(&target,8);
                }
                operations.reverse();
                let mut segments:Vec<Vec<Node>>=vec![Vec::new()];
                for operation in operations{
                    if operation.kind=="member"{
                        segments.push(Vec::new());
                    }
                    segments.last_mut().unwrap().push(operation);
                }
                let calls:Vec<_>=segments.iter().enumerate().skip(1).filter(|(_,s)|s.iter().any(|n|n.kind=="call")).map(|(i,_)|i).collect();
                let mut parts=vec![self.expression(&current,8)];
                if calls.len()<2{
                    for operation in segments.iter().flat_map(|s|s.iter()){
                        parts.push(self.postfix(operation));
                    }
                    concat(parts)
                }else{
                    let first=calls[0];
                    for operation in segments[..first].iter().flat_map(|s|s.iter()){
                        parts.push(self.postfix(operation));
                    }
                    let mut rest=Vec::new();
                    for segment in &segments[first..]{
                        rest.push(softline());
                        for operation in segment{
                            rest.push(self.postfix(operation));
                        }
                    }
                    parts.push(nest(self.profile.number("indent"),concat(rest)));
                    let d=concat(parts);
                    self.group(d)
                }
            },_=>unreachable!()
        }
    }
}
struct Formatted{
    lines:Vec<String>,
    first_function:Option<(String,Document)>,
    modes:BTreeMap<usize,&'static str>,
    comments:usize
}
fn format(lines:&[String],profile:&Profile)->Result<Formatted,Error>{
    let lexed=lexer::lex(lines)?;
    let(tokens,comments)=attach(lexed);
    let items=parser::parse(&tokens)?;
    check_comments(&items,&tokens)?;
    let empty=items.is_empty()&&tokens.last().unwrap().leading.is_empty();
    let original_trailing=tokens.iter().map(|t|!t.trailing.is_empty()).collect();
    let mut builder=Construction{
        tokens,
        original_trailing,
        profile:profile.clone(),
        docs:Builder::new()
    };
    let mut parts=Vec::new();
    let mut first_function=None;
    for(i,n)in items.iter().enumerate(){
        if i>0{
            parts.push(builder.separator(builder.preblank(n.start)));
        }
        let d=if n.kind=="function"{
            builder.function(n)
        }else{
            builder.declaration(n)
        };
        if n.kind=="function"&&first_function.is_none(){
            first_function=Some((builder.tokens[n.tokens[1]].text.clone(),d.clone()));
        }
        parts.push(d);
    }
    let end=builder.tokens.len()-1;
    let closing=builder.tokens[end].leading.clone();
    if !closing.is_empty(){
        if !items.is_empty(){
            parts.push(builder.separator(closing[0].blank));
        }
        parts.push(builder.comments(&closing,None));
    }
    let document=concat(parts);
    if empty{
        return Ok(Formatted{
            lines:Vec::new(),
            first_function,
            modes:BTreeMap::new(),
            comments
        });
    }
    let printed=printer::print(document,profile.number("width"),profile.number("comment_column"));
    Ok(Formatted{
        lines:printed.lines,
        first_function,
        modes:printed.modes,
        comments
    })
}
struct Source{
    header:String,
    name:String,
    profile:String,
    lines:Vec<String>
}
fn inputs()->(BTreeMap<String,Profile>,Vec<Source>){
    let mut profiles:BTreeMap<String,Profile>=BTreeMap::new();
    let mut current=String::new();
    for line in fs::read_to_string("input/style.txt").unwrap().lines(){
        if line.is_empty(){
            continue;
        }
        if line.starts_with('['){
            current=line[1..line.len()-1].into();
            profiles.insert(current.clone(),Profile{
                values:BTreeMap::new()
            });
        }else{
            let(k,v)=line.split_once('=').unwrap();
            profiles.get_mut(&current).unwrap().values.insert(k.into(),v.into());
        }
    }
    let mut sources:Vec<Source>=Vec::new();
    for line in fs::read_to_string("input/sources.txt").unwrap().lines(){
        if line.starts_with("=== "){
            let a:Vec<_>=line.split(' ').collect();
            sources.push(Source{
                header:line.into(),
                name:a[1].into(),
                profile:a[2].into(),
                lines:Vec::new()
            });
        }else{
            sources.last_mut().unwrap().lines.push(line.into());
        }
    }
    (profiles,sources)
}
fn write(name:&str,lines:&[String]){
    fs::create_dir_all("output").unwrap();
    fs::write(format!("output/{}",name),if lines.is_empty(){
        String::new()
    }else{
        lines.join("\n")+"\n"
    }).unwrap();
}
fn main(){
    let(profiles,sources)=inputs();
    let(mut formatted,mut idempotency,mut diagnostics,mut doc_tree,mut changes)=(Vec::new(),Vec::new(),Vec::new(),Vec::new(),Vec::new());
    for source in sources{
        let profile=&profiles[&source.profile];
        formatted.push(source.header);
        doc_tree.push(format!("=== {}",source.name));
        changes.push(format!("=== {}",source.name));
        let original:Vec<_>=source.lines.iter().map(|line|line.trim_end().to_string()).collect();
        match format(&source.lines,profile){
            Err(error)=>{
                formatted.extend(original);
                idempotency.push(format!("{}: skipped (syntax error)",source.name));
                diagnostics.push(format!("{}:{}:{}: error: {}",source.name,error.line,error.column,error.message));
                doc_tree.push("syntax error".into());
                changes.push("skipped (syntax error)".into());
            },Ok(first)=>{
                formatted.extend(first.lines.clone());
                match format(&first.lines,profile){
                    Err(error)=>idempotency.push(format!("{}: unstable (second pass: {}:{}: {})",source.name,error.line,error.column,error.message)),Ok(second)=>if first.lines==second.lines{
                        idempotency.push(format!("{}: stable",source.name));
                    }else{
                        let index=first.lines.iter().zip(&second.lines).position(|(a,b)|a!=b).unwrap_or(first.lines.len().min(second.lines.len()))+1;
                        idempotency.push(format!("{}: unstable at line {}",source.name,index));
                    }
                }
                let width=profile.number("width");
                for(i,line)in first.lines.iter().enumerate(){
                    if line.len()>width{
                        diagnostics.push(format!("{}:{}: warning: line too long ({} > {})",source.name,i+1,line.len(),width));
                    }
                }
                let longest=first.lines.iter().map(String::len).max().unwrap_or(0);
                let broken=first.modes.values().filter(|&&mode|mode!="flat").count();
                let forced=first.modes.values().filter(|&&mode|mode=="forced").count();
                doc_tree.push(format!("metrics lines={} longest={} comments={} groups={} broken={} forced={}",first.lines.len(),longest,first.comments,first.modes.len(),broken,forced));
                if let Some((name,d))=&first.first_function{
                    doc_tree.push(format!("function {}",name));
                    report::tree(d,0,&first.modes,&mut doc_tree);
                }else{
                    doc_tree.push("no function".into());
                }
                changes.extend(report::diff(&original,&first.lines));
            }
        }
    }
    if diagnostics.is_empty(){
        diagnostics.push("no diagnostics".into());
    }
    write("formatted.txt",&formatted);
    write("idempotency.txt",&idempotency);
    write("diagnostics.txt",&diagnostics);
    write("doc_tree.txt",&doc_tree);
    write("changes.txt",&changes);
}
