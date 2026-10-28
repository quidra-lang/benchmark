use std::collections::{BTreeMap,BTreeSet,VecDeque};
use crate::grounding::{Grounding,Action,State};
use crate::heuristics::{self,INF};
pub fn applicable(a:&Action,s:&State)->bool{
    a.pre.is_subset(s)&&a.neg.is_disjoint(s)
}
pub fn apply(a:&Action,s:&State)->State{
    let mut next:State=s.difference(&a.del).copied().collect();
    next.extend(&a.add);
    next
}
#[derive(Clone)] pub struct Result{
    pub status:&'static str,
    pub plan:Vec<usize>,
    pub expanded:usize,
    pub generated:usize
}
impl Result{
    pub fn failure(reason:&'static str)->Self{
        Self{
            status:reason,
            plan:Vec::new(),
            expanded:0,
            generated:0
        }
    }
}
struct Node{
    state:State,
    g:i64,
    depth:usize,
    parent:Option<usize>,
    action:Option<usize>
}
pub fn run(g:&Grounding,start:&State,algorithm:&str,h:&str,budget:usize,weight:i64)->Result{
    if algorithm=="ehc"{
        return ehc(g,start,h,budget);
    }
    let mut result=Result::failure("exhausted");
    let initial_h=heuristics::value(g,start,h);
    if initial_h>=INF{
        result.status="dead end";
        return result;
    }
    let mut nodes=vec![Node{
        state:start.clone(),g:0,depth:0,parent:None,action:None
    }];
    let mut open=BTreeMap::new();
    let key=|cost:i64,depth:usize,h:i64,serial:usize|{
        let f=match algorithm{
            "bfs"=>depth as i64,"ucs"=>cost,"gbfs"=>h,"astar"=>cost+h,_=>cost+weight*h
        };
        (f,h,serial)
    };
    open.insert(key(0,0,initial_h,0),0usize);
    let mut table=BTreeMap::new();
    table.insert(start.clone(),0);
    while let Some((_,index))=open.pop_first(){
        let state=nodes[index].state.clone();
        let cost=nodes[index].g;
        let depth=nodes[index].depth;
        if ["ucs","astar","wastar"].contains(&algorithm)&&cost>table[&state]{
            continue;
        }
        if g.goals.is_subset(&state){
            result.status="solved";
            let mut current=index;
            while let Some(parent)=nodes[current].parent{
                result.plan.push(nodes[current].action.unwrap());
                current=parent;
            }
            result.plan.reverse();
            return result;
        }
        if result.expanded==budget{
            result.status="budget";
            return result;
        }
        result.expanded+=1;
        for(a,action)in g.actions.iter().enumerate(){
            if !applicable(action,&state){
                continue;
            }
            result.generated+=1;
            let next=apply(action,&state);
            let next_g=cost+action.cost;
            let discard=table.get(&next).map_or(false,|&old|if algorithm=="bfs"||algorithm=="gbfs"{
                true
            }else{
                old<=next_g
            });
            if discard{
                continue;
            }
            table.insert(next.clone(),next_g);
            let value=heuristics::value(g,&next,h);
            if value>=INF{
                continue;
            }
            let serial=nodes.len();
            nodes.push(Node{
                state:next,
                g:next_g,
                depth:depth+1,
                parent:Some(index),
                action:Some(a)
            });
            open.insert(key(next_g,depth+1,value,serial),serial);
        }
    }
    result
}
fn ehc(g:&Grounding,start:&State,h:&str,budget:usize)->Result{
    let mut result=Result::failure("stuck");
    let mut current=start.clone();
    let mut hc=heuristics::value(g,&current,h);
    if hc>=INF{
        result.status="dead end";
        return result;
    }
    loop{
        if g.goals.is_subset(&current){
            result.status="solved";
            return result;
        }
        let mut queue=VecDeque::new();
        queue.push_back((current.clone(),Vec::<usize>::new()));
        let mut visited=BTreeSet::new();
        visited.insert(current.clone());
        let mut improvement=None;
        while let Some((state,path))=queue.pop_front(){
            if result.expanded==budget{
                result.status="budget";
                return result;
            }
            result.expanded+=1;
            for a in heuristics::relaxed(g,&state).2{
                result.generated+=1;
                let next=apply(&g.actions[a],&state);
                if !visited.insert(next.clone()){
                    continue;
                }
                let value=heuristics::value(g,&next,h);
                if value>=INF{
                    continue;
                }
                let mut next_path=path.clone();
                next_path.push(a);
                if value<hc{
                    improvement=Some((next,value,next_path));
                    break;
                }
                queue.push_back((next,next_path));
            }
            if improvement.is_some(){
                break;
            }
        }
        if let Some((next,h,path))=improvement{
            current=next;
            hc=h;
            result.plan.extend(path);
        }else{
            return result;
        }
    }
}
