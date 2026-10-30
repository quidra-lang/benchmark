use crate::lexer::{
    Token,
    render
};
#[derive(Clone)]
pub struct Position {
    pub file: String,
    pub line: i64
}
impl Position {
    pub fn text(&self) -> String {
        format!("{}:{}", self.file, self.line)
    }
}
pub struct Diagnostic {
    pub position: Position,
    pub kind: &'static str,
    pub message: String
}
#[derive(Clone)]
pub struct Macro {
    pub name: String,
    pub parameters: Option<Vec<String>>,
    pub variadic: bool,
    pub replacement: Vec<Token>,
    pub position: Position,
    pub main: bool,
    pub expanded: usize,
    pub tested: usize,
}
impl Macro {
    pub fn signature(&self) -> String {
        if let Some(parameters) = &self.parameters {
            let mut parameters = parameters.clone();
            if self.variadic {
                *parameters.last_mut().unwrap() = "...".into();
            }
            format!("{}({})", self.name, parameters.join(", "))
        } else {
            self.name.clone()
        }
    }
    pub fn identical(&self, other: &Self) -> bool {
        self.parameters == other.parameters && self.variadic == other.variadic && self.replacement.len() == other.replacement.len() && self.replacement.iter().zip(&other.replacement).all(|(a, b)| a.text == b.text && a.space == b.space)
    }
    pub fn definition(&self) -> String {
        format!("#define {}{}", self.signature(), if self.replacement.is_empty() {
            String::new()
        } else {
            format!(" {}", render(&self.replacement, false))
        })
    }
}
pub fn builtin(name: &str) -> bool {
    ["__LINE__", "__FILE__", "__COUNTER__"].contains(&name)
}
pub fn check_name(tokens: &[Token], directive: &str) -> Result<String, String> {
    let token = tokens.first().ok_or_else(|| format!("no macro name given in #{} directive", directive))?;
    if token.kind != "identifier" {
        return Err("macro names must be identifiers".into());
    }
    if token.text == "defined" {
        return Err("\"defined\" cannot be used as a macro name".into());
    }
    if builtin(&token.text) {
        return Err(format!("cannot {} builtin macro \"{}\"", if directive == "define" {
            "redefine"
        } else {
            "undefine"
        }, token.text));
    }
    Ok(token.text.clone())
}
pub fn parse(tokens: &[Token], position: Position, main: bool) -> Result<Macro, String> {
    let name = check_name(tokens, "define")?;
    let va_error = "\"__VA_ARGS__\" can only appear in the expansion of a variadic macro";
    if name == "__VA_ARGS__" {
        return Err(va_error.into());
    }
    let mut i = 1;
    let mut parameters = None;
    let mut variadic = false;
    if tokens.get(1).map_or(false, |t| t.text == "(" && !t.space) {
        i = 2;
        let mut names = Vec::new();
        if tokens.get(i).map_or(false, |t| t.text == ")") {
            i += 1;
        }
        else {
            loop {
                let token = tokens.get(i).ok_or("missing ')' in macro parameter list")?;
                if token.text == "..." {
                    variadic = true;
                    names.push("__VA_ARGS__".into());
                }
                else if token.kind == "identifier" {
                    if token.text == "__VA_ARGS__" {
                        return Err(va_error.into());
                    }
                    if names.contains(&token.text) {
                        return Err(format!("duplicate macro parameter \"{}\"", token.text));
                    }
                    names.push(token.text.clone());
                } else {
                    return Err(format!("expected parameter name, found \"{}\"", token.text));
                }
                i += 1;
                let token = tokens.get(i).ok_or("missing ')' in macro parameter list")?;
                if token.text == ")" {
                    i += 1;
                    break;
                }
                if variadic {
                    return Err(format!("expected ')' after \"...\", found \"{}\"", token.text));
                }
                if token.text != "," {
                    return Err(format!("expected ',' or ')', found \"{}\"", token.text));
                }
                i += 1;
            }
        }
        parameters = Some(names);
    }
    let mut replacement = tokens[i..].to_vec();
    if let Some(first) = replacement.first_mut() {
        first.space = false;
    }
    if replacement.first().map_or(false, |t| t.text == "##") || replacement.last().map_or(false, |t| t.text == "##") {
        return Err("'##' cannot appear at either end of a macro expansion".into());
    }
    for (i, token) in replacement.iter().enumerate() {
        if token.kind == "identifier" && token.text == "__VA_ARGS__" && !variadic {
            return Err(va_error.into());
        }
        if token.text == "#" {
            if let Some(names) = &parameters {
                if !replacement.get(i + 1).map_or(false, |t| t.kind == "identifier" && names.contains(&t.text)) {
                    return Err("'#' is not followed by a macro parameter".into());
                }
            }
        }
    }
    Ok(Macro {
        name,
        parameters,
        variadic,
        replacement,
        position,
        main,
        expanded: 0,
        tested: 0
    })
}
