mod reader;
mod terms;
mod unify;
mod database;
mod predicates;
use std::collections::{
    BTreeMap,
    BTreeSet,
    VecDeque
};
use std::fs;
use terms::{
    Term,
    Store,
    Indicator,
    list,
    indicator_term,
    type_error,
    domain_error,
    error_ball
};
use unify::Trail;
use database::{
    Database,
    Clause,
    Predicate
};
struct Writer<'a> {
    store: &'a Store,
    quoted: bool,
    names: BTreeMap<usize,
    String>,
    generated: usize
}
impl<'a> Writer<'a> {
    fn new(store: &'a Store, quoted: bool) -> Self {
        Self {
            store,
            quoted,
            names: BTreeMap::new(),
            generated: 0
        }
    }
    fn atom(&self, name: &str) -> String {
        let bytes = name.as_bytes();
        let plain = (!bytes.is_empty() && bytes[0].is_ascii_lowercase() && bytes.iter().all(|c| c.is_ascii_alphanumeric() || *c == b'_')) || (!bytes.is_empty() && name != "." && bytes.iter().all(|&c| reader::symbol(c))) || ["[]", "!", ";"].contains(&name);
        if !self.quoted || plain {
            name.into()
        } else {
            format!("'{}'", name.replace('\\', "\\\\").replace('\'', "\\'").replace('\n', "\\n").replace('\t', "\\t"))
        }
    }
    fn term(&mut self, term: &Term, limit: usize, operand: bool) -> String {
        match self.store.dereference(term) {
            Term::Integer(n) => n.to_string(),
            Term::Variable(id) => {
                if !self.names.contains_key(&id) {
                    self.generated += 1;
                    self.names.insert(id, format!("_G{}", self.generated));
                }
                self.names[&id].clone()
            },
            Term::Atom(name) => {
                let text = self.atom(&name);
                if operand && reader::operator(&name) {
                    format!("({})", text)
                } else {
                    text
                }
            },
            Term::Compound(name, arguments) => {
                if name == "." && arguments.len() == 2 {
                    let term = Term::Compound(name, arguments);
                    let (elements, tail) = self.store.parts(&term);
                    let mut text = format!("[{}", elements.iter().map(|e| self.term(e, 999, false)).collect::<Vec<_>>().join(","));
                    if !matches!(tail, Term::Atom(ref name) if name == "[]") {
                        text.push('|');
                        text.push_str(&self.term(&tail, 999, false));
                    }
                    text.push(']');
                    return text;
                }
                if arguments.len() == 2 {
                    if let Some((priority, left, right)) = reader::infix(&name) {
                        let a = self.term(&arguments[0], left, true);
                        let b = self.term(&arguments[1], right, true);
                        let text = if name == "," {
                            a + "," + &b
                        } else if name.as_bytes()[0].is_ascii_alphabetic() {
                            format!("{} {} {}", a, name, b)
                        } else {
                            format!("{}{}{}{}{}", a, if a.as_bytes().last().map_or(false, |&c| reader::symbol(c)) {
                                " "
                            } else {
                                ""
                            }, name, if b.as_bytes().first().map_or(false, |&c| reader::symbol(c)) {
                                " "
                            } else {
                                ""
                            }, b)
                        };
                        return if priority > limit {
                            format!("({})", text)
                        } else {
                            text
                        };
                    }
                }
                if arguments.len() == 1 {
                    if let Some(priority) = reader::prefix(&name) {
                        let argument = self.term(&arguments[0], priority, true);
                        let space = argument.as_bytes().first().map_or(false, |&c| reader::symbol(c) || c.is_ascii_digit() || c == b'(');
                        let text = format!("{}{}{}", name, if space {
                            " "
                        } else {
                            ""
                        }, argument);
                        return if priority > limit {
                            format!("({})", text)
                        } else {
                            text
                        };
                    }
                }
                format!("{}({})", self.atom(&name), arguments.iter().map(|a| self.term(a, 999, false)).collect::<Vec<_>>().join(","))
            }
        }
    }
}
fn write_term(term: &Term, store: &Store, quoted: bool) -> String {
    Writer::new(store, quoted).term(term, 1200, false)
}
fn indicator_text(indicator: &Indicator) -> String {
    write_term(&indicator_term(indicator), &Store::new(), true)
}
fn goal_conversion(term: &Term, store: &Store) -> Option<Term> {
    match store.dereference(term) {
        Term::Variable(id) => Some(Term::compound("call", vec![Term::Variable(id)])),
        Term::Integer(_) => None,
        Term::Compound(name, arguments) if [",", ";", "->"].contains(&name.as_str()) && arguments.len() == 2 => Some(Term::Compound(name, vec![goal_conversion(&arguments[0], store)?, goal_conversion(&arguments[1], store)?])),
        term => Some(term)
    }
}
struct Consult {
    database: Database,
    store: Store,
    reports: Vec<String>,
    counts: [[usize; 3]; 2]
}
impl Consult {
    fn warning(&mut self, file: usize, line: usize, message: String) {
        self.counts[file][2] += 1;
        self.reports.push(format!("{}:{}: warning: {}", if file == 0 {
            "prelude.pl"
        } else {
            "program.pl"
        }, line, message));
    }
    fn read(&mut self, file: usize, text: &str) {
        let name = if file == 0 {
            "prelude.pl"
        } else {
            "program.pl"
        };
        let tokens = reader::lex(text, 1);
        let source: Vec<&str> = text.lines().collect();
        let mut start = 0;
        let mut last = None;
        let mut discontiguous = BTreeSet::new();
        while tokens[start].kind != "eof" {
            let line = tokens[start].line;
            let parsed = match reader::clause(&tokens, start, &mut self.store, false) {
                Ok(parsed) => parsed,
                Err(error) => {
                    self.counts[file][1] += 1;
                    self.reports.push(format!("{}:{}:{}: syntax error: {}", name, error.line, error.column, error.message));
                    if !error.eof {
                        self.reports.push(format!("    {}", source[error.line - 1]));
                        self.reports.push(format!("{}^", " ".repeat(error.column + 3)));
                    }
                    start = error.index;
                    while tokens[start].kind != "eof" && tokens[start].kind != "end" {
                        start += 1;
                    }
                    if tokens[start].kind == "end" {
                        start += 1;
                    }
                    continue;
                }
            };
            start = parsed.next;
            let (head, body) = if let Term::Compound(ref name, ref arguments) = parsed.term {
                if name == ":-" && arguments.len() == 2 {
                    (arguments[0].clone(), Some(arguments[1].clone()))
                } else {
                    (parsed.term.clone(), None)
                }
            } else {
                (parsed.term.clone(), None)
            };
            let mut error = match &head {
                Term::Variable(_) => Some(Term::atom("instantiation_error")),
                Term::Integer(_) => Some(type_error("callable", head.clone())),
                _ => None
            };
            let indicator = head.indicator();
            if error.is_none() {
                let key = indicator.as_ref().unwrap();
                if predicates::control(key) || predicates::builtin(key) {
                    error = Some(Term::compound("permission_error", vec![Term::atom("modify"), Term::atom("static_procedure"), indicator_term(key)]));
                }
            }
            let converted = body.as_ref().and_then(|body| goal_conversion(body, &self.store));
            if error.is_none() && body.is_some() && converted.is_none() {
                error = Some(type_error("callable", body.clone().unwrap()));
            }
            if let Some(error) = error {
                self.counts[file][1] += 1;
                self.reports.push(format!("{}:{}: error: {}", name, line, write_term(&error, &self.store, true)));
                continue;
            }
            let key = indicator.unwrap();
            let index = self.database.find(&key).unwrap_or_else(|| {
                let index = self.database.predicates.len();
                self.database.predicates.push(Predicate {
                    indicator: key.clone(),
                    clauses: Vec::new()
                });
                index
            });
            if file == 1 && self.database.predicates[index].clauses.iter().any(|c| c.file == "prelude.pl") {
                self.warning(file, line, format!("redefining prelude procedure {}", indicator_text(&key)));
                self.database.predicates[index].clauses.clear();
            }
            if self.database.predicates[index].clauses.iter().any(|c| c.file == name) && last != Some(index) && discontiguous.insert(index) {
                self.warning(file, line, format!("clauses of {} are not together", indicator_text(&key)));
            }
            self.database.predicates[index].clauses.push(Clause {
                head,
                body: converted,
                file: name.into(),
                line
            });
            last = Some(index);
            self.counts[file][0] += 1;
            let singletons: Vec<String> = parsed.variables.iter().filter(|v| !v.name.starts_with('_') && v.count == 1).map(|v| v.name.clone()).collect();
            if !singletons.is_empty() {
                self.warning(file, line, format!("singleton variables: {}", singletons.join(", ")));
            }
            let repeated: Vec<String> = parsed.variables.iter().filter(|v| v.name.starts_with('_') && v.name.len() > 1 && v.count >= 2).map(|v| v.name.clone()).collect();
            if !repeated.is_empty() {
                self.warning(file, line, format!("variables starting with _ occur more than once: {}", repeated.join(", ")));
            }
        }
    }
    fn undefined(&mut self) {
        fn visit(term: &Term, result: &mut Vec<Indicator>) {
            if let Some(indicator) = term.indicator() {
                let args = term.arguments();
                match (indicator.0.as_str(), indicator.1) {
                    (",", 2) | (";", 2) | ("->", 2) => {
                        visit(&args[0], result);
                        visit(&args[1], result);
                    },
                    ("\\+", 1) | ("call", 1) => visit(&args[0], result),
                    ("findall", 3) => visit(&args[1], result),
                    ("catch", 3) => {
                        visit(&args[0], result);
                        visit(&args[2], result);
                    },
                    _ => if !predicates::control(&indicator) && !predicates::builtin(&indicator) {
                        result.push(indicator);
                    }
                }
            }
        }
        let mut warnings = Vec::new();
        let mut reported = BTreeSet::new();
        for predicate in &self.database.predicates {
            for clause in &predicate.clauses {
                if let Some(body) = &clause.body {
                    let mut indicators = Vec::new();
                    visit(body, &mut indicators);
                    for indicator in indicators {
                        if self.database.find(&indicator).is_none() && reported.insert(indicator.clone()) {
                            warnings.push((if clause.file == "prelude.pl" {
                                0
                            } else {
                                1
                            }, clause.line, format!("undefined procedure {} called from {}", indicator_text(&indicator), indicator_text(&predicate.indicator))));
                        }
                    }
                }
            }
        }
        for (file, line, message) in warnings {
            self.warning(file, line, message);
        }
        for (i, file) in ["prelude.pl", "program.pl"].iter().enumerate() {
            self.reports.push(format!("{}: clauses={} errors={} warnings={}", file, self.counts[i][0], self.counts[i][1], self.counts[i][2]));
        }
        self.reports.push(format!("database: predicates={} clauses={}", self.database.predicates.len(), self.database.predicates.iter().map(|p| p.clauses.len()).sum::<usize>()));
    }
    fn listing(&self) -> Vec<String> {
        let mut output = Vec::new();
        for (p, predicate) in self.database.predicates.iter().enumerate() {
            if p > 0 {
                output.push(String::new());
            }
            for clause in &predicate.clauses {
                let mut terms = vec![clause.head.clone()];
                if let Some(body) = &clause.body {
                    terms.push(body.clone());
                }
                let variables = self.store.variables(&terms);
                let mut counts = BTreeMap::new();
                for &id in &variables {
                    *counts.entry(id).or_insert(0) += 1;
                }
                let mut writer = Writer::new(&self.store, true);
                let mut number = 0;
                for id in variables {
                    if !writer.names.contains_key(&id) {
                        let name = if counts[&id] == 1 {
                            "_".into()
                        } else {
                            let name = format!("{}{}", (b'A' + (number % 26) as u8) as char, if number >= 26 {
                                (number / 26).to_string()
                            } else {
                                String::new()
                            });
                            number += 1;
                            name
                        };
                        writer.names.insert(id, name);
                    }
                }
                let head = writer.term(&clause.head, 1200, false);
                if let Some(body) = &clause.body {
                    output.push(format!("{} :-", head));
                    let mut goals = Vec::new();
                    let mut body = body.clone();
                    loop {
                        match body {
                            Term::Compound(ref name, ref args) if name == "," && args.len() == 2 => {
                                goals.push(args[0].clone());
                                body = args[1].clone();
                            },
                            _ => {
                                goals.push(body);
                                break;
                            }
                        }
                    }
                    for (i, goal) in goals.iter().enumerate() {
                        output.push(format!("    {}{}", writer.term(goal, 999, false), if i + 1 == goals.len() {
                            "."
                        } else {
                            ","
                        }));
                    }
                }
                else {
                    output.push(head + ".");
                }
            }
        }
        output
    }
}
#[derive(Clone)]
enum Goal {
    Term(Term),
    Ite(usize),
    Naf(usize),
    Exit(usize),
    Collect(usize)
}
#[derive(Clone)]
struct Entry {
    goal: Goal,
    barrier: usize,
    context: Option<usize>
}
impl Entry {
    fn term(term: Term, barrier: usize, context: Option<usize>) -> Self {
        Self {
            goal: Goal::Term(term),
            barrier,
            context
        }
    }
}
#[derive(Clone)]
enum ChoiceKind {
    Alternative,
    Clauses {
        predicate: usize,
        candidates: Vec<usize>,
        next: usize,
        goal: Term,
        barrier: usize,
        context: Option<usize>
    },
    Between {
        high: i64,
        variable: Term,
        next: i64
    },
    Length {
        tail: Term,
        length: Term,
        prefix: usize,
        next: usize
    },
    Catch {
        catcher: Term,
        recovery: Term,
        parent: Option<usize>
    },
    Findall {
        template: Term,
        result: Term,
        results: Vec<Term>
    },
}
#[derive(Clone)]
struct Choice {
    id: usize,
    mark: usize,
    resume: VecDeque<Entry>,
    kind: ChoiceKind
}
struct Engine<'a> {
    database: &'a Database,
    profile: &'a mut BTreeMap<Indicator,
    (usize, usize)>,
    store: Store,
    trail: Trail,
    goals: VecDeque<Entry>,
    choices: Vec<Choice>,
    serial: usize,
    solutions: usize,
    inferences: usize,
    choicepoints: usize,
    backtracks: usize,
    limit_reached: bool,
    output: String,
    answers: Vec<String>,
}
impl<'a> Engine<'a> {
    fn new(database: &'a Database, profile: &'a mut BTreeMap<Indicator, (usize, usize)>, store: Store, query: Term) -> Self {
        Self {
            database,
            profile,
            store,
            trail: Trail::new(),
            goals: VecDeque::from(vec![Entry::term(Term::compound("call", vec![query]), 0, None)]),
            choices: Vec::new(),
            serial: 0,
            solutions: 0,
            inferences: 0,
            choicepoints: 0,
            backtracks: 0,
            limit_reached: false,
            output: String::new(),
            answers: Vec::new()
        }
    }
    fn push(&mut self, kind: ChoiceKind, resume: VecDeque<Entry>) -> usize {
        let id = self.serial;
        self.serial += 1;
        self.choicepoints += 1;
        self.choices.push(Choice {
            id,
            mark: self.trail.mark(),
            resume,
            kind
        });
        id
    }
    fn prepend(&mut self, entries: Vec<Entry>) {
        for entry in entries.into_iter().rev() {
            self.goals.push_front(entry);
        }
    }
    fn inference(&mut self, indicator: &Indicator) -> bool {
        if self.inferences == 20000 {
            self.limit_reached = true;
            return false;
        }
        self.inferences += 1;
        self.profile.entry(indicator.clone()).or_insert((0, 0)).0 += 1;
        true
    }
    fn unify(&mut self, a: &Term, b: &Term) -> bool {
        self.trail.unify(a, b, &mut self.store)
    }
    fn try_clause(&mut self, predicate: usize, clause: usize, goal: Term, barrier: usize, context: Option<usize>, resume: VecDeque<Entry>) -> bool {
        let indicator = self.database.predicates[predicate].indicator.clone();
        self.profile.entry(indicator).or_insert((0, 0)).1 += 1;
        let (head, body) = self.database.copy(predicate, clause, &mut self.store);
        if !self.unify(&head, &goal) {
            return false;
        }
        self.goals = resume;
        if let Some(body) = body {
            self.goals.push_front(Entry::term(body, barrier, context));
        }
        true
    }
    fn execute(&mut self, entry: Entry) -> Result<bool,
    Term> {
        let barrier = entry.barrier;
        let context = entry.context;
        let term = match entry.goal {
            Goal::Ite(height) => {
                self.choices.truncate(height);
                return Ok(true);
            },
            Goal::Naf(height) => {
                self.choices.truncate(height);
                return Ok(false);
            },
            Goal::Exit(id) => {
                if self.choices.last().map_or(false, |c| c.id == id) {
                    self.choices.pop();
                }
                return Ok(true);
            },
            Goal::Collect(id) => {
                let index = self.choices.iter().position(|c| c.id == id).unwrap();
                let template = if let ChoiceKind::Findall {
                    template,
                    ..
                }
                = &self.choices[index].kind {
                    template.clone()
                } else {
                    unreachable!()
                };
                let copy = self.store.copy(&template);
                if let ChoiceKind::Findall {
                    results,
                    ..
                }
                = &mut self.choices[index].kind {
                    results.push(copy);
                }
                return Ok(false);
            },
            Goal::Term(term) => self.store.dereference(&term)
        };
        let indicator = term.indicator().unwrap();
        let arguments = term.arguments();
        let name = indicator.0.as_str();
        if predicates::control(&indicator) {
            match (name, indicator.1) {
                (",", 2) => self.prepend(vec![Entry::term(arguments[0].clone(), barrier, context), Entry::term(arguments[1].clone(), barrier, context)]),
                ("!", 0) => self.choices.truncate(barrier),
                (";", 2) => {
                    let height = self.choices.len();
                    let mut resume = self.goals.clone();
                    resume.push_front(Entry::term(arguments[1].clone(), barrier, context));
                    self.push(ChoiceKind::Alternative, resume);
                    let left = self.store.dereference(&arguments[0]);
                    if let Term::Compound(name, branches) = &left {
                        if name == "->" && branches.len() == 2 {
                            self.prepend(vec![Entry::term(branches[0].clone(), height + 1, context), Entry {
                                goal: Goal::Ite(height),
                                barrier,
                                context
                            }, Entry::term(branches[1].clone(), barrier, context)]);
                            return Ok(true);
                        }
                    }
                    self.goals.push_front(Entry::term(left, barrier, context));
                },
                ("->", 2) => {
                    let height = self.choices.len();
                    self.prepend(vec![Entry::term(arguments[0].clone(), height, context), Entry {
                        goal: Goal::Ite(height),
                        barrier,
                        context
                    }, Entry::term(arguments[1].clone(), barrier, context)]);
                },
                ("\\+", 1) => {
                    let height = self.choices.len();
                    self.push(ChoiceKind::Alternative, self.goals.clone());
                    self.prepend(vec![Entry::term(Term::compound("call", vec![arguments[0].clone()]), barrier, context), Entry {
                        goal: Goal::Naf(height),
                        barrier,
                        context
                    }]);
                },
                ("call", _) => {
                    let first = self.store.dereference(&arguments[0]);
                    if matches!(first, Term::Variable(_)) {
                        return Err(error_ball(Term::atom("instantiation_error"), &indicator));
                    }
                    if matches!(first, Term::Integer(_)) {
                        return Err(error_ball(type_error("callable", first), &indicator));
                    }
                    let applied = if arguments.len() == 1 {
                        first
                    } else {
                        match first {
                            Term::Atom(name) => Term::Compound(name, arguments[1..].to_vec()),
                            Term::Compound(name, mut args) => {
                                args.extend_from_slice(&arguments[1..]);
                                Term::Compound(name, args)
                            },
                            _ => unreachable!()
                        }
                    };
                    let converted = goal_conversion(&applied, &self.store).ok_or_else(|| error_ball(type_error("callable", applied), &indicator))?;
                    let height = self.choices.len();
                    self.goals.push_front(Entry::term(converted, height, context));
                },
                ("catch", 3) => {
                    let id = self.push(ChoiceKind::Catch {
                        catcher: arguments[1].clone(),
                        recovery: arguments[2].clone(),
                        parent: context
                    }, self.goals.clone());
                    self.prepend(vec![Entry::term(Term::compound("call", vec![arguments[0].clone()]), barrier, Some(id)), Entry {
                        goal: Goal::Exit(id),
                        barrier,
                        context
                    }]);
                },
                _ => unreachable!()
            }
            return Ok(true);
        }
        if !self.inference(&indicator) {
            return Ok(false);
        }
        match (name, indicator.1) {
            ("findall", 3) => {
                let id = self.push(ChoiceKind::Findall {
                    template: arguments[0].clone(),
                    result: arguments[2].clone(),
                    results: Vec::new()
                }, self.goals.clone());
                self.goals = VecDeque::from(vec![Entry::term(Term::compound("call", vec![arguments[1].clone()]), barrier, context), Entry {
                    goal: Goal::Collect(id),
                    barrier,
                    context
                }]);
                Ok(true)
            },
            ("throw", 1) => {
                let ball = self.store.dereference(&arguments[0]);
                Err(if matches!(ball, Term::Variable(_)) {
                    error_ball(Term::atom("instantiation_error"), &indicator)
                } else {
                    ball
                })
            },
            ("between", 3) => {
                let low = predicates::integer(&arguments[0], &self.store).map_err(|e| error_ball(e, &indicator))?;
                let high = predicates::integer(&arguments[1], &self.store).map_err(|e| error_ball(e, &indicator))?;
                let variable = self.store.dereference(&arguments[2]);
                match variable {
                    Term::Integer(n) => Ok(low <= n && n <= high),
                    Term::Variable(_) => {
                        if low > high {
                            return Ok(false);
                        }
                        if low < high {
                            self.push(ChoiceKind::Between {
                                high,
                                variable: variable.clone(),
                                next: low + 1
                            }, self.goals.clone());
                        }
                        Ok(self.unify(&variable, &Term::Integer(low)))
                    },
                    term => Err(error_ball(type_error("integer", term), &indicator))
                }
            },
            ("length", 2) => {
                let length = self.store.dereference(&arguments[1]);
                if !matches!(length, Term::Variable(_) | Term::Integer(_)) {
                    return Err(error_ball(type_error("integer", length), &indicator));
                }
                if let Term::Integer(n) = length {
                    if n < 0 {
                        return Err(error_ball(domain_error("not_less_than_zero", Term::Integer(n)), &indicator));
                    }
                }
                let (elements, tail) = self.store.parts(&arguments[0]);
                let prefix = elements.len();
                if matches!(tail, Term::Atom(ref name) if name == "[]") {
                    return Ok(self.unify(&arguments[1], &Term::Integer(prefix as i64)));
                }
                if !matches!(tail, Term::Variable(_)) {
                    return Err(error_ball(type_error("list", arguments[0].clone()), &indicator));
                }
                if let Term::Integer(n) = length {
                    if n < prefix as i64 {
                        return Ok(false);
                    }
                    let elements = (0..n as usize - prefix).map(|_| self.store.fresh()).collect();
                    Ok(self.unify(&tail, &list(elements, Term::atom("[]"))))
                }
                else {
                    self.push(ChoiceKind::Length {
                        tail: tail.clone(),
                        length: length.clone(),
                        prefix,
                        next: prefix + 1
                    }, self.goals.clone());
                    Ok(self.unify(&tail, &Term::atom("[]")) && self.unify(&length, &Term::Integer(prefix as i64)))
                }
            },
            _ if predicates::builtin(&indicator) => predicates::deterministic(&indicator, &arguments, &mut self.store, &mut self.trail, &mut self.output, write_term).map_err(|e| error_ball(e, &indicator)),
            _ => {
                let predicate = self.database.find(&indicator).ok_or_else(|| error_ball(Term::compound("existence_error", vec![Term::atom("procedure"), indicator_term(&indicator)]), &indicator))?;
                let candidates = self.database.candidates(predicate, &term, &self.store);
                if candidates.is_empty() {
                    return Ok(false);
                }
                let height = self.choices.len();
                let first = candidates[0];
                let resume = self.goals.clone();
                if candidates.len() > 1 {
                    self.push(ChoiceKind::Clauses {
                        predicate,
                        candidates,
                        next: 1,
                        goal: term.clone(),
                        barrier: height,
                        context
                    }, resume.clone());
                }
                Ok(self.try_clause(predicate, first, term, height, context, resume))
            }
        }
    }
    fn backtrack(&mut self) -> bool {
        'retry: loop {
            self.backtracks += 1;
            loop {
                let choice = match self.choices.last() {
                    Some(choice) => choice.clone(),
                    None => return false
                };
                self.trail.undo(choice.mark, &mut self.store);
                match choice.kind {
                    ChoiceKind::Alternative => {
                        self.choices.pop();
                        self.goals = choice.resume;
                        return true;
                    },
                    ChoiceKind::Clauses {
                        predicate,
                        candidates,
                        next,
                        goal,
                        barrier,
                        context
                    } => {
                        let clause = candidates[next];
                        if next + 1 == candidates.len() {
                            self.choices.pop();
                        } else if let ChoiceKind::Clauses {
                            next,
                            ..
                        }
                        = &mut self.choices.last_mut().unwrap().kind {
                            *next += 1;
                        }
                        if self.try_clause(predicate, clause, goal, barrier, context, choice.resume) {
                            return true;
                        }
                        continue 'retry;
                    },
                    ChoiceKind::Between {
                        high,
                        variable,
                        next
                    } => {
                        if !self.inference(&("between".into(), 3)) {
                            return false;
                        }
                        if next == high {
                            self.choices.pop();
                        } else if let ChoiceKind::Between {
                            next,
                            ..
                        }
                        = &mut self.choices.last_mut().unwrap().kind {
                            *next += 1;
                        }
                        if self.unify(&variable, &Term::Integer(next)) {
                            self.goals = choice.resume;
                            return true;
                        }
                        continue 'retry;
                    },
                    ChoiceKind::Length {
                        tail,
                        length,
                        prefix,
                        next
                    } => {
                        if !self.inference(&("length".into(), 2)) {
                            return false;
                        }
                        if let ChoiceKind::Length {
                            next,
                            ..
                        }
                        = &mut self.choices.last_mut().unwrap().kind {
                            *next += 1;
                        }
                        let elements = (0..next - prefix).map(|_| self.store.fresh()).collect();
                        let proper = list(elements, Term::atom("[]"));
                        if self.unify(&tail, &proper) && self.unify(&length, &Term::Integer(next as i64)) {
                            self.goals = choice.resume;
                            return true;
                        }
                        continue 'retry;
                    },
                    ChoiceKind::Catch {
                        ..
                    } => {
                        self.choices.pop();
                    },
                    ChoiceKind::Findall {
                        result,
                        results,
                        ..
                    } => {
                        self.choices.pop();
                        if self.unify(&list(results, Term::atom("[]")), &result) {
                            self.goals = choice.resume;
                            return true;
                        }
                        continue 'retry;
                    }
                }
            }
        }
    }
    fn exception(&mut self, ball: Term, mut context: Option<usize>) -> bool {
        let ball = self.store.copy(&ball);
        loop {
            let id = match context {
                Some(id) => id,
                None => {
                    self.answers.push(format!("uncaught exception: {}", write_term(&ball, &self.store, true)));
                    return false;
                }
            };
            let index = self.choices.iter().position(|c| c.id == id).unwrap();
            let choice = self.choices[index].clone();
            self.choices.truncate(index);
            self.trail.undo(choice.mark, &mut self.store);
            if let ChoiceKind::Catch {
                catcher,
                recovery,
                parent
            }
            = choice.kind {
                let mark = self.trail.mark();
                let copied = self.store.copy(&ball);
                if self.unify(&copied, &catcher) {
                    let height = self.choices.len();
                    self.goals = choice.resume;
                    self.goals.push_front(Entry::term(Term::compound("call", vec![recovery]), height, parent));
                    return true;
                }
                self.trail.undo(mark, &mut self.store);
                context = parent;
            } else {
                unreachable!()
            }
        }
    }
    fn answer(&self, variables: &[reader::Variable]) -> String {
        let variables: Vec<_> = variables.iter().filter(|v| !v.name.starts_with('_')).collect();
        let values: Vec<Term> = variables.iter().map(|v| self.store.dereference(&v.term)).collect();
        let mut writer = Writer::new(&self.store, true);
        for (variable, value) in variables.iter().zip(&values) {
            if let Term::Variable(id) = value {
                writer.names.entry(*id).or_insert(variable.name.clone());
            }
        }
        let mut items = Vec::new();
        for (i, variable) in variables.iter().enumerate() {
            if let Term::Variable(id) = values[i] {
                if let Some(previous) = (0..i).rev().find(|&j| matches!(values[j], Term::Variable(other) if other == id)) {
                    items.push(format!("{} = {}", variables[previous].name, variable.name));
                }
            }
            else {
                items.push(format!("{} = {}", variable.name, writer.term(&values[i], 699, true)));
            }
        }
        if items.is_empty() {
            "true".into()
        } else {
            items.join(", ")
        }
    }
    fn run(&mut self, variables: &[reader::Variable], limit: Option<usize>) {
        loop {
            if self.goals.is_empty() {
                self.solutions += 1;
                let answer = self.answer(variables);
                if limit == Some(self.solutions) || self.choices.is_empty() {
                    self.answers.push(answer + ".");
                    break;
                }
                self.answers.push(answer + " ;");
                if !self.backtrack() {
                    self.answers.push(if self.limit_reached {
                        "inference limit exceeded"
                    } else {
                        "false."
                    }.into());
                    break;
                }
                continue;
            }
            let entry = self.goals.pop_front().unwrap();
            let context = entry.context;
            match self.execute(entry) {
                Ok(true) => (),
                Ok(false) => {
                    if self.limit_reached || !self.backtrack() {
                        self.answers.push(if self.limit_reached {
                            "inference limit exceeded"
                        } else {
                            "false."
                        }.into());
                        break;
                    }
                },
                Err(ball) => if !self.exception(ball, context) {
                    break;
                }
            }
        }
    }
}
fn write(name: &str, text: &str) {
    fs::create_dir_all("output").unwrap();
    fs::write(format!("output/{}", name), text).unwrap();
}
fn lines_text(lines: &[String]) -> String {
    if lines.is_empty() {
        String::new()
    } else {
        lines.join("\n") + "\n"
    }
}
fn main() {
    let mut consult = Consult {
        database: Database::new(),
        store: Store::new(),
        reports: Vec::new(),
        counts: [[0; 3]; 2]
    };
    consult.read(0, &fs::read_to_string("input/prelude.pl").unwrap());
    consult.read(1, &fs::read_to_string("input/program.pl").unwrap());
    consult.undefined();
    let mut answers = Vec::new();
    let mut output = String::new();
    let mut statistics = Vec::new();
    let mut totals = [0usize; 4];
    let mut profile: BTreeMap<Indicator,
    (usize, usize)> = BTreeMap::new();
    for (i, line) in fs::read_to_string("input/queries.txt").unwrap().lines().enumerate() {
        answers.push(line.into());
        output.push_str(&format!("== query {} ==\n", i + 1));
        let at = line.find("?- ").unwrap();
        let limit = if at == 0 {
            None
        } else {
            Some(line[..at].trim().parse::<usize>().unwrap())
        };
        let start = at + 3;
        let tokens = reader::lex(&line[start..], start + 1);
        let mut store = consult.store.clone();
        match reader::clause(&tokens, 0, &mut store, true) {
            Err(error) => {
                answers.push(format!("syntax error at column {}: {}", error.column, error.message));
                statistics.push(format!("query {}: syntax error", i + 1));
            },
            Ok(parsed) => {
                let mut engine = Engine::new(&consult.database, &mut profile, store, parsed.term);
                engine.run(&parsed.variables, limit);
                answers.extend(engine.answers.iter().cloned());
                output.push_str(&engine.output);
                if !engine.output.is_empty() && !engine.output.ends_with('\n') {
                    output.push('\n');
                }
                statistics.push(format!("query {}: solutions={} inferences={} choicepoints={} backtracks={}", i + 1, engine.solutions, engine.inferences, engine.choicepoints, engine.backtracks));
                totals[0] += engine.solutions;
                totals[1] += engine.inferences;
                totals[2] += engine.choicepoints;
                totals[3] += engine.backtracks;
            }
        }
    }
    statistics.push(format!("total: solutions={} inferences={} choicepoints={} backtracks={}", totals[0], totals[1], totals[2], totals[3]));
    statistics.push("== profile ==".into());
    let mut entries: Vec<_> = profile.iter().filter(|e| (e.1).0 > 0).map(|(key, counts)| (indicator_text(key), key, counts)).collect();
    entries.sort_by(|a, b| (b.2).0.cmp(&(a.2).0).then_with(|| a.0.cmp(&b.0)));
    for (text, indicator, counts) in entries {
        statistics.push(if consult.database.find(indicator).is_some() {
            format!("{} calls={} tries={}", text, counts.0, counts.1)
        } else {
            format!("{} calls={}", text, counts.0)
        });
    }
    write("consult.txt", &lines_text(&consult.reports));
    write("listing.txt", &lines_text(&consult.listing()));
    write("answers.txt", &lines_text(&answers));
    write("write_output.txt", &output);
    write("stats.txt", &lines_text(&statistics));
}
