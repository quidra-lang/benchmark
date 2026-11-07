use crate::parser::Node;
use crate::boxes::BoxNode;
pub struct Params{
    pub width:usize,
    pub indent:usize,
    pub rel:usize,
    pub binary:usize,
    pub punctuation:usize,
    pub col_gap:usize,
    pub row_gap:usize
}
pub fn types(n:&Node)->(usize,usize){
    match n{
        Node::Atom{
            kind,value,..
        }
        =>{
            let t=crate::boxes::atom_type(kind,value);
            (t,t)
        },Node::Delimited(..)=>(4,5),Node::Script(base,..)=>types(base),Node::Binary(name,_,base)if name=="overset"||name=="underset"=>types(base),_=>(0,0)
    }
}
pub fn word(n:&Node)->bool{
    match n{
        Node::Atom{
            kind,value,..
        }
        if kind=="command"=>{
            let name=value.strip_prefix('\\').unwrap();
            crate::lexer::GREEK.contains(&name)||name=="infty"
        },Node::Script(base,..)=>word(base),_=>false
    }
}
pub fn alphanumeric(n:&Node)->bool{
    if word(n){
        return true;
    }
    match n{
        Node::Atom{
            kind,..
        }
        =>kind=="identifier"||kind=="number",Node::Script(base,..)=>alphanumeric(base),Node::Accent(name,body)if ["overline","hat","vec","dot","tilde"].contains(&name.as_str())=>alphanumeric(body),_=>false
    }
}
pub fn spacing(nodes:&[Node],script:bool,p:&Params)->(Vec<(usize,usize)>,Vec<usize>){
    let mut t:Vec<_>=nodes.iter().map(types).collect();
    for i in 0..t.len(){
        if t[i].0==2&&(i==0||[1,2,3,4,6].contains(&t[i-1].1)){
            t[i]=(0,0);
        }
        if [3,5,6].contains(&t[i].0)&&i>0&&t[i-1].1==2{
            t[i-1]=(0,0);
        }
    }
    if let Some(last)=t.last_mut(){
        if last.1==2{
            *last=(0,0);
        }
    }
    let table=[[0,1,2,3,0,0,0],[1,1,0,3,0,0,0],[2,2,0,0,2,0,0],[3,3,0,0,3,0,0],[0,0,0,0,0,0,0],[0,1,2,3,0,0,0],[4,4,0,4,4,4,4]];
    let mut gaps=Vec::new();
    for i in 0..nodes.len().saturating_sub(1){
        let gap=if alphanumeric(&nodes[i])&&alphanumeric(&nodes[i+1])&&(word(&nodes[i])||word(&nodes[i+1])){
            1
        }else{
            match table[t[i].1][t[i+1].0]{
                0=>0,1=>1,2=>if script{
                    0
                }else{
                    p.binary
                },3=>if script{
                    0
                }else{
                    p.rel
                },_=>if script{
                    0
                }else{
                    p.punctuation
                }
            }
        };
        gaps.push(gap);
    }
    (t,gaps)
}
pub fn row(elements:Vec<BoxNode>,gaps:&[usize],description:&str,roles:&[String])->BoxNode{
    let ascent=elements.iter().map(|b|b.baseline).max().unwrap_or(0);
    let descent=elements.iter().map(|b|b.height-1-b.baseline).max().unwrap_or(0);
    let width=elements.iter().map(|b|b.width).sum::<usize>()+gaps.iter().sum::<usize>();
    let mut result=BoxNode::new(width,ascent+descent+1,ascent,description);
    let mut x=0;
    for(i,b)in elements.into_iter().enumerate(){
        let w=b.width;
        let y=ascent-b.baseline;
        result.child(b,x,y,roles.get(i).map_or("",String::as_str));
        x+=w+gaps.get(i).copied().unwrap_or(0);
    }
    result
}
