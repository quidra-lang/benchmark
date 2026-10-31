use std::collections::BTreeMap;
use std::fs;
pub type Asn = usize;
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)] pub struct Prefix {
    pub address: u32,
    pub length: u8
}
pub fn address(text: &str) -> u32 {
    text.split('.').fold(0, |a,b| (a << 8) | b.parse::<u32>().unwrap())
}
pub fn address_text(a: u32) -> String {
    format!("{}.{}.{}.{}", a >> 24, (a >> 16) & 255, (a >> 8) & 255, a & 255)
}
impl Prefix {
    pub fn parse(s: &str) -> Self {
        let (a,n)=s.split_once('/').unwrap();
        Self{
            address:address(a),
            length:n.parse().unwrap()
        }
    }
    pub fn contains(&self, a: u32) -> bool {
        self.length == 0 || a >> (32-self.length) == self.address >> (32-self.length)
    }
    pub fn text(&self) -> String {
        format!("{}/{}",address_text(self.address),self.length)
    }
}
#[derive(Clone)] pub struct Link {
    pub name:String,
    pub a:Asn,
    pub b:Asn,
    pub peer:bool,
    pub delay:i64,
    pub mrai:i64,
    pub up:bool,
    pub downs:usize
}
impl Link {
    pub fn other(&self,x:Asn)->Asn{
        if x==self.a{
            self.b
        }else{
            self.a
        }
    }
    pub fn role(&self,x:Asn)->usize{
        if self.peer{
            1
        }else if x==self.a{
            0
        }else{
            2
        }
    }
    pub fn role_text(&self,x:Asn)->&'static str{
        ["customer","peer","provider"][self.role(x)]
    }
    pub fn symbol(&self,x:Asn)->char{
        ['D','P','U'][self.role(x)]
    }
}
pub struct Topology {
    pub routers:BTreeMap<Asn,u32>,
    pub links:Vec<Link>,
    pub initial:Vec<(Asn,Prefix,String,crate::policy::Communities)>
}
impl Topology {
    pub fn read()->Self{
        let mut t=Self{
            routers:BTreeMap::new(),
            links:Vec::new(),
            initial:Vec::new()
        };
        for line in fs::read_to_string("input/topology.txt").unwrap().lines(){
            let a:Vec<_>=line.split(' ').collect();
            match a[0]{
                "AS"=>{
                    t.routers.insert(a[1].parse().unwrap(),address(a[2]));
                },"LINK"=>t.links.push(Link{
                    name:a[1].into(),
                    a:a[2].parse().unwrap(),
                    b:a[3].parse().unwrap(),
                    peer:a[4]=="P2P",
                    delay:a[5].parse().unwrap(),
                    mrai:a[6].parse().unwrap(),
                    up:true,
                    downs:0
                }),_=>t.initial.push((a[1].parse().unwrap(),Prefix::parse(a[2]),a[3].into(),a[4..].iter().map(|v|crate::policy::community(v)).collect()))
            }
        }
        t
    }
    pub fn sessions(&self,x:Asn)->Vec<usize>{
        self.links.iter().enumerate().filter(|(_,l)|l.a==x||l.b==x).map(|(i,_)|i).collect()
    }
    pub fn connecting(&self,a:Asn,b:Asn)->&Link{
        self.links.iter().find(|l|(l.a==a&&l.b==b)||(l.a==b&&l.b==a)).unwrap()
    }
}
