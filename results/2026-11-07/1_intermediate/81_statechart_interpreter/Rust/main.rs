use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::io::{self, Read};

#[derive(Clone)]
struct Expr {
    op: String,
    text: String,
    args: Vec<Expr>,
}

struct Expression<'a> {
    tokens: Vec<String>,
    at: usize,
    variables: &'a BTreeMap<String, i64>,
    states: &'a BTreeMap<String, usize>,
}

impl<'a> Expression<'a> {
    fn new(
        text: &str,
        variables: &'a BTreeMap<String, i64>,
        states: &'a BTreeMap<String, usize>,
    ) -> Self {
        let b = text.as_bytes();
        let mut i = 0;
        let mut tokens = Vec::new();
        while i < b.len() {
            if b[i] == b' ' {
                i += 1;
                continue;
            }
            let start = i;
            if b[i].is_ascii_digit() {
                while i < b.len() && b[i].is_ascii_digit() {
                    i += 1;
                }
            } else if b[i].is_ascii_alphabetic() || b[i] == b'_' {
                while i < b.len() && (b[i].is_ascii_alphanumeric() || b[i] == b'_') {
                    i += 1;
                }
            } else {
                i += 1;
                if i < b.len()
                    && ["||", "&&", "==", "!=", "<=", ">="].contains(&&text[start..i + 1])
                {
                    i += 1;
                }
            }
            tokens.push(text[start..i].into());
        }
        Self {
            tokens,
            at: 0,
            variables,
            states,
        }
    }

    fn parse(&mut self, level: usize) -> Result<Expr, String> {
        if level == 5 {
            let t = self.tokens[self.at].clone();
            self.at += 1;
            if t == "!" || t == "-" {
                return Ok(Expr {
                    op: format!("unary{}", t),
                    text: String::new(),
                    args: vec![self.parse(5)?],
                });
            }
            if t == "(" {
                let e = self.parse(0)?;
                self.at += 1;
                return Ok(e);
            }
            if t.as_bytes()[0].is_ascii_digit() {
                return Ok(Expr {
                    op: "number".into(),
                    text: t,
                    args: Vec::new(),
                });
            }
            if t == "in" {
                self.at += 1;
                let name = self.tokens[self.at].clone();
                self.at += 2;
                if !self.states.contains_key(&name) {
                    return Err(format!("unknown state {}", name));
                }
                return Ok(Expr {
                    op: "in".into(),
                    text: name,
                    args: Vec::new(),
                });
            }
            if t != "_data" && !self.variables.contains_key(&t) {
                return Err(format!("unknown variable {}", t));
            }
            return Ok(Expr {
                op: "variable".into(),
                text: t,
                args: Vec::new(),
            });
        }
        let operators: &[&str] = match level {
            0 => &["||"],
            1 => &["&&"],
            2 => &["==", "!=", "<", "<=", ">", ">="],
            3 => &["+", "-"],
            _ => &["*", "/", "%"],
        };
        let mut left = self.parse(level + 1)?;
        while self.at < self.tokens.len() && operators.contains(&self.tokens[self.at].as_str()) {
            let op = self.tokens[self.at].clone();
            self.at += 1;
            left = Expr {
                op,
                text: String::new(),
                args: vec![left, self.parse(level + 1)?],
            };
        }
        Ok(left)
    }
}

#[derive(Clone)]
struct Action {
    kind: String,
    name: String,
    expr: Option<Expr>,
    text: Option<String>,
    delay: i64,
}

struct State {
    id: String,
    kind: String,
    parent: usize,
    children: Vec<usize>,
    initial_name: Option<String>,
    deep: bool,
    default_name: Option<String>,
    entries: Vec<Vec<Action>>,
    exits: Vec<Vec<Action>>,
    transitions: Vec<usize>,
    depth: usize,
    initial: usize,
    default: usize,
    history: Option<Vec<usize>>,
    entered: usize,
    taken: usize,
    dwell: i64,
    entry_time: i64,
}

