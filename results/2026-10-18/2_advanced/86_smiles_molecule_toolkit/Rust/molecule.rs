use std::collections::BTreeMap;
use std::fs;
#[derive(Clone)] pub struct Element{
    pub number:i32,
    pub mass:i64,
    pub valences:Vec<usize>
}
pub type Elements=BTreeMap<String,Element>;
pub fn elements()->Elements{
    let mut table=BTreeMap::new();
    for line in fs::read_to_string("input/elements.txt").unwrap().lines(){
        if line.is_empty()||line.starts_with('#'){
            continue;
        }
        let a:Vec<_>=line.split(' ').collect();
        table.insert(a[0].into(),Element{
            number:a[1].parse().unwrap(),
            mass:a[2].parse().unwrap(),
            valences:a[3].split(',').map(|s|s.parse().unwrap()).collect()
        });
    }
    table
}
#[derive(Clone)] pub struct Atom{
    pub element:String,
    pub aromatic:bool,
    pub mass:i32,
    pub charge:i32,
    pub hydrogens:usize,
    pub bracket:bool,
    pub column:usize
}
#[derive(Clone)] pub struct Bond{
    pub a:usize,
    pub b:usize,
    pub kind:u8,
    pub multiplicity:usize,
    pub ring:bool
}
#[derive(Clone,Default)] pub struct Molecule{
    pub atoms:Vec<Atom>,
    pub bonds:Vec<Bond>,
    pub neighbors:Vec<Vec<(usize,usize)>>,
    pub rings:Vec<Vec<usize>>
}
impl Molecule{
    pub fn rebuild(&mut self){
        self.bonds.sort_by_key(|b|(b.a,b.b));
        self.neighbors=vec![Vec::new();self.atoms.len()];
        for(i,b)in self.bonds.iter().enumerate(){
            self.neighbors[b.a].push((b.b,i));
            self.neighbors[b.b].push((b.a,i));
        }
        for n in &mut self.neighbors{
            n.sort();
        }
    }
    pub fn bond(&self,a:usize,b:usize)->Option<usize>{
        self.neighbors[a].iter().find(|&&(v,_)|v==b).map(|&(_,e)|e)
    }
    pub fn base(&self,i:usize)->usize{
        self.neighbors[i].iter().map(|&(_,e)|if self.bonds[e].kind==4{
            1
        }else{
            self.bonds[e].kind as usize
        }).sum()
    }
    pub fn multiplicity(&self,i:usize)->usize{
        self.neighbors[i].iter().map(|&(_,e)|self.bonds[e].multiplicity).sum()
    }
    pub fn needs_pi(&self,i:usize,elements:&Elements,hydrogens:bool)->bool{
        let a=&self.atoms[i];
        let hydrogen_count=if hydrogens { a.hydrogens } else { 0 };
        let required=self.base(i)+hydrogen_count+1;
        a.aromatic && elements[&a.element].valences[0] as i32+a.charge>=required as i32
    }
    pub fn organic_hydrogens(&self,i:usize,elements:&Elements)->Option<usize>{
        let b=self.multiplicity(i);
        elements[&self.atoms[i].element].valences.iter().copied().find(|&v|v>=b).map(|v|v-b)
    }
}
#[derive(Debug)] pub struct Error{
    pub reason:String,
    pub column:usize
}
impl Error{
    pub fn new(reason:&str,column:usize)->Self{
        Self{
            reason:reason.into(),
            column
        }
    }
}
