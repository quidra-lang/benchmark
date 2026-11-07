use crate::terms::{
    Term,
    Store
};
pub struct Trail {
    bindings: Vec<usize>
}
impl Trail {
    pub fn new() -> Self {
        Self {
            bindings: Vec::new()
        }
    }
    pub fn mark(&self) -> usize {
        self.bindings.len()
    }
    pub fn undo(&mut self, mark: usize, store: &mut Store) {
        while self.bindings.len() > mark {
            let id = self.bindings.pop().unwrap();
            store.bindings[id] = None;
        }
    }
    pub fn unify(&mut self, a: &Term, b: &Term, store: &mut Store) -> bool {
        let mut pending = vec![(a.clone(), b.clone())];
        while let Some((a, b)) = pending.pop() {
            let a = store.dereference(&a);
            let b = store.dereference(&b);
            match (a, b) {
                (Term::Variable(a), Term::Variable(b)) if a == b => (),
                (Term::Variable(id), term) | (term, Term::Variable(id)) => {
                    store.bindings[id] = Some(term);
                    self.bindings.push(id);
                },
                (Term::Integer(a), Term::Integer(b)) if a == b => (),
                (Term::Atom(a), Term::Atom(b)) if a == b => (),
                (Term::Compound(a, aa), Term::Compound(b, ba)) if a == b && aa.len() == ba.len() => pending.extend(aa.into_iter().zip(ba).rev()),
                _ => return false
            }
        }
        true
    }
}
pub fn identical(a: &Term, b: &Term, store: &Store) -> bool {
    let mut pending = vec![(a.clone(), b.clone())];
    while let Some((a, b)) = pending.pop() {
        match (store.dereference(&a), store.dereference(&b)) {
            (Term::Variable(a), Term::Variable(b)) if a == b => (),
            (Term::Integer(a), Term::Integer(b)) if a == b => (),
            (Term::Atom(a), Term::Atom(b)) if a == b => (),
            (Term::Compound(a, aa), Term::Compound(b, ba)) if a == b && aa.len() == ba.len() => pending.extend(aa.into_iter().zip(ba).rev()),
            _ => return false
        }
    }
    true
}