impl State {
    fn new(id: String, kind: String, parent: usize) -> Self {
        Self {
            id,
            kind,
            parent,
            children: Vec::new(),
            initial_name: None,
            deep: false,
            default_name: None,
            entries: Vec::new(),
            exits: Vec::new(),
            transitions: Vec::new(),
            depth: 0,
            initial: 0,
            default: 0,
            history: None,
            entered: 0,
            taken: 0,
            dwell: 0,
            entry_time: 0,
        }
    }
}

#[derive(Clone)]
struct Transition {
    source: usize,
    trigger: String,
    descriptors: Vec<String>,
    delay: i64,
    guard: Option<Expr>,
    target: Option<usize>,
    mode: String,
    actions: Vec<Action>,
}

struct Definition {
    line: usize,
    text: String,
    node: Option<usize>,
}

#[derive(Clone)]
struct Event {
    name: String,
    value: i64,
}

impl Event {
    fn new(name: impl Into<String>, value: i64) -> Self {
        Self {
            name: name.into(),
            value,
        }
    }
}

#[derive(Clone)]
struct Reservation {
    due: i64,
    creation: usize,
    transition: Option<usize>,
    event: Option<Event>,
}

struct Trigger {
    kind: &'static str,
    event: Option<Event>,
    transition: Option<usize>,
}

impl Trigger {
    fn kind(kind: &'static str) -> Self {
        Self {
            kind,
            event: None,
            transition: None,
        }
    }

    fn event(event: Event) -> Self {
        Self {
            kind: "event",
            event: Some(event),
            transition: None,
        }
    }
}

struct Selected {
    transition: usize,
    scope: Option<usize>,
    exits: BTreeSet<usize>,
}

struct Chart {
    output: Vec<String>,
    states: Vec<State>,
    ids: BTreeMap<String, usize>,
    variables: BTreeMap<String, i64>,
    transitions: Vec<Transition>,
    document: Vec<usize>,
    active: BTreeSet<usize>,
    queue: VecDeque<Event>,
    reservations: Vec<Reservation>,
    time: i64,
    data: i64,
    trace: bool,
    halted: bool,
    macros: usize,
    micros: usize,
    creation: usize,
}

impl Chart {
    fn new() -> Self {
        Self {
            output: Vec::new(),
            states: vec![State::new(String::new(), "root".into(), 0)],
            ids: BTreeMap::new(),
            variables: BTreeMap::new(),
            transitions: Vec::new(),
            document: Vec::new(),
            active: BTreeSet::new(),
            queue: VecDeque::new(),
            reservations: Vec::new(),
            time: 0,
            data: 0,
            trace: false,
            halted: false,
            macros: 0,
            micros: 0,
            creation: 0,
        }
    }

    fn children(&self, i: usize) -> Vec<usize> {
        self.states[i]
            .children
            .iter()
            .copied()
            .filter(|c| self.states[*c].kind != "history")
            .collect()
    }

    fn compound(&self, i: usize) -> bool {
        i == 0 || self.states[i].kind == "state" && !self.children(i).is_empty()
    }

    fn parallel(&self, i: usize) -> bool {
        self.states[i].kind == "parallel" && !self.children(i).is_empty()
    }

    fn atomic(&self, i: usize) -> bool {
        self.states[i].kind != "history" && self.children(i).is_empty()
    }

    fn descendant(&self, child: usize, ancestor: usize) -> bool {
        let mut i = child;
        while i != 0 {
            i = self.states[i].parent;
            if i == ancestor {
                return true;
            }
        }
        false
    }

    fn expression(&self, text: &str) -> Result<Expr, String> {
        Expression::new(text, &self.variables, &self.ids).parse(0)
    }

