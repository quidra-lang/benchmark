use std::cmp::Ordering;
use std::fmt;
pub fn gcd(mut a:i128,mut b:i128)->i128{
    a=a.abs();
    b=b.abs();
    while b!=0{
        let r=a%b;
        a=b;
        b=r;
    }
    a
}
#[derive(Clone,Copy,Debug,Eq,PartialEq)] pub struct Fraction{
    pub n:i128,
    pub d:i128
}
impl Fraction{
    pub fn new(mut n:i128,mut d:i128)->Self{
        if d<0{
            n=-n;
            d=-d;
        }
        let g=gcd(n,d);
        Self{
            n:n/g,
            d:d/g
        }
    }
}
impl Ord for Fraction{
    fn cmp(&self,b:&Self)->Ordering{
        (self.n*b.d).cmp(&(b.n*self.d))
    }
}
impl PartialOrd for Fraction{
    fn partial_cmp(&self,b:&Self)->Option<Ordering>{
        Some(self.cmp(b))
    }
}
impl fmt::Display for Fraction{
    fn fmt(&self,f:&mut fmt::Formatter<'_>)->fmt::Result{
        if self.d==1{
            write!(f,"{}",self.n)
        }else{
            write!(f,"{}/{}",self.n,self.d)
        }
    }
}
#[derive(Clone,Copy,Debug,Eq,PartialEq)] pub struct Point{
    pub x:i128,
    pub y:i128,
    pub d:i128
}
impl Point{
    pub fn new(mut x:i128,mut y:i128,mut d:i128)->Self{
        if d<0{
            x=-x;
            y=-y;
            d=-d;
        }
        let g=gcd(gcd(x,y),d);
        Self{
            x:x/g,
            y:y/g,
            d:d/g
        }
    }
    pub fn integer(x:i128,y:i128)->Self{
        Self{
            x,
            y,
            d:1
        }
    }
    pub fn real(self)->(f64,f64){
        (self.x as f64/self.d as f64,self.y as f64/self.d as f64)
    }
    pub fn snap(self)->Self{
        Self::integer((2*self.x+self.d).div_euclid(2*self.d),(2*self.y+self.d).div_euclid(2*self.d))
    }
}
impl Ord for Point{
    fn cmp(&self,b:&Self)->Ordering{
        (self.y*b.d).cmp(&(b.y*self.d)).then((self.x*b.d).cmp(&(b.x*self.d)))
    }
}
impl PartialOrd for Point{
    fn partial_cmp(&self,b:&Self)->Option<Ordering>{
        Some(self.cmp(b))
    }
}
impl fmt::Display for Point{
    fn fmt(&self,f:&mut fmt::Formatter<'_>)->fmt::Result{
        write!(f,"({},{})",Fraction::new(self.x,self.d),Fraction::new(self.y,self.d))
    }
}
pub fn cross(a:Point,b:Point,c:Point)->i128{
    (b.x*c.y-b.y*c.x)*a.d+(c.x*a.y-c.y*a.x)*b.d+(a.x*b.y-a.y*b.x)*c.d
}
pub fn x_cmp(a:Point,b:Point)->Ordering{
    (a.x*b.d).cmp(&(b.x*a.d))
}
pub fn y_cmp(a:Point,b:Point)->Ordering{
    (a.y*b.d).cmp(&(b.y*a.d))
}
