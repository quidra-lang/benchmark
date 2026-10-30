use std::cell::RefCell;
use std::rc::Rc;
use std::collections::{
    BTreeMap,
    BTreeSet,
    VecDeque
};
use crate::definitions::{
    Macro,
    Position,
    Diagnostic,
    builtin
};
use crate::lexer::{
    Token,
    single
};
pub type Definition = Rc<RefCell<Macro>>;
pub struct Expander {
    pub table: BTreeMap<String,
    Definition>,
    pub diagnostics: Vec<Diagnostic>,
    pub builtins: BTreeMap<String,
    usize>,
    pub counter: usize,
}
enum Item {
    Sequence(Vec<Token>),
    Paste(Token)
}
impl Expander {
    pub fn new() -> Self {
        Self {
            table: BTreeMap::new(),
            diagnostics: Vec::new(),
            builtins: ["__COUNTER__", "__FILE__", "__LINE__"].iter().map(|s| (s.to_string(), 0)).collect(),
            counter: 0
        }
    }
    pub fn diagnostic(&mut self, position: Position, kind: &'static str, message: String) {
        self.diagnostics.push(Diagnostic {
            position,
            kind,
            message
        });
    }
    fn expansion_error(&mut self, token: &Token, file: &str, offset: i64, message: String) {
        self.diagnostic(Position {
            file: file.into(),
            line: token.line + offset
        }, "error", message);
    }
    pub fn expand(&mut self, tokens: &[Token], file: &str, offset: i64) -> Vec<Token> {
        let mut input: VecDeque<Token> = tokens.iter().cloned().collect();
        let mut result = Vec::new();
        while let Some(token) = input.pop_front() {
            if token.kind != "identifier" || token.hide.contains(&token.text) {
                result.push(token);
                continue;
            }
            if builtin(&token.text) {
                *self.builtins.get_mut(&token.text).unwrap() += 1;
                let (kind, text) = match token.text.as_str() {
                    "__LINE__" => ("number", (token.line + offset).to_string()),
                    "__FILE__" => ("string", format!("\"{}\"", file)),
                    _ => {
                        let text = self.counter.to_string();
                        self.counter += 1;
                        ("number", text)
                    }
                };
                result.push(Token::new(kind, text, token.line, token.space));
                continue;
            }
            let definition = match self.table.get(&token.text) {
                Some(definition) => definition.clone(),
                None => {
                    result.push(token);
                    continue;
                }
            };
            let definition_value = definition.borrow().clone();
            let mut hide = token.hide.clone();
            let arguments = if definition_value.parameters.is_some() {
                if input.front().map_or(true, |t| t.text != "(") {
                    result.push(token);
                    continue;
                }
                match self.arguments(&definition_value, &input, &token, file, offset) {
                    Some((arguments, consumed, closing)) => {
                        hide = token.hide.intersection(&closing.hide).cloned().collect();
                        for _ in 0..consumed {
                            input.pop_front();
                        }
                        arguments
                    },
                    None => {
                        result.push(token);
                        continue;
                    }
                }
            } else {
                Vec::new()
            };
            hide.insert(definition_value.name.clone());
            let replacement = self.substitute(&definition_value, &arguments, &token, &hide, file, offset);
            definition.borrow_mut().expanded += 1;
            if replacement.is_empty() && token.space {
                if let Some(next) = input.front_mut() {
                    next.space = true;
                }
            }
            for token in replacement.into_iter().rev() {
                input.push_front(token);
            }
        }
        result
    }
    fn arguments(&mut self, definition: &Macro, input: &VecDeque<Token>, token: &Token, file: &str, offset: i64) -> Option<(Vec<Vec<Token>>, usize, Token)> {
        let mut arguments = vec![Vec::new()];
        let mut separators = Vec::new();
        let mut depth = 0i64;
        let mut closing = None;
        for (i, current) in input.iter().enumerate().skip(1) {
            if current.text == ")" && depth == 0 {
                closing = Some((i, current.clone()));
                break;
            }
            if current.text == "," && depth == 0 {
                separators.push(current.clone());
                arguments.push(Vec::new());
            }
            else {
                if current.text == "(" {
                    depth += 1;
                } else if current.text == ")" {
                    depth -= 1;
                }
                arguments.last_mut().unwrap().push(current.clone());
            }
        }
        let (end, closing) = match closing {
            Some(closing) => closing,
            None => {
                self.expansion_error(token, file, offset, format!("unterminated argument list invoking macro \"{}\"", definition.name));
                return None;
            }
        };
        let k = arguments.len();
        let parameters = definition.parameters.as_ref().unwrap();
        let n = parameters.len() - if definition.variadic {
            1
        } else {
            0
        };
        let empty_zero = !definition.variadic && n == 0 && k == 1 && arguments[0].is_empty();
        let message = if !definition.variadic && n == 0 && !empty_zero {
            Some(format!("macro \"{}\" passed {} arguments, but takes just 0", definition.name, k))
        }
        else if k < n {
            Some(format!("macro \"{}\" requires {} arguments, but only {} given", definition.name, n, k))
        }
        else if k > n && !definition.variadic {
            Some(format!("macro \"{}\" passed {} arguments, but takes just {}", definition.name, k, n))
        } else {
            None
        };
        if let Some(message) = message {
            self.expansion_error(token, file, offset, message);
            return None;
        }
        if definition.variadic {
            let mut variable = Vec::new();
            for i in n..k {
                if i > n {
                    variable.push(separators[i - 1].clone());
                }
                variable.extend(arguments[i].iter().cloned());
            }
            arguments.truncate(n);
            arguments.push(variable);
        } else if empty_zero {
            arguments.clear();
        }
        Some((arguments, end + 1, closing))
    }
    fn stringize(tokens: &[Token], template: &Token) -> Token {
        let mut text = String::new();
        for (i, token) in tokens.iter().enumerate() {
            if i > 0 && token.space {
                text.push(' ');
            }
            if token.kind == "string" || token.kind == "character" {
                text.push_str(&token.text.replace('\\', "\\\\").replace('"', "\\\""));
            }
            else {
                text.push_str(&token.text);
            }
        }
        Token::new("string", format!("\"{}\"", text), template.line, template.space)
    }
    fn paste(&mut self, left: Token, mut right: Token, invocation: &Token, file: &str, offset: i64) -> Vec<Token> {
        if left.kind == "placemarker" {
            right.space = left.space;
            return vec![right];
        }
        if right.kind == "placemarker" {
            return vec![left];
        }
        let text = left.text.clone() + &right.text;
        if let Some(kind) = single(&text) {
            let mut token = Token::new(kind, text, left.line, left.space);
            token.hide = left.hide.intersection(&right.hide).cloned().collect();
            vec![token]
        } else {
            self.expansion_error(invocation, file, offset, format!("pasting \"{}\" and \"{}\" does not give a valid preprocessing token", left.text, right.text));
            right.space = false;
            vec![left, right]
        }
    }
    fn substitute(&mut self, definition: &Macro, arguments: &[Vec<Token>], invocation: &Token, hide: &BTreeSet<String>, file: &str, offset: i64) -> Vec<Token> {
        let names = definition.parameters.clone().unwrap_or_default();
        let mut expanded: BTreeMap<usize,
        Vec<Token>> = BTreeMap::new();
        let mut items = Vec::new();
        let mut i = 0;
        while i < definition.replacement.len() {
            let token = &definition.replacement[i];
            if token.text == "#" && definition.parameters.is_some() {
                let parameter = names.iter().position(|name| *name == definition.replacement[i + 1].text).unwrap();
                items.push(Item::Sequence(vec![Self::stringize(&arguments[parameter], token)]));
                i += 2;
                continue;
            }
            if token.text == "##" {
                items.push(Item::Paste(token.clone()));
            }
            else if token.kind == "identifier" && names.contains(&token.text) {
                let parameter = names.iter().position(|name| *name == token.text).unwrap();
                let raw = (i > 0 && definition.replacement[i - 1].text == "##") || definition.replacement.get(i + 1).map_or(false, |t| t.text == "##");
                let mut sequence = if raw {
                    arguments[parameter].clone()
                } else {
                    if !expanded.contains_key(&parameter) {
                        let value = self.expand(&arguments[parameter], file, offset);
                        expanded.insert(parameter, value);
                    }
                    expanded[&parameter].clone()
                };
                if let Some(first) = sequence.first_mut() {
                    first.space = token.space;
                }
                else {
                    sequence.push(Token::new("placemarker", String::new(), token.line, token.space));
                }
                items.push(Item::Sequence(sequence));
            } else {
                items.push(Item::Sequence(vec![token.clone()]));
            }
            i += 1;
        }
        let mut output: Vec<Token> = Vec::new();
        let mut i = 0;
        while i < items.len() {
            match &items[i] {
                Item::Sequence(sequence) => output.extend(sequence.iter().cloned()),
                Item::Paste(_) => {
                    let left = output.pop().unwrap();
                    let mut right = match &items[i + 1] {
                        Item::Sequence(sequence) => sequence.clone(),
                        Item::Paste(token) => vec![token.clone()]
                    };
                    let first = right.remove(0);
                    output.extend(self.paste(left, first, invocation, file, offset));
                    output.extend(right);
                    i += 1;
                }
            }
            i += 1;
        }
        let mut result = Vec::new();
        let mut space = false;
        for mut token in output {
            if token.kind == "placemarker" {
                space |= token.space;
                continue;
            }
            if space {
                token.space = true;
                space = false;
            }
            token.line = invocation.line;
            token.hide.extend(hide.iter().cloned());
            result.push(token);
        }
        if let Some(first) = result.first_mut() {
            first.space = invocation.space;
        }
        result
    }
}