    fn actions(&self, text: &str) -> Result<Vec<Action>, String> {
        let mut result = Vec::new();
        for raw in text.split("; ") {
            let w: Vec<&str> = raw.split(' ').collect();
            let mut a = Action {
                kind: w[0].into(),
                name: String::new(),
                expr: None,
                text: None,
                delay: 0,
            };
            match w[0] {
                "raise" => {
                    a.name = w[1].into();
                    if w.len() > 2 {
                        a.expr = Some(self.expression(&w[2..].join(" "))?);
                    }
                }
                "send" => {
                    a.name = w[1].into();
                    a.delay = w[2].parse().unwrap();
                    if w.len() > 3 {
                        a.expr = Some(self.expression(&w[3..].join(" "))?);
                    }
                }
                "cancel" => a.name = w[1].into(),
                "log" => {
                    let rest = &raw[4..];
                    if rest.starts_with('"') {
                        let end = rest[1..].find('"').unwrap() + 1;
                        a.text = Some(rest[1..end].into());
                        if end + 1 < rest.len() {
                            a.expr = Some(self.expression(&rest[end + 2..])?);
                        }
                    } else {
                        a.expr = Some(self.expression(rest)?);
                    }
                }
                _ => {
                    if !self.variables.contains_key(w[0]) {
                        return Err(format!("unknown variable {}", w[0]));
                    }
                    a.kind = "assign".into();
                    a.name = w[0].into();
                    a.expr = Some(self.expression(&w[2..].join(" "))?);
                }
            }
            result.push(a);
        }
        Ok(result)
    }

    fn definition(&mut self, d: &Definition) -> Result<(), String> {
        let w: Vec<&str> = d.text.split(' ').collect();
        if w[0] == "state" {
            if let Some(i) = d.node {
                if let Some(name) = &self.states[i].initial_name {
                    let child = *self
                        .ids
                        .get(name)
                        .ok_or_else(|| format!("unknown state {}", name))?;
                    if self.states[child].parent != i || self.states[child].kind == "history" {
                        return Err(format!("{} is not a child of {}", name, self.states[i].id));
                    }
                }
            }
        }
        if w[0] == "final" || w[0] == "history" {
            let s = &self.states[d.node.unwrap()];
            let p = &self.states[s.parent];
            if p.kind != "state" || self.children(s.parent).is_empty() {
                return Err(format!("{} needs a compound parent", s.id));
            }
            if let Some(name) = &s.default_name {
                let target = *self
                    .ids
                    .get(name)
                    .ok_or_else(|| format!("unknown state {}", name))?;
                if !self.descendant(target, s.parent) || self.states[target].kind == "history" {
                    return Err(format!("{} is not a descendant of {}", name, p.id));
                }
            }
        }
        if w[0] == "entry" || w[0] == "exit" {
            let i = *self
                .ids
                .get(w[1])
                .ok_or_else(|| format!("unknown state {}", w[1]))?;
            if self.states[i].kind == "history" {
                return Err(format!("{} cannot have actions", w[1]));
            }
            let a = self.actions(d.text.split_once(" / ").unwrap().1)?;
            if w[0] == "entry" {
                self.states[i].entries.push(a);
            } else {
                self.states[i].exits.push(a);
            }
        }
        if w[0] == "on" {
            let source = *self
                .ids
                .get(w[1])
                .ok_or_else(|| format!("unknown state {}", w[1]))?;
            if ["final", "history"].contains(&self.states[source].kind.as_str()) {
                return Err(format!("{} cannot have transitions", w[1]));
            }
            let mut rest = &d.text[4 + w[1].len()..];
            let trigger;
            let mut delay = 0;
            let mut descriptors = Vec::new();
            if rest.starts_with("after ") {
                rest = &rest[6..];
                let word = rest.split(' ').next().unwrap();
                delay = word.parse().unwrap();
                rest = rest[word.len()..].trim_start_matches(' ');
                trigger = "timer";
            } else {
                let word = rest.split(' ').next().unwrap();
                rest = rest[word.len()..].trim_start_matches(' ');
                trigger = if word == "always" { "always" } else { "event" };
                if trigger == "event" {
                    descriptors = word.split('|').map(str::to_string).collect();
                }
            }
            let mut guard = None;
            if rest.starts_with('[') {
                let end = rest.find(']').unwrap();
                guard = Some(self.expression(&rest[1..end])?);
                rest = rest[end + 1..].trim_start_matches(' ');
            }
            let mut target = None;
            let mut mode = "internal";
            if rest.starts_with("-> ") || rest.starts_with("~> ") {
                mode = if rest.starts_with('-') {
                    "external"
                } else {
                    "local"
                };
                rest = &rest[3..];
                let name = rest.split(' ').next().unwrap();
                target = Some(
                    *self
                        .ids
                        .get(name)
                        .ok_or_else(|| format!("unknown state {}", name))?,
                );
                rest = rest[name.len()..].trim_start_matches(' ');
            }
            let actions = if rest.starts_with("/ ") {
                self.actions(&rest[2..])?
            } else {
                Vec::new()
            };
            self.states[source].transitions.push(self.transitions.len());
            self.transitions.push(Transition {
                source,
                trigger: trigger.into(),
                descriptors,
                delay,
                guard,
                target,
                mode: mode.into(),
                actions,
            });
        }
        Ok(())
    }

