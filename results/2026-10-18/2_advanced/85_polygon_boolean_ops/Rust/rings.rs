use crate::rational::{Point,cross};
use crate::intersections;
pub type Ring=Vec<Point>;
pub type Rings=Vec<Ring>;
pub type Region=Vec<Rings>;
pub fn inside(p:Point,r:&Ring)->bool{
    let mut odd=false;
    for i in 0..r.len(){
        let(a,b)=(r[i],r[(i+1)%r.len()]);
        if(a.y*p.d>p.y*a.d)!=(b.y*p.d>p.y*b.d){
            let(lo,hi)=if a.y*b.d<b.y*a.d{
                (a,b)
            }else{
                (b,a)
            };
            if cross(lo,hi,p)>0{
                odd=!odd;
            }
        }
    }
    odd
}
pub fn interior(p:Point,rings:&[Ring])->bool{
    rings.iter().filter(|r|inside(p,r)).count()%2==1
}
pub fn boundary(p:Point,r:&Ring)->bool{
    (0..r.len()).any(|i|intersections::on(r[i],r[(i+1)%r.len()],p))
}
pub fn rotate(r:&mut Ring){
    let k=r.iter().enumerate().min_by_key(|(_,p)|**p).unwrap().0;
    r.rotate_left(k);
}
pub fn ccw(r:&Ring)->bool{
    cross(r[r.len()-1],r[0],r[1])>0
}
pub fn reverse(r:&mut Ring){
    r[1..].reverse();
}
pub fn canonical(mut rings:Rings)->Rings{
    for(i,r)in rings.iter_mut().enumerate(){
        rotate(r);
        if ccw(r)!=(i==0){
            reverse(r);
        }
    }
    rings[1..].sort_by_key(|r|r[0]);
    rings
}
pub fn assemble(mut rings:Rings)->Region{
    for r in &mut rings{
        rotate(r);
    }
    let depth:Vec<_>=rings.iter().enumerate().map(|(i,r)|rings.iter().enumerate().filter(|(j,q)|i!=*j&&inside(r[0],q)).count()).collect();
    for(i,r)in rings.iter_mut().enumerate(){
        if ccw(r)!=(depth[i]%2==0){
            reverse(r);
        }
    }
    let mut outers:Vec<_>=(0..rings.len()).filter(|&i|depth[i]%2==0).collect();
    outers.sort_by_key(|&i|rings[i][0]);
    outers.iter().map(|&i|{
        let mut holes:Vec<_>=(0..rings.len()).filter(|&j|depth[j]==depth[i]+1&&inside(rings[j][0],&rings[i])).collect();
        holes.sort_by_key(|&j|rings[j][0]);
        let mut polygon=vec![rings[i].clone()];
        polygon.extend(holes.into_iter().map(|j|rings[j].clone()));
        polygon
    }).collect()
}
pub fn area(r:&Ring)->f64{
    let mut sum=0.0;
    for i in 0..r.len(){
        let(x,y)=r[i].real();
        let(u,v)=r[(i+1)%r.len()].real();
        sum+=x*v-u*y;
    }
    sum/2.0
}
pub fn perimeter(r:&Ring)->f64{
    let mut sum=0.0;
    for i in 0..r.len(){
        let(x,y)=r[i].real();
        let(u,v)=r[(i+1)%r.len()].real();
        let(dx,dy)=(u-x,v-y);
        sum+=(dx*dx+dy*dy).sqrt();
    }
    sum
}
pub fn total_area(region:&Region)->f64{
    let mut a=0.0;
    for p in region{
        for r in p{
            a+=area(r);
        }
    }
    a
}
