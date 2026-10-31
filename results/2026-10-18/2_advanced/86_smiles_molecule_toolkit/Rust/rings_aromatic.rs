use std::collections::{BTreeMap,BTreeSet,VecDeque};
use crate::molecule::{Molecule,Elements,Error};
fn edge_set(m:&Molecule,ring:&[usize])->BTreeSet<usize>{
    (0..ring.len()).map(|i|m.bond(ring[i],ring[(i+1)%ring.len()]).unwrap()).collect()
}
pub fn detect(m:&mut Molecule){
    let n=m.atoms.len();
    let mut candidates=Vec::new();
    let mut seen=BTreeSet::new();
    for root in 0..n{
        let mut parent=vec![None;n];
        let mut visited=vec![false;n];
        visited[root]=true;
        let mut queue=VecDeque::new();
        queue.push_back(root);
        while let Some(a)=queue.pop_front(){
            for &(b,_)in &m.neighbors[a]{
                if !visited[b]{
                    visited[b]=true;
                    parent[b]=Some(a);
                    queue.push_back(b);
                }
            }
        }
        let path=|mut x:usize|{
            let mut p=vec![x];
            while let Some(a)=parent[x]{
                p.push(a);
                x=a;
            }
            p
        };
        for bond in &m.bonds{
            let(x,y)=(bond.a,bond.b);
            if parent[x]==Some(y)||parent[y]==Some(x){
                continue;
            }
            let(mut a,mut b)=(path(x),path(y));
            if a.iter().any(|v|*v!=root&&b.contains(v)){
                continue;
            }
            a.reverse();
            b.pop();
            a.extend(b);
            let edges=edge_set(m,&a);
            if seen.insert(edges.clone()){
                candidates.push((a,edges));
            }
        }
    }
    candidates.sort_by_key(|(r,_)|r.len());
    let mut basis:BTreeMap<usize,BTreeSet<usize>>=BTreeMap::new();
    let mut selected=Vec::new();
    for(ring,edges)in candidates{
        let mut vector=edges.clone();
        while let Some(&pivot)=vector.iter().next_back(){
            if let Some(b)=basis.get(&pivot){
                vector=vector.symmetric_difference(b).copied().collect();
            }else{
                basis.insert(pivot,vector);
                selected.push(ring);
                break;
            }
        }
    }
    for r in &mut selected{
        let k=r.iter().enumerate().min_by_key(|(_,a)|**a).unwrap().0;
        r.rotate_left(k);
        if r[1]>r[r.len()-1]{
            r[1..].reverse();
        }
    }
    selected.sort_by(|a,b|a.len().cmp(&b.len()).then(a.cmp(b)));
    for r in &selected{
        for e in edge_set(m,r){
            m.bonds[e].ring=true;
        }
    }
    m.rings=selected;
}
fn matching(m:&Molecule,system:&BTreeSet<usize>,paired:&mut BTreeMap<usize,usize>)->bool{
    let u=match system.iter().find(|u|!paired.contains_key(*u)){
        Some(&u)=>u,None=>return true
    };
    for &(v,e)in &m.neighbors[u]{
        if system.contains(&v)&&!paired.contains_key(&v)&&m.bonds[e].kind==4{
            paired.insert(u,v);
            paired.insert(v,u);
            if matching(m,system,paired){
                return true;
            }
            paired.remove(&u);
            paired.remove(&v);
        }
    }
    false
}
pub fn kekulize(m:&mut Molecule,elements:&Elements)->Result<(),Error>{
    let mut remaining:BTreeSet<_>=(0..m.atoms.len()).filter(|&i|m.needs_pi(i,elements,true)).collect();
    let mut paired=BTreeMap::new();
    while let Some(&start)=remaining.iter().next(){
        let mut system=BTreeSet::new();
        let mut stack=vec![start];
        remaining.remove(&start);
        while let Some(a)=stack.pop(){
            system.insert(a);
            for &(b,e)in &m.neighbors[a]{
                if m.bonds[e].kind==4&&remaining.remove(&b){
                    stack.push(b);
                }
            }
        }
        if !matching(m,&system,&mut paired){
            return Err(Error::new("kekulization failed",m.atoms[*system.iter().next().unwrap()].column));
        }
    }
    for b in &mut m.bonds{
        b.multiplicity=if b.kind==4{
            if paired.get(&b.a)==Some(&b.b){
                2
            }else{
                1
            }
        }else{
            b.kind as usize
        };
    }
    Ok(())
}