    fn define(&mut self, lines: &[(usize, &str)]) -> bool {
        let mut errors = BTreeMap::new();
        let mut definitions = Vec::new();
        for &(line, text) in lines {
            let w: Vec<&str> = text.split(' ').collect();
            let mut node = None;
            if ["state", "parallel", "final", "history"].contains(&w[0]) {
                let parent_name = if w.len() > 2 && w[2] != "initial" {
                    Some(w[2])
                } else {
                    None
                };
                let reason = if self.ids.contains_key(w[1]) {
                    Some(format!("duplicate state {}", w[1]))
                } else if parent_name.is_some_and(|p| !self.ids.contains_key(p)) {
                    Some(format!("unknown state {}", parent_name.unwrap()))
                } else if parent_name.is_some_and(|p| {
                    ["final", "history"].contains(&self.states[self.ids[p]].kind.as_str())
                }) {
                    Some(format!("{} cannot have children", parent_name.unwrap()))
                } else {
                    None
                };
                if let Some(reason) = reason {
                    errors.insert(line, reason);
                } else {
                    let parent = parent_name.map_or(0, |p| self.ids[p]);
                    let mut s = State::new(w[1].into(), w[0].into(), parent);
                    if let Some(at) = w.iter().position(|s| *s == "initial") {
                        s.initial_name = Some(w[at + 1].into());
                    }
                    s.deep = w[0] == "history" && w[3] == "deep";
                    if w[0] == "history" && w.len() == 5 {
                        s.default_name = Some(w[4].into());
                    }
                    s.depth = self.states[parent].depth + 1;
                    let i = self.states.len();
                    node = Some(i);
                    self.ids.insert(s.id.clone(), i);
                    self.states.push(s);
                    self.states[parent].children.push(i);
                }
            } else if w[0] == "var" {
                if self.variables.contains_key(w[1]) {
                    errors.insert(line, format!("duplicate variable {}", w[1]));
                } else {
                    self.variables.insert(w[1].into(), w[2].parse().unwrap());
                }
            }
            definitions.push(Definition {
                line,
                text: text.into(),
                node,
            });
        }
        for d in &definitions {
            if !errors.contains_key(&d.line) {
                if let Err(reason) = self.definition(d) {
                    errors.insert(d.line, reason);
                }
            }
        }
        if !errors.is_empty() {
            for (line, reason) in errors {
                self.output.push(format!("error line {}: {}", line, reason));
            }
            return false;
        }
        for i in 0..self.states.len() {
            if self.compound(i) {
                self.states[i].initial = self.states[i]
                    .initial_name
                    .as_ref()
                    .map_or_else(|| self.children(i)[0], |n| self.ids[n]);
            }
            if self.states[i].kind == "history" {
                self.states[i].default = self.states[i]
                    .default_name
                    .as_ref()
                    .map_or(self.states[self.states[i].parent].initial, |n| self.ids[n]);
            }
        }

        fn visit(i: usize, states: &[State], document: &mut Vec<usize>) {
            document.push(i);
            for &c in &states[i].children {
                visit(c, states, document);
            }
        }
        for &i in &self.states[0].children {
            visit(i, &self.states, &mut self.document);
        }
        true
    }

