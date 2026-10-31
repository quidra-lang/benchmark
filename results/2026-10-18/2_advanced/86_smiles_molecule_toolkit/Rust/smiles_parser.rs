use std::collections::BTreeMap;
use crate::molecule::{Atom,Bond,Molecule,Elements,Error};
use crate::search::{Matcher,pattern_atom};
pub struct Parsed{
    pub molecule:Molecule,
    pub matchers:Vec<Matcher>
}
pub fn organic(text:&[u8])->Option<(String,bool,usize)>{
    if text.starts_with(b"Cl"){
        return Some(("Cl".into(),false,2));
    }
    if text.starts_with(b"Br"){
        return Some(("Br".into(),false,2));
    }
    let c=*text.first()?;
    if b"BCNOPSFI".contains(&c){
        Some(((c as char).to_string(),false,1))
    }else if b"bcnops".contains(&c){
        Some(((c as char).to_ascii_uppercase().to_string(),true,1))
    }else{
        None
    }
}
fn atom(text:&[u8],column:usize,elements:&Elements)->Result<(Atom,usize),Error>{
    if text[0]!=b'['{
        let(element,aromatic,n)=organic(text).ok_or_else(||Error::new("unexpected character",column))?;
        return Ok((Atom{
            element,
            aromatic,
            mass:0,
            charge:0,
            hydrogens:0,
            bracket:false,
            column
        },n));
    }
    let end=text.iter().position(|&c|c==b']').ok_or_else(||Error::new("unclosed bracket",column))?;
    let s=&text[1..end];
    let mut i=0;
    while i<s.len()&&s[i].is_ascii_digit(){
        i+=1;
    }
    if i>=4||i>0&&s[0]==b'0'{
        return Err(Error::new("bad bracket atom",column));
    }
    let mass=if i==0{
        0
    }else{
        std::str::from_utf8(&s[..i]).unwrap().parse().unwrap()
    };
    let(element,aromatic)=if i==s.len(){
        return Err(Error::new("bad bracket atom",column));
    }else if b"bcnops".contains(&s[i]){
        let e=(s[i]as char).to_ascii_uppercase().to_string();
        i+=1;
        (e,true)
    }else if s[i].is_ascii_uppercase(){
        let one=(s[i]as char).to_string();
        if i+1<s.len()&&s[i+1].is_ascii_lowercase(){
            let two=std::str::from_utf8(&s[i..i+2]).unwrap();
            if elements.contains_key(two){
                i+=2;
                (two.to_string(),false)
            }else if elements.contains_key(&one){
                i+=1;
                (one,false)
            }else{
                return Err(Error::new("unknown element",column));
            }
        }else if elements.contains_key(&one){
            i+=1;
            (one,false)
        }else{
            return Err(Error::new("unknown element",column));
        }
    }else{
        return Err(Error::new("bad bracket atom",column));
    };
    if i<s.len()&&s[i]==b'@'{
        i+=1;
        if i<s.len()&&s[i]==b'@'{
            i+=1;
        }
    }
    let mut hydrogens=0;
    if i<s.len()&&s[i]==b'H'{
        hydrogens=1;
        i+=1;
        if i<s.len()&&s[i].is_ascii_digit(){
            hydrogens=(s[i]-b'0')as usize;
            i+=1;
        }
    }
    let mut charge=0;
    if i<s.len()&&(s[i]==b'+'||s[i]==b'-'){
        let sign=if s[i]==b'+'{
            1
        }else{
            -1
        };
        i+=1;
        let amount=if i<s.len()&&(b'1'..=b'9').contains(&s[i]){
            let n=(s[i]-b'0')as i32;
            i+=1;
            n
        }else{
            1
        };
        charge=sign*amount;
    }
    if i!=s.len(){
        return Err(Error::new("bad bracket atom",column));
    }
    Ok((Atom{
        element,
        aromatic,
        mass,
        charge,
        hydrogens,
        bracket:true,
        column
    },end+1))
}
fn symbol(c:u8,pattern:bool)->Option<u8>{
    match c{
        b'-'=>Some(1),b'='=>Some(2),b'#'=>Some(3),b':'=>Some(4),b'~'if pattern=>Some(5),b'/'|b'\\'if !pattern=>Some(1),_=>None
    }
}
fn add(m:&mut Molecule,a:usize,b:usize,kind:u8){
    m.bonds.push(Bond{
        a:a.min(b),
        b:a.max(b),
        kind,
        multiplicity:0,
        ring:false
    });
}
pub fn parse(text:&str,elements:&Elements,pattern:bool)->Result<Parsed,Error>{
    let s=text.as_bytes();
    let mut m=Molecule::default();
    let mut matchers=Vec::new();
    let mut current=None;
    let mut pending=None;
    let mut branches=Vec::new();
    let mut rings:BTreeMap<usize,(usize,Option<(u8,usize)>,usize)>=BTreeMap::new();
    let mut i=0;
    while i<s.len(){
        let c=s[i];
        let column=i+1;
        if let Some(kind)=symbol(c,pattern){
            if current.is_none()||pending.is_some(){
                return Err(Error::new("misplaced bond",column));
            }
            pending=Some((kind,column));
            i+=1;
        }else if c==b'('{
            if current.is_none()||pending.is_some()||i>0&&s[i-1]==b'('{
                return Err(Error::new("misplaced branch",column));
            }
            branches.push((current.unwrap(),column));
            i+=1;
        }else if c==b')'{
            if branches.is_empty(){
                return Err(Error::new("unmatched parenthesis",column));
            }
            if let Some((_,col))=pending{
                return Err(Error::new("dangling bond",col));
            }
            if i>0&&s[i-1]==b'('{
                return Err(Error::new("empty branch",column));
            }
            current=Some(branches.pop().unwrap().0);
            i+=1;
        }else if c.is_ascii_digit()||c==b'%'{
            let a=current.ok_or_else(||Error::new("misplaced ring closure",column))?;
            let number;
            if c==b'%'{
                if i+2>=s.len()||!s[i+1].is_ascii_digit()||!s[i+2].is_ascii_digit(){
                    return Err(Error::new("bad ring number",column));
                }
                number=((s[i+1]-b'0')as usize)*10+(s[i+2]-b'0')as usize;
                i+=3;
            }else{
                number=(c-b'0')as usize;
                i+=1;
            }
            let closing=pending.take();
            if let Some((opening,kind,_))=rings.remove(&number){
                if opening==a{
                    return Err(Error::new("self bond",column));
                }
                if let(Some((x,_)),Some((y,_)))=(kind,closing){
                    if x!=y{
                        return Err(Error::new("ring bond mismatch",column));
                    }
                }
                if m.bonds.iter().any(|b|b.a==opening.min(a)&&b.b==opening.max(a)){
                    return Err(Error::new("duplicate bond",column));
                }
                add(&mut m,opening,a,closing.or(kind).map_or(0,|v|v.0));
            }else{
                rings.insert(number,(a,closing,column));
            }
        }else{
            let(atom,n)=if pattern{
                let(matcher,n)=pattern_atom(&s[i..],column)?;
                matchers.push(matcher);
                (Atom{
                    element:String::new(),
                    aromatic:false,
                    mass:0,
                    charge:0,
                    hydrogens:0,
                    bracket:false,
                    column
                },n)
            }else{
                atom(&s[i..],column,elements)?
            };
            let next=m.atoms.len();
            m.atoms.push(atom);
            if let Some(a)=current{
                add(&mut m,a,next,pending.map_or(0,|v|v.0));
            }
            current=Some(next);
            pending=None;
            i+=n;
        }
    }
    if let Some((_,column))=pending{
        return Err(Error::new("dangling bond",column));
    }
    if let Some(&(_,column))=branches.first(){
        return Err(Error::new("unmatched parenthesis",column));
    }
    if let Some(column)=rings.values().map(|v|v.2).min(){
        return Err(Error::new("unclosed ring",column));
    }
    m.rebuild();
    Ok(Parsed{
        molecule:m,
        matchers
    })
}
