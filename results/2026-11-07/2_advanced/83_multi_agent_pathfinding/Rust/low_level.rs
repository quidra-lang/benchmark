use std::cmp::Reverse;
use std::collections::{BTreeMap,BTreeSet};
use crate::grid_map::{Cell,Path,Grid};
#[derive(Clone,Default)] pub struct Constraints{
    pub states:BTreeSet<(Cell,usize)>,
    pub moves:BTreeSet<(Cell,Cell,usize)>,
    pub permanent:BTreeSet<(Cell,usize)>
}
impl Constraints{
    pub fn allowed(&self,u:Cell,v:Cell,t:usize)->bool{
        !self.states.contains(&(v,t))&&!self.permanent.iter().any(|&(c,s)|c==v&&s<=t)&&(u==v||!self.moves.contains(&(u,v,t)))
    }
    pub fn arrival(&self,goal:Cell)->usize{
        self.states.iter().filter(|&&(c,_)|c==goal).map(|&(_,t)|t+1).max().unwrap_or(0)
    }
    pub fn reserve(&mut self,path:&Path,start:usize,permanent:bool){
        for(k,&c)in path.iter().enumerate(){
            self.states.insert((c,start+k));
            if k>0&&c!=path[k-1]{
                self.moves.insert((c,path[k-1],start+k));
            }
        }
        if permanent{
            self.permanent.insert((*path.last().unwrap(),start+path.len()-1));
        }
    }
}
#[derive(Default)] pub struct Counts{
    pub searches:usize,
    pub expansions:usize,
    pub budget:usize
}
#[derive(Debug)] pub struct Abort;
pub fn search(grid:&Grid,i:usize,start:Cell,t0:usize,tmax:usize,window:bool,constraints:&Constraints,count:&mut Counts)->Result<Option<Path>,Abort>{
    count.searches+=1;
    let goal=grid.agents[i].goal;
    let distances=&grid.distances[i];
    let arrival=constraints.arrival(goal);
    let mut open=BTreeMap::new();
    let mut generated=BTreeSet::new();
    let mut parent:BTreeMap<(Cell,usize),(Cell,usize)>=BTreeMap::new();
    let mut serial=0;
    open.insert((distances[&start],Reverse(0),0),(start,t0));
    generated.insert((start,t0));
    while let Some((_,(c,t)))=open.pop_first(){
        count.expansions+=1;
        if count.expansions>count.budget{
            return Err(Abort);
        }
        if c==goal&&t>=arrival||window&&t==tmax{
            let mut path=vec![c];
            let mut state=(c,t);
            while let Some(&previous)=parent.get(&state){
                path.push(previous.0);
                state=previous;
            }
            path.reverse();
            return Ok(Some(path));
        }
        if t==tmax{
            continue;
        }
        for v in grid.destinations(c){
            if let Some(&h)=distances.get(&v){
                if constraints.allowed(c,v,t+1)&&generated.insert((v,t+1)){
                    serial+=1;
                    parent.insert((v,t+1),(c,t));
                    let g=t+1-t0;
                    open.insert((g+h,Reverse(g),serial),(v,t+1));
                }
            }
        }
    }
    Ok(None)
}