    fn warnings(&mut self) {
        let mut reached = BTreeSet::from([self.states[0].initial]);
        loop {
            let before = reached.len();
            for i in reached.clone() {
                if self.states[i].parent != 0 {
                    reached.insert(self.states[i].parent);
                }
                if self.compound(i) {
                    reached.insert(self.states[i].initial);
                }
                if self.parallel(i) {
                    reached.extend(self.children(i));
                }
                for &index in &self.states[i].transitions {
                    if let Some(t) = self.transitions[index].target {
                        reached.insert(if self.states[t].kind == "history" {
                            self.states[t].default
                        } else {
                            t
                        });
                    }
                }
            }
            if before == reached.len() {
                break;
            }
        }
        for &i in &self.document {
            if self.states[i].kind != "history" && !reached.contains(&i) {
                self.output
                    .push(format!("warning: unreachable state {}", self.states[i].id));
            }
        }
    }

    fn evaluate(&self, e: &Expr) -> Result<i64, ()> {
        if e.op == "number" {
            return Ok(e.text.parse().unwrap());
        }
        if e.op == "variable" {
            return Ok(if e.text == "_data" {
                self.data
            } else {
                self.variables[&e.text]
            });
        }
        if e.op == "in" {
            return Ok(i64::from(self.active.contains(&self.ids[&e.text])));
        }
        let a = self.evaluate(&e.args[0])?;
        if e.op == "unary!" {
            return Ok(i64::from(a == 0));
        }
        if e.op == "unary-" {
            return Ok(-a);
        }
        if e.op == "&&" && a == 0 {
            return Ok(0);
        }
        if e.op == "||" && a != 0 {
            return Ok(1);
        }
        let b = self.evaluate(&e.args[1])?;
        if (e.op == "/" || e.op == "%") && b == 0 {
            return Err(());
        }
        Ok(match e.op.as_str() {
            "+" => a + b,
            "-" => a - b,
            "*" => a * b,
            "/" => a / b,
            "%" => a % b,
            "==" => i64::from(a == b),
            "!=" => i64::from(a != b),
            "<" => i64::from(a < b),
            "<=" => i64::from(a <= b),
            ">" => i64::from(a > b),
            ">=" => i64::from(a >= b),
            _ => i64::from(b != 0),
        })
    }

    fn reserve(&mut self, transition: Option<usize>, event: Option<Event>, delay: i64) {
        self.creation += 1;
        self.reservations.push(Reservation {
            due: self.time + delay,
            creation: self.creation,
            transition,
            event,
        });
    }

    fn run_actions(&mut self, actions: &[Action]) {
        for a in actions {
            let v = match a.expr.as_ref().map_or(Ok(0), |e| self.evaluate(e)) {
                Ok(v) => v,
                Err(()) => {
                    self.queue.push_back(Event::new("error.execution", 0));
                    break;
                }
            };
            match a.kind.as_str() {
                "assign" => {
                    self.variables.insert(a.name.clone(), v);
                }
                "raise" => self.queue.push_back(Event::new(a.name.clone(), v)),
                "send" => self.reserve(None, Some(Event::new(a.name.clone(), v)), a.delay),
                "cancel" => self
                    .reservations
                    .retain(|r| r.event.as_ref().is_none_or(|e| e.name != a.name)),
                "log" => self.output.push(
                    a.text.clone().unwrap_or_default()
                        + &if a.expr.is_some() {
                            v.to_string()
                        } else {
                            String::new()
                        },
                ),
                _ => unreachable!(),
            }
        }
    }

    fn effective(&self, t: &Transition) -> Vec<usize> {
        t.target.map_or(Vec::new(), |i| {
            if self.states[i].kind == "history" {
                self.states[i]
                    .history
                    .clone()
                    .unwrap_or_else(|| vec![self.states[i].default])
            } else {
                vec![i]
            }
        })
    }

    fn scope(&self, t: &Transition) -> Option<usize> {
        t.target?;
        let targets = self.effective(t);
        if t.mode == "local"
            && self.compound(t.source)
            && targets.iter().all(|i| self.descendant(*i, t.source))
        {
            return Some(t.source);
        }
        let mut p = self.states[t.source].parent;
        while !(self.compound(p) && targets.iter().all(|i| self.descendant(*i, p))) {
            p = self.states[p].parent;
        }
        Some(p)
    }

    fn matches(&self, t: &Transition, trigger: &Trigger, index: usize) -> bool {
        match trigger.kind {
            "always" => t.trigger == "always",
            "timer" => trigger.transition == Some(index),
            _ => {
                let name = &trigger.event.as_ref().unwrap().name;
                t.trigger == "event"
                    && t.descriptors
                        .iter()
                        .any(|d| d == "*" || d == name || name.starts_with(&(d.clone() + ".")))
            }
        }
    }

