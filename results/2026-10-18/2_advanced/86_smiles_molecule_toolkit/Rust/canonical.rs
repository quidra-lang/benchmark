use std::collections::{BTreeMap,BTreeSet};
use crate::molecule::{Molecule,Elements};
fn dense<T:Ord+Clone>(values:&[T])->Vec<usize>{
    let sorted:Vec<_>=values.iter().cloned().collect::<BTreeSet<_>>().into_iter().collect();
    values.iter().map(|v|sorted.binary_search(v).unwrap()+1).collect()
}
fn refine(m:&Molecule,mut ranks:Vec<usize>)->Vec<usize>{
    loop{
        let classes=ranks.iter().copied().collect::<BTreeSet<_>>().len();
        let values:Vec<_>=(0..m.atoms.len()).map(|i|{
            let mut neighbors:Vec<_>=m.neighbors[i].iter().map(|&(j,e)|(ranks[j],m.bonds[e].kind)).collect();
            neighbors.sort();
            (ranks[i],neighbors)
        }).collect();
        ranks=dense(&values);
        if ranks.iter().copied().collect::<BTreeSet<_>>().len()==classes{
            return ranks;
        }
    }
}
pub fn ranks(m:&Molecule,elements:&Elements)->(Vec<usize>,usize){
    let values:Vec<_>=m.atoms.iter().enumerate().map(|(i,a)|vec![m.neighbors[i].len()as i32,elements[&a.element].number,a.mass,a.charge,a.hydrogens as i32,i32::from(a.aromatic)]).collect();
    let mut ranks=refine(m,dense(&values));
    let classes=ranks.iter().copied().collect::<BTreeSet<_>>().len();
    while ranks.iter().copied().collect::<BTreeSet<_>>().len()<m.atoms.len(){
        let mut counts=BTreeMap::new();
        for &r in &ranks{
            *counts.entry(r).or_insert(0usize)+=1;
        }
        let tied=*counts.iter().find(|(_,n)|**n>1).unwrap().0;
        let a=ranks.iter().position(|&r|r==tied).unwrap();
        let mut values:Vec<_>=ranks.iter().map(|r|2*r).collect();
        values[a]-=1;
        ranks=refine(m,dense(&values));
    }
    (ranks,classes)
}
fn atom(m:&Molecule,i:usize,e:&Elements)->String{
    let a=&m.atoms[i];
    let symbol=if a.aromatic{
        a.element.to_ascii_lowercase()
    }else{
        a.element.clone()
    };
    let allowed=["B","C","N","O","P","S","F","Cl","Br","I"].contains(&a.element.as_str())&&(!a.aromatic||["B","C","N","O","P","S"].contains(&a.element.as_str()));
    let simple=allowed&&a.mass==0&&a.charge==0&&(!a.aromatic||m.needs_pi(i,e,true)==m.needs_pi(i,e,false))&&m.organic_hydrogens(i,e)==Some(a.hydrogens);
    if simple{
        return symbol;
    }
    let mut s=String::from("[");
    if a.mass!=0{
        s.push_str(&a.mass.to_string());
    }
    s.push_str(&symbol);
    if a.hydrogens>0{
        s.push('H');
        if a.hydrogens>1{
            s.push_str(&a.hydrogens.to_string());
        }
    }
    if a.charge!=0{
        s.push(if a.charge>0{
            '+'
        }else{
            '-'
        });
        if a.charge.abs()>1{
            s.push_str(&a.charge.abs().to_string());
        }
    }
    s.push(']');
    s
}
fn bond(m:&Molecule,e:usize)->&'static str{
    let b=&m.bonds[e];
    let aromatic=m.atoms[b.a].aromatic&&m.atoms[b.b].aromatic&&b.ring;
    match b.kind{
        1=>if aromatic{
            "-"
        }else{
            ""
        },2=>"=",3=>"#",_=>if aromatic{
            ""
        }else{
            ":"
        }
    }
}
pub fn smiles(m:&Molecule,elements:&Elements)->(String,usize){
    fn visit(m:&Molecule,a:usize,incoming:Option<usize>,ranks:&[usize],visited:&mut[usize],kind:&mut[u8],children:&mut[Vec<(usize,usize)>],serial:&mut usize){
        *serial+=1;
        visited[a]=*serial;
        let mut neighbors=m.neighbors[a].clone();
        neighbors.sort_by_key(|&(b,_)|ranks[b]);
        for(b,e)in neighbors{
            if Some(e)==incoming||kind[e]==2{
                continue;
            }
            if visited[b]==0{
                kind[e]=1;
                children[a].push((b,e));
                visit(m,b,Some(e),ranks,visited,kind,children,serial);
            }else{
                kind[e]=2;
            }
        }
    }
    fn write(m:&Molecule,a:usize,elements:&Elements,visited:&[usize],kind:&[u8],children:&[Vec<(usize,usize)>],assigned:&mut BTreeMap<usize,usize>)->String{
        let mut text=atom(m,a,elements);
        let mut closures:Vec<_>=m.neighbors[a].iter().copied().filter(|&(_,e)|kind[e]==2).collect();
        closures.sort_by_key(|&(b,_)|visited[b]);
        for(_,e)in closures{
            let number=if let Some(number)=assigned.remove(&e){
                number
            }else{
                let number=(1..).find(|n|!assigned.values().any(|v|v==n)).unwrap();
                assigned.insert(e,number);
                text.push_str(bond(m,e));
                number
            };
            if number<10{
                text.push_str(&number.to_string());
            }else{
                text.push_str(&format!("%{:02}",number));
            }
        }
        for(i,&(child,e))in children[a].iter().enumerate(){
            let branch=i+1<children[a].len();
            if branch{
                text.push('(');
            }
            text.push_str(bond(m,e));
            text.push_str(&write(m,child,elements,visited,kind,children,assigned));
            if branch{
                text.push(')');
            }
        }
        text
    }
    let(ranks,classes)=ranks(m,elements);
    let start=ranks.iter().position(|&r|r==1).unwrap();
    let mut visited=vec![0;m.atoms.len()];
    let mut kind=vec![0;m.bonds.len()];
    let mut children=vec![Vec::new();m.atoms.len()];
    visit(m,start,None,&ranks,&mut visited,&mut kind,&mut children,&mut 0);
    (write(m,start,elements,&visited,&kind,&children,&mut BTreeMap::new()),classes)
}
