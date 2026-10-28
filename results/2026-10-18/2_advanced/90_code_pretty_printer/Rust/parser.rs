use crate::lexer::{Token,Error};
#[derive(Clone)] pub struct Node{
    pub kind:String,
    pub tokens:Vec<usize>,
    pub children:Vec<Node>,
    pub start:usize,
    pub end:usize,
    pub trailing:Option<usize>
}
impl Node{
    fn new(kind:&str,tokens:Vec<usize>,children:Vec<Node>,start:usize,end:usize)->Self{
        Self{
            kind:kind.into(),
            tokens,
            children,
            start,
            end,
            trailing:None
        }
    }
}
pub fn is_type(s:&str)->bool{
    ["int","float","bool","string","void"].contains(&s)
}
pub fn precedence(s:&str)->usize{
    match s{
        "||"=>1,"&&"=>2,"=="|"!="=>3,"<"|"<="|">"|">="=>4,"+"|"-"=>5,"*"|"/"|"%"=>6,_=>0
    }
}
struct Parser<'a>{
    tokens:&'a[Token],
    i:usize
}
impl<'a> Parser<'a>{
    fn peek(&self)->&Token{
        &self.tokens[self.i]
    }
    fn text(&self)->&str{
        &self.peek().text
    }
    fn take(&mut self)->usize{
        let i=self.i;
        self.i+=1;
        i
    }
    fn error(&self,expected:&str)->Error{
        let t=self.peek();
        Error{
            line:t.line,
            column:t.column,
            message:format!("expected {}, found {}",expected,if t.kind=="end"{
                "end of file".into()
            }else{
                format!("'{}'",t.text)
            })
        }
    }
    fn symbol(&mut self,s:&str)->Result<usize,Error>{
        if self.text()==s{
            Ok(self.take())
        }else{
            Err(self.error(&format!("'{}'",s)))
        }
    }
    fn identifier(&mut self)->Result<usize,Error>{
        if self.peek().kind=="identifier"{
            Ok(self.take())
        }else{
            Err(self.error("identifier"))
        }
    }
    fn ty(&mut self)->Result<usize,Error>{
        if is_type(self.text()){
            Ok(self.take())
        }else{
            Err(self.error("type"))
        }
    }
    fn node(&self,kind:&str,tokens:Vec<usize>,children:Vec<Node>,start:usize)->Node{
        Node::new(kind,tokens,children,start,self.i.saturating_sub(1))
    }
    fn empty(&self)->Node{
        Node::new("empty",Vec::new(),Vec::new(),self.i,self.i)
    }
    fn list(&mut self,kind:&str,open:&str,close:&str,trailing:bool)->Result<Node,Error>{
        let start=self.i;
        let mut tokens=vec![self.symbol(open)?];
        let mut children=Vec::new();
        let mut tail=None;
        if self.text()!=close{
            children.push(self.list_element(kind)?);
            while self.text()==","{
                let comma=self.take();
                if trailing&&self.tokens[self.i].text==close{
                    tail=Some(comma);
                    break;
                }
                tokens.push(comma);
                children.push(self.list_element(kind)?);
            }
        }
        tokens.push(self.symbol(close)?);
        let mut n=self.node(kind,tokens,children,start);
        n.trailing=tail;
        Ok(n)
    }
    fn list_element(&mut self,kind:&str)->Result<Node,Error>{
        if kind=="params"{
            let start=self.i;
            let tokens=vec![self.ty()?,self.identifier()?];
            let mut children=Vec::new();
            while self.text()=="["{
                let s=self.i;
                let tokens=vec![self.take(),self.symbol("]")?];
                children.push(self.node("dimension",tokens,Vec::new(),s));
            }
            Ok(self.node("parameter",tokens,children,start))
        }else if kind=="initlist"{
            self.initializer()
        }else{
            self.expression()
        }
    }
    fn initializer(&mut self)->Result<Node,Error>{
        if self.text()=="{"{
            self.list("initlist","{","}",true)
        }else{
            self.expression()
        }
    }
    fn declaration(&mut self,semicolon:bool)->Result<Node,Error>{
        let start=self.i;
        let tokens=vec![self.ty()?,self.identifier()?];
        self.declaration_rest(start,tokens,semicolon)
    }
    fn declaration_rest(&mut self,start:usize,mut tokens:Vec<usize>,semicolon:bool)->Result<Node,Error>{
        let mut children=Vec::new();
        while self.text()=="["{
            let s=self.i;
            let open=self.take();
            let mut c=Vec::new();
            if self.text()!="]"{
                c.push(self.expression()?);
            }
            let close=self.symbol("]")?;
            children.push(self.node("dimension",vec![open,close],c,s));
        }
        if self.text()=="="{
            tokens.push(self.take());
            children.push(self.initializer()?);
        }
        if semicolon{
            tokens.push(self.symbol(";")?);
        }
        Ok(self.node("decl",tokens,children,start))
    }
    fn item(&mut self)->Result<Node,Error>{
        let start=self.i;
        let tokens=vec![self.ty()?,self.identifier()?];
        if self.text()=="("{
            let parameters=self.list("params","(",")",false)?;
            let block=self.block()?;
            Ok(self.node("function",tokens,vec![parameters,block],start))
        }else{
            self.declaration_rest(start,tokens,true)
        }
    }
    fn block(&mut self)->Result<Node,Error>{
        let start=self.i;
        let open=self.symbol("{")?;
        let mut statements=Vec::new();
        while self.text()!="}"&&self.peek().kind!="end"{
            statements.push(self.statement()?);
        }
        let close=self.symbol("}")?;
        Ok(self.node("block",vec![open,close],statements,start))
    }
    fn statement(&mut self)->Result<Node,Error>{
        let start=self.i;
        if self.text()=="{"{
            return self.block();
        }
        if is_type(self.text()){
            return self.declaration(true);
        }
        match self.text(){
            "if"=>{
                let keyword=self.take();
                let open=self.symbol("(")?;
                let condition=self.expression()?;
                let close=self.symbol(")")?;
                let body=self.statement()?;
                let mut tokens=vec![keyword,open,close];
                let mut children=vec![condition,body];
                if self.text()=="else"{
                    tokens.push(self.take());
                    children.push(self.statement()?);
                }
                Ok(self.node("if",tokens,children,start))
            },"while"=>{
                let keyword=self.take();
                let open=self.symbol("(")?;
                let condition=self.expression()?;
                let close=self.symbol(")")?;
                let body=self.statement()?;
                Ok(self.node("while",vec![keyword,open,close],vec![condition,body],start))
            },"for"=>{
                let keyword=self.take();
                let open=self.symbol("(")?;
                let init=if self.text()==";"{
                    self.empty()
                }else if is_type(self.text()){
                    self.declaration(false)?
                }else{
                    self.simple()?
                };
                let first=self.symbol(";")?;
                let condition=if self.text()==";"{
                    self.empty()
                }else{
                    self.expression()?
                };
                let second=self.symbol(";")?;
                let update=if self.text()==")"{
                    self.empty()
                }else{
                    self.simple()?
                };
                let close=self.symbol(")")?;
                let body=self.statement()?;
                Ok(self.node("for",vec![keyword,open,first,second,close],vec![init,condition,update,body],start))
            },"switch"=>{
                let keyword=self.take();
                let open=self.symbol("(")?;
                let condition=self.expression()?;
                let close=self.symbol(")")?;
                let left=self.symbol("{")?;
                let mut children=vec![condition];
                while self.text()=="case"||self.text()=="default"{
                    let s=self.i;
                    let label=self.take();
                    let mut body=Vec::new();
                    let kind=if self.tokens[label].text=="case"{
                        body.push(self.expression()?);
                        "case"
                    }else{
                        "default"
                    };
                    let colon=self.symbol(":")?;
                    while !["case","default","}"].contains(&self.text())&&self.peek().kind!="end"{
                        body.push(self.statement()?);
                    }
                    children.push(self.node(kind,vec![label,colon],body,s));
                }
                let right=self.symbol("}")?;
                Ok(self.node("switch",vec![keyword,open,close,left,right],children,start))
            },"return"=>{
                let keyword=self.take();
                let mut children=Vec::new();
                if self.text()!=";"{
                    children.push(self.expression()?);
                }
                let semi=self.symbol(";")?;
                Ok(self.node("return",vec![keyword,semi],children,start))
            },"break"|"continue"=>{
                let keyword=self.take();
                let kind=self.tokens[keyword].text.clone();
                let semi=self.symbol(";")?;
                Ok(self.node(&kind,vec![keyword,semi],Vec::new(),start))
            },_=>{
                let simple=self.simple()?;
                let semi=self.symbol(";")?;
                Ok(self.node("statement",vec![semi],vec![simple],start))
            }
        }
    }
    fn simple(&mut self)->Result<Node,Error>{
        let start=self.i;
        let left=self.expression()?;
        if ["=","+=","-=","*=","/=","%="].contains(&self.text()){
            let op=self.take();
            let right=self.expression()?;
            Ok(self.node("assign",vec![op],vec![left,right],start))
        }else{
            Ok(self.node("exprstmt",Vec::new(),vec![left],start))
        }
    }
    fn expression(&mut self)->Result<Node,Error>{
        let start=self.i;
        let condition=self.binary(1)?;
        if self.text()=="?"{
            let question=self.take();
            let yes=self.expression()?;
            let colon=self.symbol(":")?;
            let no=self.expression()?;
            Ok(self.node("conditional",vec![question,colon],vec![condition,yes,no],start))
        }else{
            Ok(condition)
        }
    }
    fn binary(&mut self,p:usize)->Result<Node,Error>{
        let start=self.i;
        let mut left=if p==6{
            self.unary()?
        }else{
            self.binary(p+1)?
        };
        while precedence(self.text())==p{
            let op=self.take();
            let right=if p==6{
                self.unary()?
            }else{
                self.binary(p+1)?
            };
            left=self.node("binary",vec![op],vec![left,right],start);
        }
        Ok(left)
    }
    fn unary(&mut self)->Result<Node,Error>{
        let start=self.i;
        if self.text()=="-"||self.text()=="!"{
            let op=self.take();
            let child=self.unary()?;
            return Ok(self.node("unary",vec![op],vec![child],start));
        }
        let mut target=self.primary()?;
        loop{
            target=match self.text(){
                "("=>{
                    let list=self.list("args","(",")",false)?;
                    self.node("call",Vec::new(),vec![target,list],start)
                },"["=>{
                    let open=self.take();
                    let index=self.expression()?;
                    let close=self.symbol("]")?;
                    self.node("index",vec![open,close],vec![target,index],start)
                },"."=>{
                    let dot=self.take();
                    let name=self.identifier()?;
                    self.node("member",vec![dot,name],vec![target],start)
                },_=>return Ok(target)
            }
        }
    }
    fn primary(&mut self)->Result<Node,Error>{
        let start=self.i;
        if ["identifier","number","string"].contains(&self.peek().kind.as_str())||self.text()=="true"||self.text()=="false"{
            let t=self.take();
            Ok(self.node("atom",vec![t],Vec::new(),start))
        }else if self.text()=="("{
            let open=self.take();
            let child=self.expression()?;
            let close=self.symbol(")")?;
            Ok(self.node("paren",vec![open,close],vec![child],start))
        }else{
            Err(self.error("expression"))
        }
    }
}
pub fn parse(tokens:&[Token])->Result<Vec<Node>,Error>{
    let mut p=Parser{
        tokens,
        i:0
    };
    let mut items=Vec::new();
    while p.peek().kind!="end"{
        items.push(p.item()?);
    }
    Ok(items)
}