    fn select(&mut self, trigger: &Trigger) -> Vec<Selected> {
        let mut candidates = Vec::new();
        let mut seen = BTreeSet::new();
        for leaf in self.document.clone() {
            if !self.active.contains(&leaf) || !self.atomic(leaf) {
                continue;
            }
            let mut source = leaf;
            let mut chosen = None;
            while source != 0 && chosen.is_none() {
                for index in self.states[source].transitions.clone() {
                    let t = &self.transitions[index];
                    if !self.matches(t, trigger, index) {
                        continue;
                    }
                    let enabled = match t
                        .guard
                        .as_ref()
                        .map_or(Ok(true), |e| self.evaluate(e).map(|v| v != 0))
                    {
                        Ok(v) => v,
                        Err(()) => {
                            self.queue.push_back(Event::new("error.execution", 0));
                            false
                        }
                    };
                    if enabled {
                        chosen = Some(index);
                        break;
                    }
                }
                source = self.states[source].parent;
            }
            if let Some(i) = chosen {
                if seen.insert(i) {
                    candidates.push(i);
                }
            }
        }
        let mut occupied = BTreeSet::new();
        let mut result = Vec::new();
        for i in candidates {
            let scope = self.scope(&self.transitions[i]);
            let exits = scope.map_or(BTreeSet::new(), |p| {
                self.active
                    .iter()
                    .copied()
                    .filter(|i| self.descendant(*i, p))
                    .collect()
            });
            if exits.is_disjoint(&occupied) {
                occupied.extend(&exits);
                result.push(Selected {
                    transition: i,
                    scope,
                    exits,
                });
            }
        }
        result
    }

    fn expand(&self, entries: &mut BTreeSet<usize>) {
        loop {
            let before = entries.len();
            for i in entries.clone() {
                if self.parallel(i) {
                    entries.extend(self.children(i));
                }
                if self.compound(i) && self.children(i).iter().all(|c| !entries.contains(c)) {
                    entries.insert(self.states[i].initial);
                }
            }
            if before == entries.len() {
                return;
            }
        }
    }

    fn complete(&self, i: usize) -> bool {
        if self.compound(i) {
            self.children(i)
                .iter()
                .any(|c| self.states[*c].kind == "final" && self.active.contains(c))
        } else {
            self.parallel(i) && self.children(i).iter().all(|c| self.complete(*c))
        }
    }

    fn enter(&mut self, entries: &BTreeSet<usize>) {
        for i in self.document.clone() {
            if !entries.contains(&i) {
                continue;
            }
            self.active.insert(i);
            self.states[i].entered += 1;
            self.states[i].entry_time = self.time;
            for index in self.states[i].transitions.clone() {
                if self.transitions[index].trigger == "timer" {
                    self.reserve(Some(index), None, self.transitions[index].delay);
                }
            }
            for a in self.states[i].entries.clone() {
                self.run_actions(&a);
            }
            if self.states[i].kind == "final" {
                let p = self.states[i].parent;
                self.queue
                    .push_back(Event::new(format!("done.state.{}", self.states[p].id), 0));
                let g = self.states[p].parent;
                if self.parallel(g) && self.children(g).iter().all(|c| self.complete(*c)) {
                    self.queue
                        .push_back(Event::new(format!("done.state.{}", self.states[g].id), 0));
                }
            }
        }
    }

    fn list(&self, values: &[usize]) -> String {
        if values.is_empty() {
            "-".into()
        } else {
            values
                .iter()
                .map(|i| self.states[*i].id.as_str())
                .collect::<Vec<_>>()
                .join(",")
        }
    }

    fn display(&self, trigger: &Trigger) -> String {
        match trigger.kind {
            "always" => "always".into(),
            "timer" => {
                let t = &self.transitions[trigger.transition.unwrap()];
                format!("after({})@{}", t.delay, self.states[t.source].id)
            }
            _ => {
                let e = trigger.event.as_ref().unwrap();
                e.name.clone()
                    + &if e.value == 0 {
                        String::new()
                    } else {
                        format!("={}", e.value)
                    }
            }
        }
    }

