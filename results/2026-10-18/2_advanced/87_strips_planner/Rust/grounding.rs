use std::collections::{BTreeMap,BTreeSet};
use crate::pddl_parser::{Domain,Problem,Atom};
pub type State=BTreeSet<usize>;
#[derive(Clone)] pub struct Action{
    pub source:usize,
    pub name:String,
    pub args:Vec<String>,
    pub cost:i64,
    pub pre:State,
    pub neg:State,
    pub add:State,
    pub del:State
}
impl Action{
    pub fn text(&self)->String{
        Atom{
            predicate:self.name.clone(),
            terms:self.args.clone()
        }.text()
    }
}
pub struct Grounding{
    pub facts:Vec<Atom>,
    pub actions:Vec<Action>,
    pub initial:State,
    pub goals:State,
    pub unreachable:Vec<Atom>,
    pub stats:Vec<[usize;3]>,
    pub fluent:BTreeSet<String>,
    pub static_count:usize
}
pub fn subtype(d:&Domain,t:&str,u:&str)->bool{
    let mut current=t.to_string();
    loop {
        if current==u { return true; }
        if let Some(parent)=d.parents.get(&current) { current=parent.clone(); }
        else { return false; }
    }
}

pub fn fluents(d:&Domain)->BTreeSet<String>{
    d.actions.iter().flat_map(|a|a.effects.iter().map(|l|l.atom.predicate.clone())).collect()
}
struct Candidate{
    source:usize,
    args:Vec<String>,
    pre:BTreeSet<Atom>,
    neg:BTreeSet<Atom>,
    add:BTreeSet<Atom>,
    del:BTreeSet<Atom>
}
pub fn ground(d:&Domain,p:&Problem)->Grounding{
    fn combinations(choices:&[Vec<String>],i:usize,current:&mut Vec<String>,all:&mut Vec<Vec<String>>){
        if i==choices.len(){
            all.push(current.clone());
            return;
        }
        for x in &choices[i]{
            current.push(x.clone());
            combinations(choices,i+1,current,all);
            current.pop();
        }
    }
    let fluent=fluents(d);
    let initial:BTreeSet<_>=p.initial.iter().cloned().collect();
    let mut stats=vec![[0;3];d.actions.len()];
    let mut candidates=Vec::new();
    for(source,a)in d.actions.iter().enumerate(){
        let choices:Vec<Vec<String>>=a.parameters.iter().map(|(_,t)|p.objects.iter().filter(|(_,u)|subtype(d,u,t)).map(|(n,_)|n.clone()).collect()).collect();
        let mut all=Vec::new();
        combinations(&choices,0,&mut Vec::new(),&mut all);
        stats[source][0]=all.len();
        for args in all{
            let values:BTreeMap<_,_>=a.parameters.iter().map(|(n,_)|n.clone()).zip(args.iter().cloned()).collect();
            let mut c=Candidate{
                source,
                args,
                pre:BTreeSet::new(),
                neg:BTreeSet::new(),
                add:BTreeSet::new(),
                del:BTreeSet::new()
            };
            let mut valid=true;
            for l in &a.pre{
                let atom=l.atom.replace(&values);
                if atom.predicate=="="||!fluent.contains(&atom.predicate){
                    let truth=if atom.predicate=="="{
                        atom.terms[0]==atom.terms[1]
                    }else{
                        initial.contains(&atom)
                    };
                    if truth==l.negative{
                        valid=false;
                        break;
                    }
                }else if l.negative{
                    c.neg.insert(atom);
                }else{
                    c.pre.insert(atom);
                }
            }
            if !valid{
                continue;
            }
            for l in &a.effects{
                let atom=l.atom.replace(&values);
                if l.negative{
                    c.del.insert(atom);
                }else{
                    c.add.insert(atom);
                }
            }
            c.del=c.del.difference(&c.add).cloned().collect();
            stats[source][1]+=1;
            candidates.push(c);
        }
    }
    let mut reachable:BTreeSet<_>=initial.iter().filter(|a|fluent.contains(&a.predicate)).cloned().collect();
    let mut kept=BTreeSet::new();
    loop{
        let before=kept.len();
        for(i,c)in candidates.iter().enumerate(){
            if c.pre.is_subset(&reachable){
                kept.insert(i);
                reachable.extend(c.add.iter().cloned());
            }
        }
        if kept.len()==before{
            break;
        }
    }
    let predicates:BTreeMap<_,_>=d.predicates.iter().enumerate().map(|(i,p)|(p.name.clone(),i)).collect();
    let objects:BTreeMap<_,_>=p.objects.iter().enumerate().map(|(i,(n,_))|(n.clone(),i)).collect();
    let mut facts:Vec<_>=reachable.into_iter().collect();
    facts.sort_by_key(|a|(predicates[&a.predicate],a.terms.iter().map(|n|objects[n]).collect::<Vec<_>>()));
    let numbering:BTreeMap<_,_>=facts.iter().enumerate().map(|(i,a)|(a.clone(),i)).collect();
    let numbers=|atoms:&BTreeSet<Atom>|atoms.iter().filter_map(|a|numbering.get(a).copied()).collect::<State>();
    let mut actions=Vec::new();
    for i in kept{
        let c=&candidates[i];
        stats[c.source][2]+=1;
        let a=&d.actions[c.source];
        actions.push(Action{
            source:c.source,
            name:a.name.clone(),
            args:c.args.clone(),
            cost:a.cost,
            pre:numbers(&c.pre),
            neg:numbers(&c.neg),
            add:numbers(&c.add),
            del:numbers(&c.del)
        });
    }
    let initial_state=initial.iter().filter_map(|a|numbering.get(a).copied()).collect();
    let mut goals=State::new();
    let mut unreachable=Vec::new();
    for a in &p.goals{
        if let Some(&i)=numbering.get(a){
            goals.insert(i);
        }else if fluent.contains(&a.predicate)||!initial.contains(a){
            unreachable.push(a.clone());
        }
    }
    Grounding{
        facts,
        actions,
        initial:initial_state,
        goals,
        unreachable,
        stats,
        fluent:fluent.clone(),
        static_count:p.initial.iter().filter(|a|!fluent.contains(&a.predicate)).count()
    }
}
