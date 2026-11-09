use std::collections::BTreeMap;
use std::fs;
pub const NAMES:[&str;13]=["layering","width","promotion","heuristic","sweeps","node_sep","dummy_sep","layer_gap","direction","sifting","reduce","restarts","seed"];
#[derive(Clone)] pub struct Settings{
    pub values:Vec<String>
}
impl Settings{
    pub fn default()->Self{
        Self{
            values:["longest","4","off","barycenter","12","2","1","3","TB","off","off","0","1"].iter().map(|v|v.to_string()).collect()
        }
    }
    pub fn text(&self,n:&str)->&str{
        &self.values[NAMES.iter().position(|v|*v==n).unwrap()]
    }
    pub fn integer(&self,n:&str)->usize{
        self.text(n).parse().unwrap()
    }
    pub fn on(&self,n:&str)->bool{
        self.text(n)=="on"
    }
    pub fn set(&mut self,n:&str,value:&str)->bool{
        let i=match NAMES.iter().position(|v|*v==n){
            Some(i)=>i,None=>return false
        };
        let words=match n{
            "layering"=>vec!["longest","coffman"],"promotion"|"sifting"|"reduce"=>vec!["on","off"],"heuristic"=>vec!["barycenter","median"],"direction"=>vec!["TB","BT","LR","RL"],_=>Vec::new()
        };
        if !words.is_empty(){
            if !words.contains(&value){
                return false;
            }
            self.values[i]=value.into();
            return true;
        }
        let(lo,hi)=match n{
            "width"=>(1,40),"sweeps"=>(0,50),"node_sep"|"dummy_sep"=>(1,9),"layer_gap"=>(2,9),"restarts"=>(0,9),_ =>(1,2147483646)
        };
        if value.is_empty()||value.len()>10||!value.bytes().all(|c|c.is_ascii_digit()){
            return false;
        }
        if let Ok(v)=value.parse::<usize>(){
            if lo<=v&&v<=hi{
                self.values[i]=v.to_string();
                return true;
            }
        }
        false
    }
}
pub struct Graph{
    pub name:String,
    pub settings:Settings,
    pub nodes:Vec<(usize,String)>,
    pub edges:Vec<(usize,usize)>,
    pub path:Option<(usize,usize)>,
    pub loops:usize,
    pub duplicates:usize,
    pub error:Option<(String,usize)>
}
pub fn read()->Vec<Graph>{
    let mut defaults=Settings::default();
    for line in fs::read_to_string("input/params.txt").unwrap().lines(){
        if !line.is_empty()&&!line.starts_with('#'){
            let a:Vec<_>=line.split(' ').collect();
            defaults.set(a[0],a[1]);
        }
    }
    let mut all=Vec::new();
    let mut current=None;
    let mut nodes:BTreeMap<usize,String>=BTreeMap::new();
    for(i,line)in fs::read_to_string("input/graphs.txt").unwrap().lines().enumerate(){
        if line.is_empty()||line.starts_with('#'){
            continue;
        }
        let a:Vec<_>=line.split(' ').collect();
        if a[0]=="GRAPH"{
            current=Some(Graph{
                name:a[1].into(),
                settings:defaults.clone(),
                nodes:Vec::new(),
                edges:Vec::new(),
                path:None,
                loops:0,
                duplicates:0,
                error:None
            });
            nodes.clear();
            continue;
        }
        let g=current.as_mut().unwrap();
        if a[0]=="END"{
            if g.error.is_none()&&nodes.is_empty(){
                g.error=Some(("no_nodes".into(),i+1));
            }
            g.nodes=nodes.iter().map(|(&id,label)|(id,label.clone())).collect();
            let mut g=current.take().unwrap();
            let numbering:BTreeMap<_,_>=g.nodes.iter().enumerate().map(|(i,(id,_))|(*id,i)).collect();
            if g.error.is_none(){
                g.edges=g.edges.iter().map(|(a,b)|(numbering[a],numbering[b])).collect();
                g.path=g.path.map(|(a,b)|(numbering[&a],numbering[&b]));
            }
            all.push(g);
            continue;
        }
        if g.error.is_some(){
            continue;
        }
        let error=match a[0]{
            "OPTION"=>if g.settings.set(a[1],a[2]){
                None
            }else{
                Some("bad_option")
            },"NODE"=>{
                let id=a[1].parse().unwrap();
                if nodes.contains_key(&id){
                    Some("duplicate_node")
                }else if nodes.len()==40{
                    Some("too_many_nodes")
                }else{
                    nodes.insert(id,a[2].to_string());
                    None
                }
            },"EDGE"=>{
                let u=a[1].parse().unwrap();
                let v=a[2].parse().unwrap();
                if !nodes.contains_key(&u)||!nodes.contains_key(&v){
                    Some("unknown_node")
                }else if u==v{
                    g.loops+=1;
                    None
                }else if g.edges.contains(&(u,v)){
                    g.duplicates+=1;
                    None
                }else{
                    g.edges.push((u,v));
                    None
                }
            },_=>{
                let u=a[1].parse().unwrap();
                let v=a[2].parse().unwrap();
                if !nodes.contains_key(&u)||!nodes.contains_key(&v){
                    Some("unknown_node")
                }else{
                    g.path=Some((u,v));
                    None
                }
            }
        };
        if let Some(error)=error{
            g.error=Some((error.into(),i+1));
        }
    }
    all
}
