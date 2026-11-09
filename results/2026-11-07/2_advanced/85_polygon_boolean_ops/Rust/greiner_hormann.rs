use crate::rational::{Point,Fraction};
use crate::intersections;
use crate::rings::{self,Rings,Region};
#[derive(Clone)] struct Crossing{
    point:Point,
    ar:usize,
    ae:usize,
    br:usize,
    be:usize,
    t:Fraction,
    u:Fraction
}
#[derive(Clone)] struct Node{
    point:Point,
    crossing:Option<usize>,
    enter:bool
}
pub struct Graph{
    nodes:Vec<Vec<Vec<Node>>>,
    locations:Vec<[(usize,usize);2]>,
    pub ordered:Vec<(Point,bool)>,
    order:Vec<usize>,
    pub na:usize,
    pub nb:usize
}
impl Graph{
    pub fn new(a:&Rings,b:&Rings)->Self{
        let mut crossings=Vec::new();
        for(ar,r)in a.iter().enumerate(){
            for ae in 0..r.len(){
                for(br,q)in b.iter().enumerate(){
                    for be in 0..q.len(){
                        if let Some((point,t,u))=intersections::crossing(r[ae],r[(ae+1)%r.len()],q[be],q[(be+1)%q.len()]){
                            crossings.push(Crossing{
                                point,
                                ar,
                                ae,
                                br,
                                be,
                                t,
                                u
                            });
                        }
                    }
                }
            }
        }
        let mut nodes=vec![Vec::new(),Vec::new()];
        let mut locations=vec![[(0,0);2];crossings.len()];
        let mut order=Vec::new();
        let mut ordered=Vec::new();
        for(side,(p,q))in [(a,b),(b,a)].iter().enumerate(){
            for(ri,ring)in p.iter().enumerate(){
                let mut list=Vec::new();
                let mut inside=rings::interior(ring[0],q);
                for edge in 0..ring.len(){
                    list.push(Node{
                        point:ring[edge],
                        crossing:None,
                        enter:false
                    });
                    let mut on:Vec<_>=crossings.iter().enumerate().filter(|(_,c)|if side==0{
                        c.ar==ri&&c.ae==edge
                    }else{
                        c.br==ri&&c.be==edge
                    }).map(|(i,c)|(if side==0{
                        c.t
                    }else{
                        c.u
                    },i)).collect();
                    on.sort();
                    for(_,id)in on{
                        locations[id][side]=(ri,list.len());
                        list.push(Node{
                            point:crossings[id].point,
                            crossing:Some(id),
                            enter:!inside
                        });
                        if side==0{
                            order.push(id);
                            ordered.push((crossings[id].point,!inside));
                        }
                        inside=!inside;
                    }
                }
                nodes[side].push(list);
            }
        }
        let na=a.iter().filter(|r|rings::interior(r[0],b)).count();
        let nb=b.iter().filter(|r|rings::interior(r[0],a)).count();
        Self{
            nodes,
            locations,
            ordered,
            order,
            na,
            nb
        }
    }
    pub fn result(&self,kind:&str)->Region{
        let inverted=match kind{
            "UNION"=>[true,true],"DIFFERENCE"=>[true,false],_=>[false,false]
        };
        let mut visited=vec![false;self.locations.len()];
        let mut rings=Vec::new();
        for &start in &self.order{
            if visited[start]{
                continue;
            }
            let(mut side,mut id)=(0,start);
            let mut points=Vec::new();
            loop{
                let(ri,index)=self.locations[id][side];
                let list=&self.nodes[side][ri];
                let node=&list[index];
                visited[id]=true;
                points.push(node.point);
                let forward=node.enter!=inverted[side];
                let mut next=index;
                loop{
                    next=if forward{
                        (next+1)%list.len()
                    }else{
                        (next+list.len()-1)%list.len()
                    };
                    if list[next].crossing.is_some(){
                        break;
                    }
                    points.push(list[next].point);
                }
                let found=list[next].crossing.unwrap();
                if found==start{
                    break;
                }
                id=found;
                side=1-side;
            }
            rings.push(points);
        }
        for side in 0..2{
            for list in &self.nodes[side]{
                if list.iter().any(|n|n.crossing.is_some()){
                    continue;
                }
                let other:Vec<_>=self.nodes[1-side].iter().map(|r|r.iter().map(|n|n.point).collect()).collect();
                let inside=rings::interior(list[0].point,&other);
                if inside!=inverted[side]{
                    rings.push(list.iter().map(|n|n.point).collect());
                }
            }
        }
        rings::assemble(rings)
    }
}
