use std::fs;
use crate::grid_map::{Cell,Path};
use crate::cbs::Conflict;
pub fn name(i:usize)->char{
    (b'A'+i as u8)as char
}
pub fn cell(c:Cell)->String{
    format!("{},{}",c.0,c.1)
}
pub fn conflict(c:&Conflict)->String{
    if c.vertex{
        format!("vertex t {} {} {} at {}",c.time,name(c.a),name(c.b),cell(c.v))
    }else{
        format!("edge t {} {} {} from {} to {}",c.time,name(c.a),name(c.b),cell(c.u),cell(c.v))
    }
}
pub fn actions(path:&Path)->String{
    path.windows(2).map(|w|match(w[1].0-w[0].0,w[1].1-w[0].1){
        (0,0)=>'.',(0,-1)=>'N',(1,0)=>'E',(0,1)=>'S',_=>'W'
    }).collect()
}
pub fn ratio(mut a:usize,mut b:usize)->String{
    let(x,y)=(a,b);
    while b!=0{
        let r=a%b;
        a=b;
        b=r;
    }
    format!("{}/{}",x/a,y/a)
}
pub fn csv(values:&[String])->String{
    values.join(",")
}
pub fn write(name:&str,lines:&[String]){
    fs::create_dir_all("output").unwrap();
    fs::write(format!("output/{}",name),if lines.is_empty(){
        String::new()
    }else{
        lines.join("\n")+"\n"
    }).unwrap();
}
