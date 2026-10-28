use std::collections::BTreeMap;
use crate::boxes::BoxNode;
pub fn paint(b:&BoxNode,x:usize,y:usize,grid:&mut[Vec<char>]){
    for &(dx,dy,ref text)in &b.strings{
        for(i,c)in text.chars().enumerate(){
            if c!=' '{
                grid[y+dy][x+dx+i]=c;
            }
        }
    }
    for child in &b.children{
        paint(&child.node,x+child.x,y+child.y,grid);
    }
}
pub fn describe(b:&BoxNode,x:usize,y:usize,level:usize,role:&str,lines:&mut Vec<String>,kinds:&mut BTreeMap<String,usize>,depth:&mut usize){
    lines.push(format!("{}{}{} x={} y={} w={} h={} b={}"," ".repeat(2*level),role,b.description,x,y,b.width,b.height,b.baseline));
    *kinds.entry(b.description.split(' ').next().unwrap().into()).or_default()+=1;
    *depth=(*depth).max(level+1);
    for child in &b.children{
        describe(&child.node,x+child.x,y+child.y,level+1,&child.role,lines,kinds,depth);
    }
}
pub fn lines(grid:&[Vec<char>])->Vec<String>{
    grid.iter().map(|r|r.iter().collect::<String>().trim_end().to_string()).collect()
}
