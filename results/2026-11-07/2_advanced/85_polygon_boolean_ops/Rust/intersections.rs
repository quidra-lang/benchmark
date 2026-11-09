use crate::rational::{Point,Fraction,cross,gcd,x_cmp,y_cmp};
use std::cmp::Ordering;
pub fn on(a:Point,b:Point,p:Point)->bool{
    cross(a,b,p)==0&&x_cmp(p,a.min_by_x(b))!=Ordering::Less&&x_cmp(p,a.max_by_x(b))!=Ordering::Greater&&y_cmp(p,a.min_by_y(b))!=Ordering::Less&&y_cmp(p,a.max_by_y(b))!=Ordering::Greater
}
trait Bounds{
    fn min_by_x(self,b:Self)->Self;
    fn max_by_x(self,b:Self)->Self;
    fn min_by_y(self,b:Self)->Self;
    fn max_by_y(self,b:Self)->Self;
}
impl Bounds for Point{
    fn min_by_x(self,b:Self)->Self{
        if x_cmp(self,b).is_le(){
            self
        }else{
            b
        }
    }
    fn max_by_x(self,b:Self)->Self{
        if x_cmp(self,b).is_ge(){
            self
        }else{
            b
        }
    }
    fn min_by_y(self,b:Self)->Self{
        if y_cmp(self,b).is_le(){
            self
        }else{
            b
        }
    }
    fn max_by_y(self,b:Self)->Self{
        if y_cmp(self,b).is_ge(){
            self
        }else{
            b
        }
    }
}
pub fn touch(a:Point,b:Point,c:Point,d:Point)->bool{
    let opposite=|a:i128,b:i128|a.signum()*b.signum()<0;
    (opposite(cross(a,b,c),cross(a,b,d))&&opposite(cross(c,d,a),cross(c,d,b)))||on(a,b,c)||on(a,b,d)||on(c,d,a)||on(c,d,b)
}
pub fn overlap(a:Point,b:Point,c:Point,d:Point)->bool{
    if cross(a,b,c)!=0||cross(a,b,d)!=0{
        return false;
    }
    if x_cmp(a,b)!=Ordering::Equal{
        x_cmp(a.min_by_x(b).max_by_x(c.min_by_x(d)),a.max_by_x(b).min_by_x(c.max_by_x(d)))==Ordering::Less
    }else{
        y_cmp(a.min_by_y(b).max_by_y(c.min_by_y(d)),a.max_by_y(b).min_by_y(c.max_by_y(d)))==Ordering::Less
    }
}
fn line(a:Point,b:Point)->(i128,i128,i128){
    let(x,y,z)=(a.y*b.d-a.d*b.y,a.d*b.x-a.x*b.d,a.x*b.y-a.y*b.x);
    let g=gcd(gcd(x,y),z);
    (x/g,y/g,z/g)
}
pub fn line_intersection(a:Point,b:Point,c:Point,d:Point)->Point{
    let(x,y,z)=line(a,b);
    let(u,v,w)=line(c,d);
    Point::new(y*w-z*v,z*u-x*w,x*v-y*u)
}
pub fn crossing(a:Point,b:Point,c:Point,d:Point)->Option<(Point,Fraction,Fraction)>{
    let(rx,ry,sx,sy)=(b.x-a.x,b.y-a.y,d.x-c.x,d.y-c.y);
    let mut den=rx*sy-ry*sx;
    if den==0{
        return None;
    }
    let(gx,gy)=(c.x-a.x,c.y-a.y);
    let(mut nt,mut nu)=(gx*sy-gy*sx,gx*ry-gy*rx);
    if den<0{
        den=-den;
        nt=-nt;
        nu=-nu;
    }
    if nt<=0||nt>=den||nu<=0||nu>=den{
        return None;
    }
    Some((Point::new(a.x*den+nt*rx,a.y*den+nt*ry,den),Fraction::new(nt,den),Fraction::new(nu,den)))
}
pub fn segment(a:Point,b:Point)->String{
    format!("{}-{}",a,b)
}
