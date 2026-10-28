use std::fs;
use crate::decision::{Attribute,Route};
use crate::policy::community_text;
use crate::topology::{Asn,Topology};
pub fn path(p:&[Asn])->String{
    p.iter().map(usize::to_string).collect::<Vec<_>>().join(",")
}
pub fn attribute(a:&Attribute)->String{
    format!("path {} origin {} med {} comm {}",path(&a.path),a.origin,a.med,community_text(&a.communities))
}
pub fn route(r:Option<&Route>,t:&Topology)->String{
    match r{
        None=>"NONE".into(),Some(r)=>if let Some(l)=r.link{
            format!("next {} path {} link {} lp {} med {} origin {} comm {}",r.neighbor(),path(&r.attribute.path),t.links[l].name,r.local_pref,r.attribute.med,r.attribute.origin,community_text(&r.attribute.communities))
        }else{
            format!("LOCAL origin {} comm {}",r.attribute.origin,community_text(&r.attribute.communities))
        }
    }
}
pub fn write(name:&str,lines:&[String]){
    fs::create_dir_all("output").unwrap();
    let text=if lines.is_empty(){
        String::new()
    }else{
        lines.join("\n")+"\n"
    };
    fs::write(format!("output/{}",name),text).unwrap();
}
