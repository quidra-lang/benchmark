use std::collections::{BTreeMap, BTreeSet};
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Type { Integer, Boolean, String, Variable(usize), List(Box<Type>), Pair(Box<Type>, Box<Type>), Function(Box<Type>, Box<Type>) }
impl Type {
    pub fn list(ty: Type) -> Self { Self::List(Box::new(ty)) }
    pub fn pair(a: Type, b: Type) -> Self { Self::Pair(Box::new(a), Box::new(b)) }
    pub fn function(a: Type, b: Type) -> Self { Self::Function(Box::new(a), Box::new(b)) }
}
#[derive(Clone)]
pub struct Scheme { pub ty: Type, pub quantified: BTreeSet<usize> }
impl Scheme { pub fn mono(ty: Type) -> Self { Self { ty, quantified: BTreeSet::new() } } }
pub type Environment = BTreeMap<String, Scheme>;
#[derive(Clone)]
pub struct Failure { pub expected: Type, pub found: Type, pub occurs: bool, pub nested: bool }
pub struct Unifier { bindings: Vec<Option<Type>> }
impl Unifier {
    pub fn new() -> Self { Self { bindings: Vec::new() } }
    pub fn fresh(&mut self) -> Type { let index = self.bindings.len(); self.bindings.push(None); Type::Variable(index) }
    pub fn resolve(&self, ty: &Type) -> Type {
        match ty {
            Type::Variable(index) => if let Some(ty) = &self.bindings[*index] { self.resolve(ty) } else { ty.clone() },
            Type::List(ty) => Type::list(self.resolve(ty)),
            Type::Pair(a, b) => Type::pair(self.resolve(a), self.resolve(b)),
            Type::Function(a, b) => Type::function(self.resolve(a), self.resolve(b)),
            _ => ty.clone()
        }
    }
    pub fn variables(&self, ty: &Type) -> BTreeSet<usize> {
        fn collect(ty: &Type, out: &mut BTreeSet<usize>) {
            match ty { Type::Variable(i) => { out.insert(*i); }, Type::List(ty) => collect(ty, out), Type::Pair(a, b) | Type::Function(a, b) => { collect(a, out); collect(b, out); }, _ => () }
        }
        let mut out = BTreeSet::new(); collect(&self.resolve(ty), &mut out); out
    }
    pub fn bind(&mut self, index: usize, ty: Type) { self.bindings[index] = Some(ty); }
    pub fn unify(&mut self, expected: &Type, found: &Type) -> Result<(), Failure> { self.unify_at(expected, found, false) }
    fn unify_at(&mut self, expected: &Type, found: &Type, nested: bool) -> Result<(), Failure> {
        let expected = self.resolve(expected);
        let found = self.resolve(found);
        if expected == found { return Ok(()); }
        if let Type::Variable(index) = expected {
            if self.variables(&found).contains(&index) { return Err(Failure { expected: Type::Variable(index), found, occurs: true, nested }); }
            self.bind(index, found); return Ok(());
        }
        if let Type::Variable(index) = found {
            if self.variables(&expected).contains(&index) { return Err(Failure { expected, found: Type::Variable(index), occurs: true, nested }); }
            self.bind(index, expected); return Ok(());
        }
        match (&expected, &found) {
            (Type::List(a), Type::List(b)) => self.unify_at(a, b, true),
            (Type::Pair(a, b), Type::Pair(c, d)) | (Type::Function(a, b), Type::Function(c, d)) => { self.unify_at(a, c, true)?; self.unify_at(b, d, true) },
            _ => Err(Failure { expected, found, occurs: false, nested })
        }
    }
    pub fn generalize(&self, ty: Type, environment: &Environment) -> Scheme {
        let mut variables = self.variables(&ty);
        for scheme in environment.values() {
            for index in self.variables(&scheme.ty).difference(&scheme.quantified) { variables.remove(index); }
        }
        Scheme { ty, quantified: variables }
    }
    pub fn instantiate(&mut self, scheme: &Scheme) -> Type {
        let replacements: BTreeMap<_, _> = scheme.quantified.iter().map(|&i| (i, self.fresh())).collect();
        fn replace(ty: Type, replacements: &BTreeMap<usize, Type>) -> Type {
            match ty { Type::Variable(i) => replacements.get(&i).cloned().unwrap_or(Type::Variable(i)), Type::List(ty) => Type::list(replace(*ty, replacements)), Type::Pair(a, b) => Type::pair(replace(*a, replacements), replace(*b, replacements)), Type::Function(a, b) => Type::function(replace(*a, replacements), replace(*b, replacements)), _ => ty }
        }
        replace(self.resolve(&scheme.ty), &replacements)
    }
}
