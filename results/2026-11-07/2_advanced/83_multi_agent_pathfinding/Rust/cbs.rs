use crate::grid_map::{Cell,Path};
use crate::low_level::Constraints;
pub fn position(path:&Path,t:usize)->Cell{
    path[t.min(path.len()-1)]
}
#[derive(Clone)] pub struct Conflict{
    pub time:usize,
    pub a:usize,
    pub b:usize,
    pub vertex:bool,
    pub u:Cell,
    pub v:Cell
}
pub fn conflicts(paths:&[Path])->Vec<Conflict>{
    let tmax=paths.iter().map(|p|p.len()-1).max().unwrap_or(0);
    let mut all=Vec::new();
    for t in 1..=tmax{
        for a in 0..paths.len(){
            for b in a+1..paths.len(){
                let(u,v)=(position(&paths[a],t-1),position(&paths[a],t));
                let(bu,bv)=(position(&paths[b],t-1),position(&paths[b],t));
                if v==bv{
                    all.push(Conflict{
                        time:t,
                        a,
                        b,
                        vertex:true,
                        u:v,
                        v
                    });
                }else if u==bv&&v==bu{
                    all.push(Conflict{
                        time:t,
                        a,
                        b,
                        vertex:false,
                        u,
                        v
                    });
                }
            }
        }
    }
    all
}
impl Conflict{
    pub fn constrain(&self,i:usize,c:&mut Constraints){
        if self.vertex{
            c.states.insert((self.v,self.time));
        }else if i==self.a{
            c.moves.insert((self.u,self.v,self.time));
        }else{
            c.moves.insert((self.v,self.u,self.time));
        }
    }
}
#[derive(Clone)] pub struct Node{
    pub id:usize,
    pub parent:Option<usize>,
    pub depth:usize,
    pub constraints:Vec<Constraints>,
    pub paths:Vec<Path>,
    pub conflicts:Vec<Conflict>,
    pub cost:usize
}
impl Node{
    pub fn new(id:usize,parent:Option<usize>,depth:usize,constraints:Vec<Constraints>,paths:Vec<Path>,soc:bool)->Self{
        let conflicts=conflicts(&paths);
        let cost=if soc{
            paths.iter().map(|p|p.len()-1).sum()
        }else{
            paths.iter().map(|p|p.len()-1).max().unwrap_or(0)
        };
        Self{
            id,
            parent,
            depth,
            constraints,
            paths,
            conflicts,
            cost
        }
    }
    pub fn key(&self)->(usize,usize,usize){
        (self.cost,self.conflicts.len(),self.id)
    }
}
