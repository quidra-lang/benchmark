use std::collections::BTreeMap;
use std::fs;
#[derive(Clone)] pub enum Expr{
    Word(String),
    List(Vec<Expr>)
}
impl Expr{
    pub fn word(&self)->&str{
        if let Self::Word(w)=self{
            w
        }else{
            panic!()
        }
    }
    pub fn list(&self)->&[Expr]{
        if let Self::List(v)=self{
            v
        }else{
            panic!()
        }
    }
}
pub fn expressions(path:&str)->Vec<Expr>{
    let mut tokens=Vec::new();
    let text=fs::read_to_string(path).unwrap();
    for line in text.lines(){
        let mut word=String::new();
        for c in line.split(';').next().unwrap().chars(){
            if c=='('||c==')'||c==' '{
                if !word.is_empty(){
                    tokens.push(std::mem::take(&mut word));
                }
                if c=='('||c==')'{
                    tokens.push(c.to_string());
                }
            }else{
                word.push(c);
            }
        }
        if !word.is_empty(){
            tokens.push(word);
        }
    }
    fn read(tokens:&[String],i:&mut usize)->Expr{
        let t=&tokens[*i];
        *i+=1;
        if t=="("{
            let mut children=Vec::new();
            while tokens[*i]!=")"{
                children.push(read(tokens,i));
            }
            *i+=1;
            Expr::List(children)
        }else{
            Expr::Word(t.clone())
        }
    }
    let mut i=0;
    let mut out=Vec::new();
    while i<tokens.len(){
        out.push(read(&tokens,&mut i));
    }
    out
}
pub fn typed(words:&[Expr])->Vec<(String,String)>{
    let mut result=Vec::new();
    let mut pending=Vec::new();
    let mut i=0;
    while i<words.len(){
        if words[i].word()=="-"{
            i+=1;
            let t=words[i].word();
            for name in pending.drain(..){
                result.push((name,t.into()));
            }
        }else{
            pending.push(words[i].word().to_string());
        }
        i+=1;
    }
    result.extend(pending.into_iter().map(|n|(n,"object".into())));
    result
}
#[derive(Clone,Debug,PartialEq,Eq,PartialOrd,Ord)] pub struct Atom{
    pub predicate:String,
    pub terms:Vec<String>
}
impl Atom{
    pub fn read(e:&Expr)->Self{
        let a=e.list();
        Self{
            predicate:a[0].word().into(),
            terms:a[1..].iter().map(|e|e.word().to_string()).collect()
        }
    }
    pub fn text(&self)->String{
        if self.terms.is_empty(){
            format!("({})",self.predicate)
        }else{
            format!("({} {})",self.predicate,self.terms.join(" "))
        }
    }
    pub fn replace(&self,values:&BTreeMap<String,String>)->Self{
        Self{
            predicate:self.predicate.clone(),
            terms:self.terms.iter().map(|v|values[v].clone()).collect()
        }
    }
}
#[derive(Clone)] pub struct Literal{
    pub atom:Atom,
    pub negative:bool
}
impl Literal{
    pub fn text(&self)->String{
        if self.negative{
            format!("(not {})",self.atom.text())
        }else{
            self.atom.text()
        }
    }
    pub fn replace(&self,values:&BTreeMap<String,String>)->Self{
        Self{
            atom:self.atom.replace(values),
            negative:self.negative
        }
    }
}
fn literal(e:&Expr)->Literal{
    let a=e.list();
    if a[0].word()=="not"{
        Literal{
            atom:Atom::read(&a[1]),
            negative:true
        }
    }else{
        Literal{
            atom:Atom::read(e),
            negative:false
        }
    }
}
fn conjunction(e:&Expr)->Vec<Expr>{
    let a=e.list();
    if a[0].word()=="and"{
        a[1..].to_vec()
    }else{
        vec![e.clone()]
    }
}
#[derive(Clone)] pub struct Schema{
    pub name:String,
    pub parameters:Vec<(String,String)>,
    pub pre:Vec<Literal>,
    pub effects:Vec<Literal>,
    pub cost:i64
}
#[derive(Clone)] pub struct Predicate{
    pub name:String,
    pub types:Vec<String>
}
pub struct Domain{
    pub name:String,
    pub type_order:Vec<String>,
    pub parents:BTreeMap<String,String>,
    pub predicates:Vec<Predicate>,
    pub actions:Vec<Schema>,
    pub diagnostics:Vec<String>
}
pub fn domain()->Domain{
    let expressions=expressions("input/domain.txt");
    let a=expressions[0].list();
    let mut d=Domain{
        name:a[1].list()[1].word().into(),
        type_order:vec!["object".into()],
        parents:BTreeMap::new(),
        predicates:Vec::new(),
        actions:Vec::new(),
        diagnostics:Vec::new()
    };
    for e in &a[2..]{
        let s=e.list();
        match s[0].word(){
            ":types"=>{
                for word in &s[1..]{
                    let t=word.word();
                    if t!="-"&&!d.type_order.iter().any(|n|n==t){
                        d.type_order.push(t.into());
                        if t!="object"{
                            d.parents.insert(t.into(),"object".into());
                        }
                    }
                }
                for(n,t)in typed(&s[1..]){
                    d.parents.insert(n,t);
                }
            },":predicates"=>{
                for p in &s[1..]{
                    let p=p.list();
                    d.predicates.push(Predicate{
                        name:p[0].word().into(),
                        types:typed(&p[1..]).into_iter().map(|(_,t)|t).collect()
                    });
                }
            },":action"=>{
                let mut action=Schema{
                    name:s[1].word().into(),
                    parameters:Vec::new(),
                    pre:Vec::new(),
                    effects:Vec::new(),
                    cost:1
                };
                let mut i=2;
                while i<s.len(){
                    match s[i].word(){
                        ":parameters"=>action.parameters=typed(s[i+1].list()),":precondition"=>action.pre=conjunction(&s[i+1]).iter().map(literal).collect(),_=>{
                            for e in conjunction(&s[i+1]){
                                if e.list()[0].word()=="increase"{
                                    action.cost=e.list()[2].word().parse().unwrap();
                                }else{
                                    action.effects.push(literal(&e));
                                }
                            }
                        }
                    }
                    i+=2;
                }
                d.actions.push(action);
            },_=>()
        }
    }
    d
}
#[derive(Clone)] pub struct Problem{
    pub name:String,
    pub objects:Vec<(String,String)>,
    pub initial:Vec<Atom>,
    pub goals:Vec<Atom>,
    pub diagnostics:Vec<String>
}
pub fn problems()->Vec<Problem>{
    expressions("input/problems.txt").iter().map(|e|{
        let a=e.list();
        let mut p=Problem{
            name:a[1].list()[1].word().into(),
            objects:Vec::new(),
            initial:Vec::new(),
            goals:Vec::new(),
            diagnostics:Vec::new()
        };
        for section in &a[2..]{
            let s=section.list();
            match s[0].word(){
                ":objects"=>p.objects=typed(&s[1..]),":init"=>p.initial=s[1..].iter().map(Atom::read).collect(),":goal"=>p.goals=conjunction(&s[1]).iter().map(Atom::read).collect(),_=>()
            }
        }
        p
    }).collect()
}