    fn micro(&mut self, selected: &[Selected], trigger: &Trigger) {
        let exits: BTreeSet<usize> = selected
            .iter()
            .flat_map(|s| s.exits.iter().copied())
            .collect();
        for i in self.document.clone() {
            if self.states[i].kind == "history" && exits.contains(&self.states[i].parent) {
                let p = self.states[i].parent;
                let history = self
                    .document
                    .iter()
                    .copied()
                    .filter(|c| {
                        self.active.contains(c)
                            && if self.states[i].deep {
                                self.atomic(*c) && self.descendant(*c, p)
                            } else {
                                self.states[*c].parent == p && self.states[*c].kind != "history"
                            }
                    })
                    .collect();
                self.states[i].history = Some(history);
            }
        }
        let mut entries = BTreeSet::new();
        for choice in selected {
            if let Some(scope) = choice.scope {
                for target in self.effective(&self.transitions[choice.transition]) {
                    let mut i = target;
                    while i != scope {
                        entries.insert(i);
                        i = self.states[i].parent;
                    }
                }
            }
        }
        self.expand(&mut entries);
        if self.trace {
            let sources = selected
                .iter()
                .map(|s| self.transitions[s.transition].source)
                .collect::<Vec<_>>();
            let exit_list = self
                .document
                .iter()
                .rev()
                .copied()
                .filter(|i| exits.contains(i))
                .collect::<Vec<_>>();
            let entry_list = self
                .document
                .iter()
                .copied()
                .filter(|i| entries.contains(i))
                .collect::<Vec<_>>();
            self.output.push(format!(
                "[t={}] {} ({}): exit {}; enter {}",
                self.time,
                self.display(trigger),
                self.list(&sources),
                self.list(&exit_list),
                self.list(&entry_list)
            ));
        }
        for i in self.document.clone().into_iter().rev() {
            if exits.contains(&i) {
                for a in self.states[i].exits.clone() {
                    self.run_actions(&a);
                }
                self.active.remove(&i);
                self.states[i].dwell += self.time - self.states[i].entry_time;
                let transitions = &self.transitions;
                self.reservations
                    .retain(|r| r.transition.is_none_or(|t| transitions[t].source != i));
            }
        }
        for choice in selected {
            let t = self.transitions[choice.transition].clone();
            self.run_actions(&t.actions);
            self.states[t.source].taken += 1;
        }
        self.enter(&entries);
    }

    fn perform(&mut self, selected: Vec<Selected>, trigger: &Trigger, count: &mut usize) -> bool {
        if selected.is_empty() {
            return true;
        }
        if *count == 1000 {
            self.output.push(format!("LIVELOCK t={}", self.time));
            self.halted = true;
            return false;
        }
        *count += 1;
        self.micros += 1;
        self.micro(&selected, trigger);
        true
    }

    fn macrostep(&mut self, trigger: Trigger) {
        self.macros += 1;
        let mut count = 0;
        if trigger.kind == "start" {
            self.data = 0;
            let mut entries = BTreeSet::from([self.states[0].initial]);
            self.expand(&mut entries);
            self.enter(&entries);
        } else {
            self.data = trigger.event.as_ref().map_or(0, |e| e.value);
            let selected = self.select(&trigger);
            if !self.perform(selected, &trigger, &mut count) {
                return;
            }
        }
        loop {
            self.data = 0;
            let always = Trigger::kind("always");
            let selected = self.select(&always);
            if !selected.is_empty() {
                if !self.perform(selected, &always, &mut count) {
                    return;
                }
                continue;
            }
            let Some(event) = self.queue.pop_front() else {
                return;
            };
            self.data = event.value;
            let next = Trigger::event(event);
            let selected = self.select(&next);
            if !self.perform(selected, &next, &mut count) {
                return;
            }
        }
    }

