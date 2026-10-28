use crate::policy::Communities;
use crate::topology::{Asn,Topology};
#[derive(Clone,Debug,PartialEq,Eq,PartialOrd,Ord)] pub struct Attribute {
    pub path:Vec<Asn>,
    pub origin:String,
    pub med:usize,
    pub communities:Communities
}
#[derive(Clone,Debug,PartialEq,Eq)] pub struct Route {
    pub attribute:Attribute,
    pub local_pref:usize,
    pub link:Option<usize>
}
impl Route{
    pub fn local(origin:String,communities:Communities)->Self{
        Self{
            attribute:Attribute{
                path:Vec::new(),
                origin,
                med:0,
                communities
            },
            local_pref:0,
            link:None
        }
    }
    pub fn neighbor(&self)->Asn{
        self.attribute.path[0]
    }
}
pub fn best(routes:&[Route],topology:&Topology)->(Route,&'static str){
    let mut k=routes.to_vec();
    if k.len()==1{
        return(k.remove(0),"ONLY");
    }
    for stage in 0..6{
        let key=|r:&Route|->i64{
            match stage{
                0=>-(r.local_pref as i64),1=>r.attribute.path.len() as i64,2=>match r.attribute.origin.as_str(){
                    "IGP"=>0,"EGP"=>1,_=>2
                },4=>topology.routers[&r.neighbor()] as i64,5=>r.link.unwrap() as i64,_=>0
            }
        };
        if stage==3{
            let original=k.clone();
            k.retain(|r|!original.iter().any(|s|s.neighbor()==r.neighbor()&&s.attribute.med<r.attribute.med));
        }else{
            let minimum=k.iter().map(key).min().unwrap();
            k.retain(|r|key(r)==minimum);
        }
        if k.len()==1{
            return(k.remove(0),["LOCALPREF","ASPATH","ORIGIN","MED","ROUTERID","LINK"][stage]);
        }
    }
    unreachable!()
}
