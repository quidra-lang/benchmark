use std::collections::BTreeMap;
#[derive(Clone, Debug)]
pub enum Term {
    Integer(i64),
    Atom(String),
    Variable(usize),
    Compound(String, Vec<Term>)
}
pub type Indicator = (String, usize);
impl Term {
    pub fn atom(name: &str) -> Self {
        Self::Atom(name.into())
    }
    pub fn compound(name: &str, arguments: Vec<Term>) -> Self {
        Self::Compound(name.into(), arguments)
    }
    pub fn indicator(&self) -> Option<Indicator> {
        match self {
            Self::Atom(name) => Some((name.clone(), 0)),
            Self::Compound(name, arguments) => Some((name.clone(), arguments.len())),
            _ => None
        }
    }
    pub fn arguments(&self) -> Vec<Term> {
        if let Self::Compound(_, arguments) = self {
            arguments.clone()
        } else {
            Vec::new()
        }
    }
}
#[derive(Clone)]
pub struct Store {
    pub bindings: Vec<Option<Term>>
}
impl Store {
    pub fn new() -> Self {
        Self {
            bindings: Vec::new()
        }
    }
    pub fn fresh(&mut self) -> Term {
        let id = self.bindings.len();
        self.bindings.push(None);
        Term::Variable(id)
    }
    pub fn dereference(&self, term: &Term) -> Term {
        let mut term = term.clone();
        while let Term::Variable(id) = term {
            if let Some(value) = &self.bindings[id] {
                term = value.clone();
            } else {
                break;
            }
        }
        term
    }
    pub fn copy(&mut self, term: &Term) -> Term {
        self.copy_with(term, &mut BTreeMap::new())
    }
    fn copy_with(&mut self, term: &Term, variables: &mut BTreeMap<usize, Term>) -> Term {
        match self.dereference(term) {
            Term::Variable(id) => {
                if let Some(value) = variables.get(&id) {
                    value.clone()
                } else {
                    let fresh = self.fresh();
                    variables.insert(id, fresh.clone());
                    fresh
                }
            },
            Term::Compound(name, arguments) => Term::Compound(name, arguments.iter().map(|a| self.copy_with(a, variables)).collect()),
            term => term
        }
    }
    pub fn copy_many(&mut self, terms: &[Term]) -> Vec<Term> {
        let mut variables = BTreeMap::new();
        terms.iter().map(|t| self.copy_with(t, &mut variables)).collect()
    }
    pub fn parts(&self, term: &Term) -> (Vec<Term>, Term) {
        let mut term = self.dereference(term);
        let mut elements = Vec::new();
        loop {
            match term {
                Term::Compound(ref name, ref arguments) if name == "." && arguments.len() == 2 => {
                    elements.push(arguments[0].clone());
                    term = self.dereference(&arguments[1]);
                },
                _ => return (elements, term)
            }
        }
    }
    pub fn variables(&self, terms: &[Term]) -> Vec<usize> {
        let mut pending: Vec<Term> = terms.iter().rev().cloned().collect();
        let mut variables = Vec::new();
        while let Some(term) = pending.pop() {
            match self.dereference(&term) {
                Term::Variable(id) => variables.push(id),
                Term::Compound(_, arguments) => pending.extend(arguments.into_iter().rev()),
                _ => ()
            }
        }
        variables
    }
}
pub fn list(elements: Vec<Term>, tail: Term) -> Term {
    elements.into_iter().rev().fold(tail, |tail, element| Term::compound(".", vec![element, tail]))
}
pub fn indicator_term(indicator: &Indicator) -> Term {
    Term::compound("/", vec![Term::Atom(indicator.0.clone()), Term::Integer(indicator.1 as i64)])
}
pub fn type_error(kind: &str, term: Term) -> Term {
    Term::compound("type_error", vec![Term::atom(kind), term])
}
pub fn domain_error(kind: &str, term: Term) -> Term {
    Term::compound("domain_error", vec![Term::atom(kind), term])
}
pub fn error_ball(error: Term, indicator: &Indicator) -> Term {
    Term::compound("error", vec![error, indicator_term(indicator)])
}
pub fn same_kind(a: &Term, b: &Term, store: &Store) -> bool {
    match (store.dereference(a), store.dereference(b)) {
        (Term::Variable(_), _) | (_, Term::Variable(_)) => true,
        (Term::Integer(a), Term::Integer(b)) => a == b,
        (Term::Atom(a), Term::Atom(b)) => a == b,
        (Term::Compound(a, aa), Term::Compound(b, ba)) => a == b && aa.len() == ba.len(),
        _ => false
    }
}
