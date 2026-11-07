use std::rc::Rc;
pub type Document=Rc<Doc>;
pub enum Doc{
    Text(String),
    Line,
    Softline,
    Hardline,
    BreakParent,
    Suffix(String),
    IfBreak(String,String),
    Group(usize,Document),
    Nest(usize,Document),
    Align(Document),
    Concat(Vec<Document>)
}
pub fn text(s:impl Into<String>)->Document{
    Rc::new(Doc::Text(s.into()))
}
pub fn concat(parts:Vec<Document>)->Document{
    fn flatten(d:Document,out:&mut Vec<Document>){
        if let Doc::Concat(parts)=d.as_ref(){
            for part in parts{
                flatten(part.clone(),out);
            }
        }else if let Doc::Text(s)=d.as_ref(){
            if s.is_empty(){
                return;
            }
            if let Some(last)=out.last(){
                if let Doc::Text(previous)=last.as_ref(){
                    let joined=previous.clone()+s;
                    out.pop();
                    out.push(text(joined));
                    return;
                }
            }
            out.push(d);
        }else{
            out.push(d);
        }
    }
    let mut out=Vec::new();
    for p in parts{
        flatten(p,&mut out);
    }
    if out.is_empty(){
        text("")
    }else if out.len()==1{
        out.pop().unwrap()
    }else{
        Rc::new(Doc::Concat(out))
    }
}
pub fn nest(n:usize,d:Document)->Document{
    Rc::new(Doc::Nest(n,d))
}
pub fn align(d:Document)->Document{
    Rc::new(Doc::Align(d))
}
pub fn line()->Document{
    Rc::new(Doc::Line)
}
pub fn softline()->Document{
    Rc::new(Doc::Softline)
}
pub fn hardline()->Document{
    Rc::new(Doc::Hardline)
}
pub fn suffix(s:String)->Document{
    Rc::new(Doc::Suffix(s))
}
pub fn break_parent()->Document{
    Rc::new(Doc::BreakParent)
}
pub fn if_break(a:&str,b:&str)->Document{
    Rc::new(Doc::IfBreak(a.into(),b.into()))
}
pub struct Builder{
    next:usize
}
impl Builder{
    pub fn new()->Self{
        Self{
            next:0
        }
    }
    pub fn group(&mut self,d:Document)->Document{
        let id=self.next;
        self.next+=1;
        Rc::new(Doc::Group(id,d))
    }
}
pub fn forced(d:&Document)->bool{
    match d.as_ref(){
        Doc::Hardline|Doc::BreakParent=>true,Doc::Concat(v)=>v.iter().any(forced),Doc::Group(_,d)|Doc::Nest(_,d)|Doc::Align(d)=>forced(d),_=>false
    }
}
