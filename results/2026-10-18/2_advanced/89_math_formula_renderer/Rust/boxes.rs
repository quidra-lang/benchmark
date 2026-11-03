#[derive(Clone)] pub struct BoxNode{
    pub width:usize,
    pub height:usize,
    pub baseline:usize,
    pub description:String,
    pub children:Vec<Child>,
    pub strings:Vec<(usize,usize,String)>
}
#[derive(Clone)] pub struct Child{
    pub role:String,
    pub x:usize,
    pub y:usize,
    pub node:BoxNode
}
impl BoxNode{
    pub fn new(width:usize,height:usize,baseline:usize,description:impl Into<String>)->Self{
        Self{
            width,
            height,
            baseline,
            description:description.into(),
            children:Vec::new(),
            strings:Vec::new()
        }
    }
    pub fn text(display:String,description:String)->Self{
        let mut b=Self::new(display.len(),1,0,description);
        b.strings.push((0,0,display));
        b
    }
    pub fn child(&mut self,node:BoxNode,x:usize,y:usize,role:&str){
        self.children.push(Child{
            role:role.into(),
            x,
            y,
            node
        });
    }
    pub fn string(&mut self,x:usize,y:usize,s:impl Into<String>){
        self.strings.push((x,y,s.into()));
    }
}
pub fn delimiter(s:&str,height:usize)->Vec<String>{
    if s=="."{
        return Vec::new();
    }
    let plain=match s{
        "\\{"=>"{","\\}"=>"}",_=>s
    };
    if height==1{
        return vec![plain.into()];
    }
    let mut glyph=vec![plain.to_string();height];
    if s=="("||s=="\\{"{
        glyph=vec!["|".into();height];
        glyph[0]="/".into();
        glyph[height-1]="\\".into();
        if s=="\\{"&&height>=3{
            glyph[(height-1)/2]="<".into();
        }
    }else if s==")"||s=="\\}"{
        glyph=vec!["|".into();height];
        glyph[0]="\\".into();
        glyph[height-1]="/".into();
        if s=="\\}"&&height>=3{
            glyph[(height-1)/2]=">".into();
        }
    }
    glyph
}
pub fn add_delimiter(b:&mut BoxNode,s:&str,x:usize){
    for(y,line)in delimiter(s,b.height).into_iter().enumerate(){
        b.string(x,y,line);
    }
}
pub fn large(name:&str)->Vec<String>{
    match name{
        "sum"=>vec!["\\--"," > ","/--"],"prod"=>vec!["___","| |","| |"],_=>vec![" /"," |","/ "]
    }.iter().map(|s|s.to_string()).collect()
}
pub fn atom_type(kind:&str,value:&str)->usize{
    if kind=="command"{
        return crate::lexer::symbol(value.strip_prefix('\\').unwrap()).unwrap().1;
    }
    if kind!="symbol"{
        return 0;
    }
    match value{
        "+"|"-"|"*"=>2,"="|"<"|">"|":"=>3,"("|"["=>4,")"|"]"|"!"=>5,","|";"=>6,_=>0
    }
}
