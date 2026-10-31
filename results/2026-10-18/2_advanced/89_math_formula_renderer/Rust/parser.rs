use crate::lexer::{Token,Error};
#[derive(Clone)] pub enum Node{
    Atom{
        kind:String,
        value:String,
        column:usize
    },
    Row(Vec<Node>),
    Binary(String,Box<Node>,Box<Node>),
    Root(Option<Box<Node>>,Box<Node>),
    Script(Box<Node>,Option<Box<Node>>,Option<Box<Node>>),
    Delimited(String,String,Box<Node>,usize),
    Matrix(String,Vec<Vec<Node>>),
    Accent(String,Box<Node>)
}
impl Node{
    pub fn empty()->Self{
        Self::Row(Vec::new())
    }
    pub fn is_empty(&self)->bool{
        matches!(self,Self::Row(v)if v.is_empty())
    }
}
fn collapse(mut nodes:Vec<Node>)->Node{
    if nodes.len()==1{
        nodes.remove(0)
    }else{
        Node::Row(nodes)
    }
}
pub struct Formula{
    pub elements:Vec<Node>,
    pub tag:Option<(String,usize)>,
    pub label:Option<(String,usize)>
}
struct Parser{
    tokens:Vec<Token>,
    index:usize,
    eof:Token,
    tag:Option<(String,usize)>,
    label:Option<(String,usize)>
}
impl Parser{
    fn peek(&self)->&Token{
        self.tokens.get(self.index).unwrap_or(&self.eof)
    }
    fn take(&mut self)->Token{
        let t=self.peek().clone();
        if self.index<self.tokens.len(){
            self.index+=1;
        }
        t
    }
    fn unexpected(&self)->Error{
        let t=self.peek();
        let message=match t.kind.as_str(){
            "right"=>"unexpected \\right","end"=>"unexpected \\end","&"=>"misplaced &","newline"=>"misplaced \\\\",_=>"unexpected end of input"
        };
        Error::new(t.column,message)
    }
    fn list(&mut self,top:bool,index:bool)->Result<Vec<Node>,Error>{
        let mut out=Vec::new();
        loop{
            let t=self.peek();
            if ["}","&","newline","right","end","eof"].contains(&t.kind.as_str())||index&&t.kind=="symbol"&&t.value=="]"{
                return Ok(out);
            }
            if t.kind=="tag"||t.kind=="label"{
                let t=t.clone();
                if !top{
                    return Err(Error::new(t.column,format!("misplaced \\{}",t.kind)));
                }
                let slot=if t.kind=="tag"{
                    &mut self.tag
                }else{
                    &mut self.label
                };
                if slot.is_some(){
                    return Err(Error::new(t.column,format!("duplicate \\{}",t.kind)));
                }
                *slot=Some((t.value,t.column));
                self.take();
                continue;
            }
            out.push(self.element()?);
        }
    }
    fn element(&mut self)->Result<Node,Error>{
        let base=if self.peek().kind=="^"||self.peek().kind=="_"{
            Node::empty()
        }else{
            self.nucleus()?
        };
        let(mut sub,mut sup)=(None,None);
        while self.peek().kind=="^"||self.peek().kind=="_"{
            let t=self.take();
            let slot=if t.kind=="^"{
                &mut sup
            }else{
                &mut sub
            };
            if slot.is_some(){
                return Err(Error::new(t.column,if t.kind=="^"{
                    "double superscript"
                }else{
                    "double subscript"
                }));
            }
            *slot=Some(Box::new(self.argument(&t.kind)?));
        }
        if sub.is_some()||sup.is_some(){
            Ok(Node::Script(Box::new(base),sub,sup))
        }else{
            Ok(base)
        }
    }
    fn argument(&mut self,name:&str)->Result<Node,Error>{
        if ["identifier","number","symbol","command","text","eqref","{","frac","binom","overset","underset","sqrt","accent"].contains(&self.peek().kind.as_str()){
            self.nucleus()
        }else{
            Err(Error::new(self.peek().column,format!("missing argument for {}",name)))
        }
    }
    fn delimiter(&mut self)->Result<String,Error>{
        let t=self.take();
        if t.kind=="symbol"&&["(",")","[","]","|","."].contains(&t.value.as_str())||t.kind=="command"&&["\\{","\\}"].contains(&t.value.as_str()){
            Ok(t.value)
        }else{
            Err(Error::new(t.column,"invalid delimiter"))
        }
    }
    fn nucleus(&mut self)->Result<Node,Error>{
        let t=self.take();
        match t.kind.as_str(){
            "identifier"|"number"|"symbol"|"command"|"text"|"eqref"=>Ok(Node::Atom{
                kind:t.kind,
                value:t.value,
                column:t.column
            }),"{"=>{
                let nodes=self.list(false,false)?;
                if self.peek().kind!="}"{
                    return Err(self.unexpected());
                }
                self.take();
                Ok(collapse(nodes))
            },"frac"|"binom"|"overset"|"underset"=>{
                let name=format!("\\{}",t.kind);
                let first=self.argument(&name)?;
                let second=self.argument(&name)?;
                Ok(Node::Binary(t.kind,Box::new(first),Box::new(second)))
            },"sqrt"=>{
                let index=if self.peek().kind=="symbol"&&self.peek().value=="["{
                    let c=self.take().column;
                    let nodes=self.list(false,true)?;
                    if self.peek().kind!="symbol"||self.peek().value!="]"{
                        return Err(Error::new(c,"missing ]"));
                    }
                    self.take();
                    Some(Box::new(collapse(nodes)))
                }else{
                    None
                };
                let body=self.argument("\\sqrt")?;
                Ok(Node::Root(index,Box::new(body)))
            },"accent"=>{
                let body=self.argument(&format!("\\{}",t.value))?;
                Ok(Node::Accent(t.value,Box::new(body)))
            },"left"=>{
                let left=self.delimiter()?;
                let nodes=self.list(false,false)?;
                if self.peek().kind!="right"{
                    return Err(Error::new(t.column,"missing \\right"));
                }
                let column=self.take().column;
                let right=self.delimiter()?;
                Ok(Node::Delimited(left,right,Box::new(collapse(nodes)),column))
            },"begin"=>{
                let mut rows=vec![Vec::new()];
                loop{
                    let nodes=self.list(false,false)?;
                    rows.last_mut().unwrap().push(collapse(nodes));
                    let end=self.take();
                    match end.kind.as_str(){
                        "&"=>(),"newline"=>rows.push(Vec::new()),"end"=>{
                            if end.value!=t.value{
                                return Err(Error::new(end.column,"mismatched \\end"));
                            }
                            break;
                        },_=>return Err(Error::new(t.column,"missing \\end"))
                    }
                }
                if rows.len()>1&&rows.last().unwrap().len()==1&&rows.last().unwrap()[0].is_empty(){
                    rows.pop();
                }
                let width=rows.iter().map(Vec::len).max().unwrap();
                for row in &mut rows{
                    row.resize(width,Node::empty());
                }
                Ok(Node::Matrix(t.value,rows))
            },_=>unreachable!()
        }
    }
}
pub fn parse(tokens:Vec<Token>,end:usize)->Result<Formula,Error>{
    let mut braces=Vec::new();
    for t in &tokens{
        if t.kind=="{"{
            braces.push(t.column);
        }else if t.kind=="}"&&braces.pop().is_none(){
            return Err(Error::new(t.column,"unmatched }"));
        }
    }
    if let Some(column)=braces.pop(){
        return Err(Error::new(column,"unclosed {"));
    }
    let mut p=Parser{
        tokens,
        index:0,
        eof:Token{
            kind:"eof".into(),
            value:String::new(),
            column:end
        },
        tag:None,
        label:None
    };
    let elements=p.list(true,false)?;
    if p.peek().kind!="eof"{
        return Err(p.unexpected());
    }
    Ok(Formula{
        elements,
        tag:p.tag,
        label:p.label
    })
}
