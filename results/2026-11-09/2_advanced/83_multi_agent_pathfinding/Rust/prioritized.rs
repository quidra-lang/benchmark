use crate::grid_map::{Grid,Path};
use crate::low_level::{self,Constraints,Counts};
use crate::report::name;
pub struct OrderResult{
    pub paths:Option<Vec<Path>>,
    pub planned:usize,
    pub failed:Option<usize>,
    pub expansions:usize,
    pub trace:Vec<String>,
    pub aborted:bool
}
pub fn plan(grid:&Grid,order:&[usize],number:usize,horizon:usize,count:&mut Counts)->OrderResult{
    let before=count.expansions;
    let mut constraints=Constraints::default();
    let mut paths=vec![Vec::new();grid.agents.len()];
    let mut trace=Vec::new();
    for(planned,&i)in order.iter().enumerate(){
        let old=count.expansions;
        let result=low_level::search(grid,i,grid.agents[i].start,0,horizon,false,&constraints,count);
        match result{
            Err(_)=>return OrderResult{
                paths:None,
                planned,
                failed:None,
                expansions:count.expansions-before,
                trace,
                aborted:true
            },Ok(None)=>{
                trace.push(format!("order {} agent {} failed expansions {}",number,name(i),count.expansions-old));
                return OrderResult{
                    paths:None,
                    planned,
                    failed:Some(i),
                    expansions:count.expansions-before,
                    trace,
                    aborted:false
                };
            },Ok(Some(path))=>{
                trace.push(format!("order {} agent {} cost {} expansions {}",number,name(i),path.len()-1,count.expansions-old));
                constraints.reserve(&path,0,true);
                paths[i]=path;
            }
        }
    }
    OrderResult{
        paths:Some(paths),
        planned:order.len(),
        failed:None,
        expansions:count.expansions-before,
        trace,
        aborted:false
    }
}
