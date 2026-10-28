use crate::rational::Point;
use crate::rings::{self,Region,Rings};
pub fn draw(region:&Region,operands:Option<&(Rings,Rings)>,values:&[i128])->(Vec<String>,[usize;4]){
    let(x,y,cw,ch,cols,rows)=(values[0],values[1],values[2],values[3],values[4],values[5]);
    let all:Vec<_>=region.iter().flat_map(|p|p.iter().cloned()).collect();
    let mut lines=Vec::new();
    let mut counts=[0;4];
    for j in 0..rows{
        let mut line=String::new();
        for i in 0..cols{
            let p=Point::new(2*x+(2*i+1)*cw,2*y+(2*(rows-1-j)+1)*ch,2);
            let c=if rings::interior(p,&all){
                counts[0]+=1;
                '#'
            }else if let Some((a,b))=operands{
                match(rings::interior(p,a),rings::interior(p,b)){
                    (true,true)=>{
                        counts[3]+=1;
                        '+'
                    },(true,false)=>{
                        counts[1]+=1;
                        'a'
                    },(false,true)=>{
                        counts[2]+=1;
                        'b'
                    },_=>'.'
                }
            }else{
                '.'
            };
            line.push(c);
        }
        lines.push(line);
    }
    (lines,counts)
}