    fn script(&mut self, line: &str) {
        if self.halted {
            return;
        }
        let w: Vec<&str> = line.split(' ').collect();
        match w[0] {
            "event" => self.macrostep(Trigger::event(Event::new(
                w[1],
                w.get(2).map_or(0, |s| s.parse().unwrap()),
            ))),
            "tick" => {
                let finish = self.time + w[1].parse::<i64>().unwrap();
                while !self.halted {
                    let next = self
                        .reservations
                        .iter()
                        .enumerate()
                        .filter(|(_, r)| r.due <= finish)
                        .min_by_key(|(_, r)| (r.due, r.creation))
                        .map(|(i, _)| i);
                    let Some(index) = next else {
                        break;
                    };
                    let r = self.reservations.remove(index);
                    self.time = r.due;
                    self.macrostep(if let Some(t) = r.transition {
                        Trigger {
                            kind: "timer",
                            event: None,
                            transition: Some(t),
                        }
                    } else {
                        Trigger::event(r.event.unwrap())
                    });
                }
                if !self.halted {
                    self.time = finish;
                }
            }
            "set" => {
                if self.variables.contains_key(w[1]) {
                    self.variables.insert(w[1].into(), w[2].parse().unwrap());
                } else {
                    self.output
                        .push(format!("error: unknown variable {}", w[1]));
                }
            }
            "trace" => self.trace = w[1] == "on",
            "eval" => {
                let text = &line[5..];
                match self.expression(text) {
                    Err(reason) => self.output.push(format!("error: {}", reason)),
                    Ok(e) => {
                        self.data = 0;
                        let result = self.evaluate(&e);
                        self.output.push(match result {
                            Ok(value) => format!("{} -> {}", text, value),
                            Err(()) => "error: division by zero".into(),
                        });
                    }
                }
            }
            "dump" => {
                self.output.push(format!("dump t={}", self.time));
                for &i in &self.document {
                    if self.active.contains(&i) {
                        self.output
                            .push("  ".repeat(self.states[i].depth) + &self.states[i].id);
                    }
                }
                for (name, value) in &self.variables {
                    self.output.push(format!("  var {} = {}", name, value));
                }
                for &i in &self.document {
                    if let Some(h) = &self.states[i].history {
                        self.output.push(format!(
                            "  history {} = {}",
                            self.states[i].id,
                            self.list(h)
                        ));
                    }
                }
                let mut reservations = self.reservations.clone();
                reservations.sort_by_key(|r| (r.due, r.creation));
                for r in reservations {
                    if let Some(i) = r.transition {
                        let t = &self.transitions[i];
                        self.output.push(format!(
                            "  timer {} after({})@{}",
                            r.due, t.delay, self.states[t.source].id
                        ));
                    } else {
                        let e = r.event.unwrap();
                        self.output
                            .push(format!("  send {} {} {}", r.due, e.name, e.value));
                    }
                }
            }
            _ => unreachable!(),
        }
    }

    fn statistics(&mut self) {
        self.output.push(format!(
            "end t={} macrosteps={} microsteps={}",
            self.time, self.macros, self.micros
        ));
        for &i in &self.document {
            let s = &self.states[i];
            if s.kind != "history" {
                let dwell = s.dwell
                    + if self.active.contains(&i) {
                        self.time - s.entry_time
                    } else {
                        0
                    };
                self.output.push(format!(
                    "  {} entered={} taken={} time={}",
                    s.id, s.entered, s.taken, dwell
                ));
            }
        }
    }
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let lines: Vec<&str> = input.lines().collect();
    let count: usize = lines[0].parse().unwrap();
    let mut at = 1;
    let mut output = Vec::new();
    for _ in 0..count {
        output.push(format!("chart {}", &lines[at][6..]));
        at += 1;
        let mut definitions = Vec::new();
        while lines[at] != "RUN" {
            definitions.push((at + 1, lines[at]));
            at += 1;
        }
        at += 1;
        let mut scripts = Vec::new();
        while lines[at] != "END" {
            scripts.push(lines[at]);
            at += 1;
        }
        at += 1;
        let mut chart = Chart::new();
        if chart.define(&definitions) {
            chart.warnings();
            chart.macrostep(Trigger::kind("start"));
            for line in scripts {
                chart.script(line);
            }
            chart.statistics();
        }
        output.extend(chart.output);
    }
    for line in output {
        println!("{}", line);
    }
}
