use std::cmp::Ordering;
use std::fmt;
use std::ops::{Add,Sub,Mul,Div};
use std::fs;
#[derive(Clone,Copy,Debug,Eq,PartialEq)] pub struct Fraction{
    pub n:i64,
    pub d:i64
}
impl Fraction{
    pub fn new(mut n:i64,mut d:i64)->Self{
        if d<0{
            n=-n;
            d=-d;
        }
        let(mut a,mut b)=(n.abs(),d);
        while b!=0{
            let r=a%b;
            a=b;
            b=r;
        }
        Self{
            n:n/a,
            d:d/a
        }
    }
    pub fn integer(n:i64)->Self{
        Self{
            n,
            d:1
        }
    }
}
impl Ord for Fraction{
    fn cmp(&self,b:&Self)->Ordering{
        ((self.n as i128)*(b.d as i128)).cmp(&((b.n as i128)*(self.d as i128)))
    }
}
impl PartialOrd for Fraction{
    fn partial_cmp(&self,b:&Self)->Option<Ordering>{
        Some(self.cmp(b))
    }
}
impl Add for Fraction{
    type Output=Self;
    fn add(self,b:Self)->Self{
        Self::new(self.n*b.d+b.n*self.d,self.d*b.d)
    }
}
impl Sub for Fraction{
    type Output=Self;
    fn sub(self,b:Self)->Self{
        Self::new(self.n*b.d-b.n*self.d,self.d*b.d)
    }
}
impl Mul for Fraction{
    type Output=Self;
    fn mul(self,b:Self)->Self{
        Self::new(self.n*b.n,self.d*b.d)
    }
}
impl Div for Fraction{
    type Output=Self;
    fn div(self,b:Self)->Self{
        Self::new(self.n*b.d,self.d*b.n)
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
pub fn bundle(mask:u16,names:&[String])->String{
    let values:Vec<_>=names.iter().enumerate().filter(|(i,_)|mask&(1<<i)!=0).map(|(_,s)|s.clone()).collect();
    if values.is_empty(){
        "-".into()
    }else{
        values.join("+")
    }
}
pub fn numbers(values:&[usize])->String{
    if values.is_empty(){
        "-".into()
    }else{
        values.iter().map(usize::to_string).collect::<Vec<_>>().join("+")
    }
}
pub fn write(name:&str,lines:&[String]){
    fs::create_dir_all("output").unwrap();
    fs::write(format!("output/{}",name),if lines.is_empty(){
        String::new()
    }else{
        lines.join("\n")+"\n"
    }).unwrap();
}
