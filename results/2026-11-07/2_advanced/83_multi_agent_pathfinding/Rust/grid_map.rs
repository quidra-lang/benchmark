use std::collections::{BTreeMap,VecDeque};
use std::fs;
pub type Cell=(i32,i32);
pub type Path=Vec<Cell>;
#[derive(Clone)] pub struct Agent{
    pub start:Cell,
    pub goal:Cell
}
pub struct Grid{
    pub width:usize,
    pub height:usize,
    pub rows:Vec<Vec<char>>,
    pub agents:Vec<Agent>,
    pub distances:Vec<BTreeMap<Cell,usize>>
}
impl Grid{
    pub fn read()->Self{
        let text=fs::read_to_string("input/map.txt").unwrap();
        let mut lines=text.lines();
        let size:Vec<usize>=lines.next().unwrap().split(' ').map(|v|v.parse().unwrap()).collect();
        let rows=lines.map(|v|v.chars().collect()).collect();
        let agents=fs::read_to_string("input/agents.csv").unwrap().lines().skip(1).map(|v|{
            let a:Vec<i32>=v.split(',').map(|v|v.parse().unwrap()).collect();
            Agent{
                start:(a[1],a[2]),
                goal:(a[3],a[4])
            }
        }).collect();
        let mut grid=Self{
            width:size[0],
            height:size[1],
            rows,
            agents,
            distances:Vec::new()
        };
        grid.distances=grid.agents.iter().map(|a|grid.distance(a.goal)).collect();
        grid
    }
    pub fn free(&self,c:Cell)->bool{
        c.0>=0&&c.1>=0&&(c.0 as usize)<self.width&&(c.1 as usize)<self.height&&self.rows[c.1 as usize][c.0 as usize]=='.'
    }
    pub fn destinations(&self,c:Cell)->Vec<Cell>{
        [(0,0),(0,-1),(1,0),(0,1),(-1,0)].iter().map(|&(x,y)|(c.0+x,c.1+y)).filter(|&c|self.free(c)).collect()
    }
    pub fn cells(&self)->Vec<Cell>{
        (0..self.height).flat_map(|y|(0..self.width).map(move |x|(x as i32,y as i32))).filter(|&c|self.free(c)).collect()
    }
    pub fn distance(&self,goal:Cell)->BTreeMap<Cell,usize>{
        let mut d=BTreeMap::new();
        let mut q=VecDeque::new();
        d.insert(goal,0);
        q.push_back(goal);
        while let Some(c)=q.pop_front(){
            let next=d[&c]+1;
            for v in self.destinations(c).into_iter().skip(1){
                if !d.contains_key(&v){
                    d.insert(v,next);
                    q.push_back(v);
                }
            }
        }
        d
    }
}
