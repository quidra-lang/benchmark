use std::fs;
use crate::expressions::{self,Expr};
pub struct Clause {
    pub reference: String,
    pub mandatory: bool,
    pub operator: String,
    pub literal: Expr
}
pub type Target = Vec<Vec<Vec<Clause>>>;
pub struct Attachment {
    pub advice: bool,
    pub effect: usize,
    pub id: String,
    pub arguments: Vec<(String,Expr)>
}
pub struct Element {
    pub kind: &'static str,
    pub id: String,
    pub algorithm: String,
    pub effect: usize,
    pub targets: Target,
    pub condition: Option<Expr>,
    pub attachments: Vec<Attachment>,
    pub children: Vec<usize>,
    pub parent: Option<usize>
}
pub fn read() -> Vec<Element> {
    let mut elements = Vec::<Element>::new();
    let mut stack = Vec::<usize>::new();
    for raw in fs::read_to_string("input/policies.txt").unwrap().lines() {
        let line = raw.trim_start_matches(' ');
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let w: Vec<_> = line.split_whitespace().collect();
        match w[0] {
            "POLICYSET" | "POLICY" | "RULE" => {
                let parent = stack.last().copied();
                let index = elements.len();
                if let Some(p) = parent {
                    elements[p].children.push(index);
                }
                elements.push(Element {
                    kind: if w[0] == "RULE" {
                        "rule"
                    } else if w[0] == "POLICY" {
                        "policy"
                    } else {
                        "policyset"
                    },
                    id: w[1].to_owned(),
                    algorithm: if w[0] == "RULE" {
                        String::new()
                    } else {
                        w[2].to_owned()
                    },
                    effect: usize::from(w[2] == "DENY"),
                    targets: Vec::new(),
                    condition: None,
                    attachments: Vec::new(),
                    children: Vec::new(),
                    parent
                });
                stack.push(index);
            }
            "END" => {
                stack.pop();
            }
            "TARGET" => {
                let alternatives = line[7..].split(" | ").map(|alternative| alternative.split(" & ").map(|clause| {
                    let parts: Vec<_> = clause.splitn(3,' ').collect();
                    let mandatory = parts[0].ends_with('!');
                    Clause {
                        reference: parts[0].trim_end_matches('!').to_owned(),
                        mandatory,
                        operator: parts[1].to_owned(),
                        literal: expressions::parse(parts[2])
                    }
                }).collect()).collect();
                elements[*stack.last().unwrap()].targets.push(alternatives);
            }
            "CONDITION" => elements[*stack.last().unwrap()].condition = Some(expressions::parse(&line[10..])), _ => {
                let parts: Vec<_> = line.splitn(4,' ').collect();
                let arguments = parts.get(3).map_or_else(Vec::new,|arguments| arguments.split(';').map(|argument| {
                    let (name,expression) = argument.trim().split_once('=').unwrap();
                    (name.to_owned(),expressions::parse(expression))
                }).collect());
                elements[*stack.last().unwrap()].attachments.push(Attachment {
                    advice: w[0] == "ADVICE",
                    effect: usize::from(w[1] == "DENY"),
                    id: w[2].to_owned(),
                    arguments
                });
            }
        }
    }
    elements
}
