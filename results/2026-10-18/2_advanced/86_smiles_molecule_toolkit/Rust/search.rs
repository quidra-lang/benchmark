use std::collections::BTreeSet;
use crate::molecule::{Molecule,Error,Elements};
#[derive(Clone)] pub enum Matcher{
    Any,
    Aliphatic,
    Aromatic,
    List(Vec<(String,bool)>)
}
pub fn pattern_atom(s:&[u8],column:usize)->Result<(Matcher,usize),Error>{
    match s[0]{
        b'*'=>Ok((Matcher::Any,1)),b'A'=>Ok((Matcher::Aliphatic,1)),b'a'=>Ok((Matcher::Aromatic,1)),b'['=>{
            let end=s.iter().position(|&c|c==b']').ok_or_else(||Error::new("unclosed bracket",column))?;
            let mut list=Vec::new();
            for part in s[1..end].split(|&c|c==b','){
                let(element,aromatic,n)=crate::smiles_parser::organic(part).ok_or_else(||Error::new("bad bracket atom",column))?;
                if n!=part.len(){
                    return Err(Error::new("bad bracket atom",column));
                }
                list.push((element,aromatic));
            }
            Ok((Matcher::List(list),end+1))
        },_=>{
            let(e,a,n)=crate::smiles_parser::organic(s).ok_or_else(||Error::new("unexpected character",column))?;
            Ok((Matcher::List(vec![(e,a)]),n))
        }
    }
}
pub struct Pattern{
    pub graph:Molecule,
    pub atoms:Vec<Matcher>
}
impl Pattern{
    pub fn parse(s:&str,e:&Elements)->Result<Self,Error>{
        let p=crate::smiles_parser::parse(s,e,true)?;
        Ok(Self{
            graph:p.molecule,
            atoms:p.matchers
        })
    }
    pub fn molecule(m:&Molecule)->Self{
        Self{
            graph:m.clone(),
            atoms:m.atoms.iter().map(|a|Matcher::List(vec![(a.element.clone(),a.aromatic)])).collect()
        }
    }
}
pub struct Matches{
    pub count:usize,
    pub unique:usize,
    pub first:Vec<usize>
}
pub fn embeddings(pattern:&Pattern,m:&Molecule)->Matches{
    fn visit(p:&Pattern,m:&Molecule,map:&mut Vec<usize>,used:&mut BTreeSet<usize>,count:&mut usize,sets:&mut BTreeSet<Vec<usize>>,first:&mut Vec<usize>){
        let a=map.len();
        if a==p.atoms.len(){
            *count+=1;
            if first.is_empty(){
                *first=map.iter().map(|v|v+1).collect();
            }
            let mut set=map.clone();
            set.sort();
            sets.insert(set);
            return;
        }
        for b in 0..m.atoms.len(){
            if used.contains(&b){
                continue;
            }
            let atom=&m.atoms[b];
            let matches=match &p.atoms[a]{
                Matcher::Any=>true,Matcher::Aliphatic=>!atom.aromatic,Matcher::Aromatic=>atom.aromatic,Matcher::List(list)=>list.iter().any(|(e,r)|*e==atom.element&&*r==atom.aromatic)
            };
            if !matches{
                continue;
            }
            let bonds=p.graph.neighbors[a].iter().filter(|&&(v,_)|v<a).all(|&(v,e)|m.bond(b,map[v]).map_or(false,|f|match p.graph.bonds[e].kind{
                0=>m.bonds[f].kind==1||m.bonds[f].kind==4,5=>true,k=>m.bonds[f].kind==k
            }));
            if bonds{
                used.insert(b);
                map.push(b);
                visit(p,m,map,used,count,sets,first);
                map.pop();
                used.remove(&b);
            }
        }
    }
    let(mut count,mut first,mut sets)=(0,Vec::new(),BTreeSet::new());
    visit(pattern,m,&mut Vec::new(),&mut BTreeSet::new(),&mut count,&mut sets,&mut first);
    Matches{
        count,
        unique:sets.len(),
        first
    }
}
pub struct Fingerprint{
    pub bits:BTreeSet<usize>,
    pub paths:usize
}
pub fn fingerprint(m:&Molecule,e:&Elements)->Fingerprint{
    fn walk(m:&Molecule,codes:&[usize],path:&mut Vec<usize>,hash:usize,result:&mut Fingerprint){
        result.paths+=1;
        result.bits.insert(hash%1024);
        if path.len()==6{
            return;
        }
        let a=*path.last().unwrap();
        for &(b,e)in &m.neighbors[a]{
            if !path.contains(&b){
                let h=((hash*31+m.bonds[e].kind as usize)%1000003*31+codes[b])%1000003;
                path.push(b);
                walk(m,codes,path,h,result);
                path.pop();
            }
        }
    }
    let codes:Vec<_>=m.atoms.iter().enumerate().map(|(i,a)|16*e[&a.element].number as usize+8*usize::from(a.aromatic)+m.neighbors[i].len()).collect();
    let mut result=Fingerprint{
        bits:BTreeSet::new(),
        paths:0
    };
    for i in 0..m.atoms.len(){
        walk(m,&codes,&mut vec![i],codes[i],&mut result);
    }
    result
}
pub fn similarity(a:&Fingerprint,b:&Fingerprint)->(usize,usize){
    let common=a.bits.intersection(&b.bits).count();
    (common,a.bits.len()+b.bits.len()-common)
}
