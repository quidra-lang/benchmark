use crate::{grammar_parser::nonterminal, first_follow::Sets, table::Table};

#[derive(Clone)]
pub struct Node {
    pub symbol: String,
    pub mark: Option<String>,
    pub children: Vec<usize>,
}

pub enum Action {
    Accept,
    Match(String),
    Predict(usize),
    Skip(String),
    Missing(String),
    Pop(String),
}

pub struct Trace {
    pub stack: Vec<String>,
    pub input: Vec<String>,
    pub position: usize,
    pub action: Action,
}

pub struct Parse {
    pub trace: Vec<Trace>,
    pub tree: Vec<Node>,
    pub left: Vec<usize>,
    pub matches: usize,
    pub max_stack: usize,
    pub skips: usize,
    pub pops: usize,
    pub missing: usize,
}

pub fn parse(start: &str, input: &[(String, usize)], table: &Table, sets: &Sets) -> Parse {
    let mut result = Parse { trace: Vec::new(), tree: vec![Node { symbol: start.into(), mark: None, children: Vec::new() }],
        left: Vec::new(), matches: 0, max_stack: 0, skips: 0, pops: 0, missing: 0 };
    let mut stack = vec![("$".to_owned(), None), (start.to_owned(), Some(0usize))];
    let mut current = 0;
    loop {
        let before = stack.iter().map(|(s, _)| s.clone()).collect::<Vec<_>>();
        result.max_stack = result.max_stack.max(stack.len());
        let (x, node) = stack.last().unwrap().clone();
        let a = &input[current].0;
        let action;
        let mut accept = false;
        let mut advance = false;
        if x == "$" && a == "$" {
            action = Action::Accept;
            accept = true;
        } else if x == "$" {
            action = Action::Skip(a.clone());
            result.skips += 1;
            advance = true;
        } else if !nonterminal(&x) {
            stack.pop();
            if x == *a { action = Action::Match(a.clone()); result.matches += 1; advance = true; }
            else { action = Action::Missing(x); result.tree[node.unwrap()].mark = Some("missing".into()); result.missing += 1; }
        } else if let Some(p) = table.chosen(&x, a) {
            stack.pop();
            let rhs = &table.productions[p].rhs;
            let parent = node.unwrap();
            if rhs.is_empty() {
                let index = result.tree.len();
                result.tree.push(Node { symbol: "%empty".into(), mark: None, children: Vec::new() });
                result.tree[parent].children.push(index);
            } else {
                let mut children = Vec::new();
                for symbol in rhs {
                    let index = result.tree.len();
                    result.tree.push(Node { symbol: symbol.clone(), mark: None, children: Vec::new() });
                    children.push(index);
                }
                for (&index, symbol) in children.iter().zip(rhs).rev() { stack.push((symbol.clone(), Some(index))); }
                result.tree[parent].children = children;
            }
            result.left.push(p);
            action = Action::Predict(p);
        } else if a == "$" || sets.follow[&x].contains(a) {
            stack.pop();
            result.tree[node.unwrap()].mark = Some("error".into());
            action = Action::Pop(x);
            result.pops += 1;
        } else {
            action = Action::Skip(a.clone());
            result.skips += 1;
            advance = true;
        }
        result.trace.push(Trace { stack: before, input: input[current..].iter().map(|(s, _)| s.clone()).collect(), position: input[current].1, action });
        if accept { break; }
        if advance { current += 1; }
    }
    result
}
