use std::collections::BTreeSet;
use crate::grounding::{Action,State};
use crate::search;
type Mutex=BTreeSet<(usize,usize)>;
fn pair(a:usize,b:usize)->(usize,usize){
    (a.min(b),a.max(b))
}
fn compatible(pre:&State,mutex:&Mutex)->bool{
    pre.iter().all(|&p|pre.iter().all(|&q|p==q||!mutex.contains(&pair(p,q))))
}
#[derive(Clone)] struct Element{
    action:Option<usize>,
    pre:State,
    add:State,
    del:State
}
#[derive(Clone)] struct Level{
    elements:Vec<Element>,
    mutex:Mutex
}
struct Extractor{
    levels:Vec<Level>,
    memo:BTreeSet<(usize,Vec<usize>)>,
    searched:usize,
    hits:usize,
    tried:usize
}
impl Extractor{
    fn extract(&mut self,j:usize,goals:Vec<usize>)->Option<Vec<Vec<usize>>>{
        if j==0{
            return Some(Vec::new());
        }
        if self.memo.contains(&(j,goals.clone())){
            self.hits+=1;
            return None;
        }
        self.searched+=1;
        let result=self.assign(j,&goals,0,Vec::new());
        if result.is_none(){
            self.memo.insert((j,goals));
        }
        result
    }
    fn assign(&mut self,j:usize,goals:&[usize],mut k:usize,chosen:Vec<usize>)->Option<Vec<Vec<usize>>>{
        let level=self.levels[j-1].clone();
        while k<goals.len()&&chosen.iter().any(|&x|level.elements[x].add.contains(&goals[k])){
            k+=1;
        }
        if k==goals.len(){
            let previous:State=chosen.iter().flat_map(|&x|level.elements[x].pre.iter().copied()).collect();
            let mut plan=self.extract(j-1,previous.into_iter().collect())?;
            let mut actions:Vec<_>=chosen.iter().filter_map(|&x|level.elements[x].action).collect();
            actions.sort();
            plan.push(actions);
            return Some(plan);
        }
        let goal=goals[k];
        let mut achievers:Vec<_>=level.elements.iter().enumerate().filter(|(_,e)|e.add.contains(&goal)).map(|(i,_)|i).collect();
        achievers.sort_by_key(|&i|(level.elements[i].action.is_some(),level.elements[i].action.unwrap_or(0)));
        for x in achievers{
            if chosen.iter().all(|&y|x==y||!level.mutex.contains(&pair(x,y))){
                self.tried+=1;
                let mut next=chosen.clone();
                next.push(x);
                if let Some(plan)=self.assign(j,goals,k+1,next){
                    return Some(plan);
                }
            }
        }
        None
    }
}
pub struct Result{
    pub search:search::Result,
    pub layers:Vec<Vec<usize>>,
    pub records:Vec<String>,
    pub hits:usize
}
pub fn run(actions:&[Action],initial:&State,goals:&State,limit:usize)->Result{
    let mut extractor=Extractor{
        levels:Vec::new(),
        memo:BTreeSet::new(),
        searched:0,
        hits:0,
        tried:0
    };
    let mut facts=initial.clone();
    let mut mutex=Mutex::new();
    let(mut previous_counts,mut records,mut answer,mut status)=(None,Vec::new(),Vec::new(),"level limit");
    for i in 0..=limit{
        records.push(format!("fact level {}: facts={} mutexes={}",i,facts.len(),mutex.len()));
        let extract=goals.is_subset(&facts)&&compatible(goals,&mutex);
        if extract{
            let before=extractor.searched;
            let hits=extractor.hits;
            let result=extractor.extract(i,goals.iter().copied().collect());
            records.push(format!("extract level {}: {} searched={} memo_hits={}",i,if result.is_some(){
                "success"
            }else{
                "fail"
            },extractor.searched-before,extractor.hits-hits));
            if let Some(plan)=result{
                answer=plan;
                status="solved";
                break;
            }
        }else if previous_counts==Some((facts.len(),mutex.len())){
            status="unreachable";
            break;
        }
        if i==limit{
            break;
        }
        previous_counts=Some((facts.len(),mutex.len()));
        let mut elements:Vec<_>=actions.iter().enumerate().filter(|(_,a)|a.pre.is_subset(&facts)&&compatible(&a.pre,&mutex)).map(|(i,a)|Element{
            action:Some(i),
            pre:a.pre.clone(),
            add:a.add.clone(),
            del:a.del.clone()
        }).collect();
        let real=elements.len();
        for &p in &facts{
            let singleton=[p].iter().copied().collect();
            elements.push(Element{
                action:None,
                pre:singleton,
                add:[p].iter().copied().collect(),
                del:State::new()
            });
        }
        let mut action_mutex=Mutex::new();
        for x in 0..elements.len(){
            for y in x+1..elements.len(){
                let(a,b)=(&elements[x],&elements[y]);
                let interference=!a.del.is_disjoint(&b.pre)||!a.del.is_disjoint(&b.add)||!b.del.is_disjoint(&a.pre)||!b.del.is_disjoint(&a.add);
                let competing=a.pre.iter().any(|&p|b.pre.iter().any(|&q|p!=q&&mutex.contains(&pair(p,q))));
                if interference||competing{
                    action_mutex.insert((x,y));
                }
            }
        }
        records.push(format!("action level {}: actions={} noops={} mutexes={}",i,real,facts.len(),action_mutex.len()));
        let next:State=elements.iter().flat_map(|e|e.add.iter().copied()).collect();
        let values:Vec<_>=next.iter().copied().collect();
        let mut next_mutex=Mutex::new();
        for x in 0..values.len(){
            for y in x+1..values.len(){
                let(p,q)=(values[x],values[y]);
                let impossible=elements.iter().enumerate().filter(|(_,e)|e.add.contains(&p)).all(|(a,_)|elements.iter().enumerate().filter(|(_,e)|e.add.contains(&q)).all(|(b,_)|a!=b&&action_mutex.contains(&pair(a,b))));
                if impossible{
                    next_mutex.insert((p,q));
                }
            }
        }
        extractor.levels.push(Level{
            elements,
            mutex:action_mutex
        });
        facts=next;
        mutex=next_mutex;
    }
    let plan=answer.iter().flat_map(|v|v.iter().copied()).collect();
    Result{
        search:search::Result{
            status,
            plan,
            expanded:extractor.searched,
            generated:extractor.tried
        },
        layers:answer,
        records,
        hits:extractor.hits
    }
}
