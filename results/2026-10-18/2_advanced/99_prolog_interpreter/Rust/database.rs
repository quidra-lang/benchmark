use crate::terms::{
    Term,
    Store,
    Indicator,
    same_kind
};
#[derive(Clone)]
pub struct Clause {
    pub head: Term,
    pub body: Option<Term>,
    pub file: String,
    pub line: usize
}
pub struct Predicate {
    pub indicator: Indicator,
    pub clauses: Vec<Clause>
}
pub struct Database {
    pub predicates: Vec<Predicate>
}
impl Database {
    pub fn new() -> Self {
        Self {
            predicates: Vec::new()
        }
    }
    pub fn find(&self, indicator: &Indicator) -> Option<usize> {
        self.predicates.iter().position(|p| p.indicator == *indicator)
    }
    pub fn candidates(&self, index: usize, goal: &Term, store: &Store) -> Vec<usize> {
        let arguments = goal.arguments();
        self.predicates[index].clauses.iter().enumerate().filter(|(_, c)| arguments.is_empty() || same_kind(&arguments[0], &c.head.arguments()[0], store)).map(|(i, _)| i).collect()
    }
    pub fn copy(&self, predicate: usize, clause: usize, store: &mut Store) -> (Term, Option<Term>) {
        let clause = &self.predicates[predicate].clauses[clause];
        let mut terms = vec![clause.head.clone()];
        if let Some(body) = &clause.body {
            terms.push(body.clone());
        }
        let mut copied = store.copy_many(&terms);
        let body = if copied.len() > 1 {
            Some(copied.remove(1))
        } else {
            None
        };
        (copied.remove(0), body)
    }
}
