#[derive(Clone)] pub struct Token{
    pub kind:String,
    pub value:String,
    pub column:usize
}
#[derive(Clone,Debug)] pub struct Error{
    pub column:usize,
    pub message:String
}
impl Error{
    pub fn new(column:usize,message:impl Into<String>)->Self{
        Self{
            column,
            message:message.into()
        }
    }
}
pub const GREEK:[&str;34]=["alpha","beta","gamma","delta","epsilon","zeta","eta","theta","iota","kappa","lambda","mu","nu","xi","pi","rho","sigma","tau","upsilon","phi","chi","psi","omega","Gamma","Delta","Theta","Lambda","Xi","Pi","Sigma","Upsilon","Phi","Psi","Omega"];
pub fn symbol(name:&str)->Option<(String,usize)>{
    if GREEK.contains(&name){
        return Some((name.into(),0));
    }
    let(display,kind)=match name{
        "cdot"=>("*",2),"times"=>("x",2),"pm"=>("+-",2),"mp"=>("-+",2),"leq"=>("<=",3),"geq"=>(">=",3),"neq"=>("!=",3),"approx"=>("~=",3),"to"=>("->",3),"infty"=>("oo",0),"ldots"|"cdots"=>("...",0),"quad"=>("  ",0),","=>(" ",0),"{"=>("{",4),"}"=>("}",5),"sin"|"cos"|"tan"|"log"|"ln"|"exp"|"det"|"lim"|"max"|"min"|"sum"|"prod"|"int"=>(name,1),_=>return None
    };
    Some((display.into(),kind))
}
pub fn command_name(s:&str)->bool{
    symbol(s).is_some()&&!s.is_empty()&&s.bytes().all(|c|c.is_ascii_alphabetic())
}
pub fn lex(text:&str)->Result<Vec<Token>,Error>{
    let a=text.as_bytes();
    let mut out=Vec::new();
    let mut i=0;
    while i<a.len(){
        let c=a[i];
        let column=i+1;
        let(kind,value);
        if c==b' '{
            i+=1;
            continue;
        }else if c.is_ascii_alphabetic(){
            let start=i;
            i+=1;
            while i<a.len()&&a[i].is_ascii_alphabetic(){
                i+=1;
            }
            kind="identifier".to_string();
            value=text[start..i].to_string();
        }else if c.is_ascii_digit(){
            let start=i;
            i+=1;
            while i<a.len()&&a[i].is_ascii_digit(){
                i+=1;
            }
            if i+1<a.len()&&a[i]==b'.'&&a[i+1].is_ascii_digit(){
                i+=2;
                while i<a.len()&&a[i].is_ascii_digit(){
                    i+=1;
                }
            }
            kind="number".into();
            value=text[start..i].into();
        }else if b"+-*/=<>:()[],;.!|'".contains(&c){
            kind="symbol".into();
            value=(c as char).to_string();
            i+=1;
        }else if b"{}^_&".contains(&c){
            kind=(c as char).to_string();
            value=kind.clone();
            i+=1;
        }else if c==b'\\'{
            i+=1;
            if i<a.len()&&a[i]==b'\\'{
                i+=1;
                kind="newline".into();
                value=String::new();
            }else if i<a.len()&&b"{},".contains(&a[i]){
                kind="command".into();
                value=format!("\\{}",a[i]as char);
                i+=1;
            }else{
                let start=i;
                while i<a.len()&&a[i].is_ascii_alphabetic(){
                    i+=1;
                }
                let name=&text[start..i];
                if name.is_empty(){
                    return Err(Error::new(column,"invalid command"));
                }
                if ["text","begin","end","tag","label","eqref"].contains(&name){
                    while i<a.len()&&a[i]==b' '{
                        i+=1;
                    }
                    if i==a.len()||a[i]!=b'{'{
                        return Err(Error::new(i+1,"expected {"));
                    }
                    let begin=i+1;
                    let end=(begin..a.len()).find(|&j|a[j]==b'}').ok_or_else(||Error::new(column,"unterminated argument"))?;
                    value=text[begin..end].into();
                    i=end+1;
                    kind=name.into();
                    if(name=="begin"||name=="end")&&!["matrix","pmatrix","bmatrix","vmatrix","cases"].contains(&value.as_str()){
                        return Err(Error::new(column,format!("unknown environment \"{}\"",value)));
                    }
                }else if symbol(name).is_some(){
                    kind="command".into();
                    value=format!("\\{}",name);
                }else if ["overline","hat","vec","dot","tilde","overbrace","underbrace"].contains(&name){
                    kind="accent".into();
                    value=name.into();
                }else if ["frac","binom","overset","underset","sqrt","left","right"].contains(&name){
                    kind=name.into();
                    value=String::new();
                }else{
                    return Err(Error::new(column,format!("unknown command \\{}",name)));
                }
            }
        }else{
            return Err(Error::new(column,format!("invalid character {}",c as char)));
        }
        out.push(Token{
            kind,
            value,
            column
        });
    }
    Ok(out)
}
