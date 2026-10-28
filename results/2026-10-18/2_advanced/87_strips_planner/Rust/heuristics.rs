use std::collections::BTreeSet;
use crate::grounding::{Grounding,State};
pub const INF:i64=1_000_000_000_000;
fn aggregate(values:impl Iterator<Item=i64>,maximum:bool)->i64{
    let mut out=0;
    for v in values{
        if v>=INF{
            return INF;
        }
        if maximum{
            out=out.max(v);
        }else{
            out+=v;
        }
    }
    out
}
pub fn costs(g:&Grounding,s:&State,maximum:bool)->Vec<i64>{
    let mut c=vec![INF;g.facts.len()];
    for &p in s{
        c[p]=0;
    }
    loop{
        let mut changed=false;
        for a in &g.actions{
            let v=aggregate(a.pre.iter().map(|&p|c[p]),maximum);
            if v>=INF{
                continue;
            }
            let v=v+a.cost;
            for &p in &a.add{
                if v<c[p]{
                    c[p]=v;
                    changed=true;
                }
            }
        }
        if !changed{
            return c;
        }
    }
}
pub fn relaxed(g:&Grounding,s:&State)->(i64,Vec<usize>,Vec<usize>){
    let c=costs(g,s,false);
    if g.goals.iter().any(|&p|c[p]>=INF){
        return(INF,Vec::new(),Vec::new());
    }
    let achiever=|p:usize|g.actions.iter().enumerate().filter(|(_,a)|a.add.contains(&p)&&a.pre.iter().all(|&q|c[q]<INF)).min_by_key(|(i,a)|(a.cost+a.pre.iter().map(|&q|c[q]).sum::<i64>(),*i)).unwrap().0;
    let mut chosen=BTreeSet::new();
    let mut pending:Vec<_>=g.goals.difference(s).copied().collect();
    while let Some(p)=pending.pop(){
        let a=achiever(p);
        if chosen.insert(a){
            pending.extend(g.actions[a].pre.difference(s).copied());
        }
    }
    let plan:Vec<_>=chosen.into_iter().collect();
    let helpful=plan.iter().copied().filter(|&a|crate::search::applicable(&g.actions[a],s)).collect();
    let value=plan.iter().map(|&a|g.actions[a].cost).sum();
    (value,plan,helpful)
}
pub fn landmarks(g:&Grounding,s:&State)->Option<State>{
    let mut fact_level=vec![usize::MAX;g.facts.len()];
    for &p in s{
        fact_level[p]=0;
    }
    let mut action_level=vec![usize::MAX;g.actions.len()];
    for k in 0..{
        let mut added=false;
        for(i,a)in g.actions.iter().enumerate(){
            if action_level[i]==usize::MAX&&a.pre.iter().all(|&p|fact_level[p]<=k){
                action_level[i]=k;
                for &p in &a.add{
                    if fact_level[p]==usize::MAX{
                        fact_level[p]=k+1;
                        added=true;
                    }
                }
            }
        }
        if !added{
            break;
        }
    }
    if g.goals.iter().any(|&p|fact_level[p]==usize::MAX){
        return None;
    }
    let mut lm:State=g.goals.difference(s).copied().collect();
    loop{
        let before=lm.len();
        for p in lm.clone(){
            let achievers:Vec<_>=g.actions.iter().enumerate().filter(|(i,a)|action_level[*i]!=usize::MAX&&action_level[*i]+1==fact_level[p]&&a.add.contains(&p)).map(|(_,a)|a).collect();
            let mut candidates=achievers[0].pre.clone();
            for a in &achievers[1..]{
                candidates=candidates.intersection(&a.pre).copied().collect();
            }
            for q in candidates.difference(s){
                if lm.contains(q){
                    continue;
                }
                let mut reachable=s.clone();
                loop{
                    let old=reachable.len();
                    for a in &g.actions{
                        if !a.add.contains(q)&&a.pre.is_subset(&reachable){
                            reachable.extend(&a.add);
                        }
                    }
                    if old==reachable.len(){
                        break;
                    }
                }
                if !g.goals.is_subset(&reachable){
                    lm.insert(*q);
                }
            }
        }
        if lm.len()==before{
            return Some(lm);
        }
    }
}
pub fn value(g:&Grounding,s:&State,name:&str)->i64{
    match name{
        "none"=>0,"goalcount"=>g.goals.difference(s).count()as i64,"hmax"|"hadd"=>{
            let maximum=name=="hmax";
            let c=costs(g,s,maximum);
            aggregate(g.goals.iter().map(|&p|c[p]),maximum)
        },"ff"=>relaxed(g,s).0,_=>landmarks(g,s).map_or(INF,|m|m.len()as i64)
    }
}
pub fn values(g:&Grounding,s:&State)->[i64;5]{
    [value(g,s,"goalcount"),value(g,s,"hmax"),value(g,s,"hadd"),value(g,s,"ff"),value(g,s,"lmcount")]
}
