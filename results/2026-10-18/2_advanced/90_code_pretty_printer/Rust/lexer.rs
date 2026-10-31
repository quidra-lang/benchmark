#[derive(Clone,Debug)] pub struct Error{
    pub line:usize,
    pub column:usize,
    pub message:String
}
#[derive(Clone)] pub struct Comment{
    pub text:String,
    pub line:usize,
    pub column:usize,
    pub blank:usize,
    pub line_comment:bool,
    pub own:bool
}
#[derive(Clone)] pub struct Token{
    pub text:String,
    pub kind:String,
    pub line:usize,
    pub column:usize,
    pub blank:usize,
    pub leading:Vec<Comment>,
    pub trailing:Vec<Comment>
}
pub struct Lexed{
    pub tokens:Vec<Token>,
    pub comments:Vec<Comment>,
    pub order:Vec<(bool,usize)>
}
pub fn lex(lines:&[String])->Result<Lexed,Error>{
    let mut result=Lexed{
        tokens:Vec::new(),
        comments:Vec::new(),
        order:Vec::new()
    };
    let mut previous=0;
    for(row,line)in lines.iter().enumerate(){
        let a=line.as_bytes();
        let mut i=0;
        while i<a.len(){
            if a[i]==b' '{
                i+=1;
                continue;
            }
            let start=i;
            let line_number=row+1;
            let blank=line_number.saturating_sub(previous+1);
            let error=|message:String|Error{
                line:line_number,
                column:start+1,
                message
            };
            if line[i..].starts_with("//"){
                let text=line[i..].trim_end().to_string();
                result.order.push((false,result.comments.len()));
                result.comments.push(Comment{
                    text,
                    line:line_number,
                    column:i+1,
                    blank,
                    line_comment:true,
                    own:false
                });
                previous=line_number;
                break;
            }
            if line[i..].starts_with("/*"){
                let end=line[i+2..].find("*/").ok_or_else(||error("unterminated comment".into()))?+i+4;
                result.order.push((false,result.comments.len()));
                result.comments.push(Comment{
                    text:line[i..end].into(),
                    line:line_number,
                    column:i+1,
                    blank,
                    line_comment:false,
                    own:false
                });
                previous=line_number;
                i=end;
                continue;
            }
            let kind;
            if a[i].is_ascii_alphabetic()||a[i]==b'_'{
                i+=1;
                while i<a.len()&&(a[i].is_ascii_alphanumeric()||a[i]==b'_'){
                    i+=1;
                }
                let text=&line[start..i];
                kind=if ["int","float","bool","string","void","if","else","while","for","return","break","continue","true","false","switch","case","default"].contains(&text){
                    "keyword"
                }else{
                    "identifier"
                };
            }else if a[i].is_ascii_digit(){
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
                kind="number";
            }else if a[i]==b'"'{
                i+=1;
                let mut closed=false;
                while i<a.len(){
                    if a[i]==b'\\'{
                        i+=2;
                    }else if a[i]==b'"'{
                        i+=1;
                        closed=true;
                        break;
                    }else{
                        i+=1;
                    }
                }
                if !closed{
                    return Err(error("unterminated string".into()));
                }
                kind="string";
            }else if i+1<a.len()&&["<=",">=","==","!=","&&","||","+=","-=","*=","/=","%="].contains(&&line[i..i+2]){
                i+=2;
                kind="symbol";
            }else if b"+-*/%<>=!()[]{},;.?:".contains(&a[i]){
                i+=1;
                kind="symbol";
            }else{
                return Err(error(format!("unexpected character '{}'",a[i]as char)));
            }
            result.order.push((true,result.tokens.len()));
            result.tokens.push(Token{
                text:line[start..i].into(),
                kind:kind.into(),
                line:line_number,
                column:start+1,
                blank,
                leading:Vec::new(),
                trailing:Vec::new()
            });
            previous=line_number;
        }
    }
    result.tokens.push(Token{
        text:String::new(),
        kind:"end".into(),
        line:lines.len()+1,
        column:1,
        blank:0,
        leading:Vec::new(),
        trailing:Vec::new()
    });
    Ok(result)
}
