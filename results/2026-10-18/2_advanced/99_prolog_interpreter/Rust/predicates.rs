use crate::terms::{
    Term,
    Store,
    Indicator,
    list,
    indicator_term,
    type_error,
    domain_error
};
use crate::unify::{
    Trail,
    identical
};
pub fn control(indicator: &Indicator) -> bool {
    matches!((indicator.0.as_str(), indicator.1), (",", 2) | ("!", 0) | (";", 2) | ("->", 2) | ("\\+", 1) | ("catch", 3)) || (indicator.0 == "call" && indicator.1 >= 1 && indicator.1 <= 8)
}
pub fn builtin(indicator: &Indicator) -> bool {
    matches!((indicator.0.as_str(), indicator.1), ("findall", 3) | ("throw", 1) | ("between", 3) | ("length", 2) | ("true", 0) | ("fail", 0) | ("false", 0) | ("=", 2) | ("\\=", 2) | ("==", 2) | ("\\==", 2) | ("var", 1) | ("nonvar", 1) | ("atom", 1) | ("number", 1) | ("integer", 1) | ("atomic", 1) | ("compound", 1) | ("callable", 1) | ("is_list", 1) | ("is", 2) | ("=:=", 2) | ("=\\=", 2) | ("<", 2) | (">", 2) | ("=<", 2) | (">=", 2) | ("functor", 3) | ("arg", 3) | ("=..", 2) | ("copy_term", 2) | ("atom_length", 2) | ("atom_chars", 2) | ("write", 1) | ("writeq", 1) | ("nl", 0))
}
pub fn integer(term: &Term, store: &Store) -> Result<i64, Term> {
    match store.dereference(term) {
        Term::Variable(_) => Err(Term::atom("instantiation_error")),
        Term::Integer(n) => Ok(n),
        term => Err(type_error("integer", term))
    }
}
fn atom(term: &Term, store: &Store) -> Result<String, Term> {
    match store.dereference(term) {
        Term::Variable(_) => Err(Term::atom("instantiation_error")),
        Term::Atom(name) => Ok(name),
        term => Err(type_error("atom", term))
    }
}
fn proper(term: &Term, store: &Store) -> Result<Vec<Term>, Term> {
    let (elements, tail) = store.parts(term);
    match tail {
        Term::Variable(_) => Err(Term::atom("instantiation_error")),
        Term::Atom(ref name) if name == "[]" => Ok(elements),
        _ => Err(type_error("list", term.clone()))
    }
}
pub fn arithmetic(term: &Term, store: &Store) -> Result<i64, Term> {
    let term = store.dereference(term);
    match term {
        Term::Variable(_) => Err(Term::atom("instantiation_error")),
        Term::Integer(n) => Ok(n),
        Term::Atom(name) => Err(type_error("evaluable", indicator_term(&(name, 0)))),
        Term::Compound(name, arguments) => {
            let valid = matches!((name.as_str(), arguments.len()), ("+", 2) | ("-", 2) | ("*", 2) | ("//", 2) | ("mod", 2) | ("rem", 2) | ("-", 1) | ("abs", 1) | ("min", 2) | ("max", 2));
            if !valid {
                return Err(type_error("evaluable", indicator_term(&(name, arguments.len()))));
            }
            let a = arithmetic(&arguments[0], store)?;
            let b = if arguments.len() == 2 {
                arithmetic(&arguments[1], store)?
            } else {
                0
            };
            if ["//", "mod", "rem"].contains(&name.as_str()) && b == 0 {
                return Err(Term::compound("evaluation_error", vec![Term::atom("zero_divisor")]));
            }
            let value = match name.as_str() {
                "+" => a + b,
                "-" if arguments.len() == 1 => -a,
                "-" => a - b,
                "*" => a * b,
                "//" => a / b,
                "rem" => a % b,
                "mod" => {
                    let mut quotient = a / b;
                    if a % b != 0 && (a < 0) != (b < 0) {
                        quotient -= 1;
                    }
                    a - b * quotient
                },
                "abs" => a.abs(),
                "min" => a.min(b),
                _ => a.max(b)
            };
            if !(-2147483648..=2147483647).contains(&value) {
                Err(Term::compound("evaluation_error", vec![Term::atom("int_overflow")]))
            } else {
                Ok(value)
            }
        }
    }
}
pub fn deterministic(indicator: &Indicator, arguments: &[Term], store: &mut Store, trail: &mut Trail, output: &mut String, writer: fn(&Term, &Store, bool) -> String) -> Result<bool, Term> {
    let name = indicator.0.as_str();
    match name {
        "true" => Ok(true),
        "fail" | "false" => Ok(false),
        "=" => Ok(trail.unify(&arguments[0], &arguments[1], store)),
        "\\=" => {
            let mark = trail.mark();
            let result = trail.unify(&arguments[0], &arguments[1], store);
            trail.undo(mark, store);
            Ok(!result)
        },
        "==" | "\\==" => Ok(identical(&arguments[0], &arguments[1], store) == (name == "==")),
        "var" | "nonvar" | "atom" | "number" | "integer" | "atomic" | "compound" | "callable" | "is_list" => {
            let term = store.dereference(&arguments[0]);
            Ok(match name {
                "var" => matches!(term, Term::Variable(_)),
                "nonvar" => !matches!(term, Term::Variable(_)),
                "atom" => matches!(term, Term::Atom(_)),
                "number" | "integer" => matches!(term, Term::Integer(_)),
                "atomic" => matches!(term, Term::Integer(_) | Term::Atom(_)),
                "compound" => matches!(term, Term::Compound(_, _)),
                "callable" => matches!(term, Term::Atom(_) | Term::Compound(_, _)),
                _ => matches!(store.parts(&term).1, Term::Atom(ref name) if name == "[]")
            })
        },
        "is" => {
            let value = arithmetic(&arguments[1], store)?;
            Ok(trail.unify(&arguments[0], &Term::Integer(value), store))
        },
        "=:=" | "=\\=" | "<" | ">" | "=<" | ">=" => {
            let a = arithmetic(&arguments[0], store)?;
            let b = arithmetic(&arguments[1], store)?;
            Ok(match name {
                "=:=" => a == b,
                "=\\=" => a != b,
                "<" => a < b,
                ">" => a > b,
                "=<" => a <= b,
                _ => a >= b
            })
        },
        "functor" => {
            let term = store.dereference(&arguments[0]);
            if !matches!(term, Term::Variable(_)) {
                let (functor, arity) = if let Term::Compound(name, args) = term {
                    (Term::Atom(name), args.len())
                } else {
                    (term, 0)
                };
                return Ok(trail.unify(&arguments[1], &functor, store) && trail.unify(&arguments[2], &Term::Integer(arity as i64), store));
            }
            let functor = store.dereference(&arguments[1]);
            let arity = store.dereference(&arguments[2]);
            if matches!(functor, Term::Variable(_)) || matches!(arity, Term::Variable(_)) {
                return Err(Term::atom("instantiation_error"));
            }
            if matches!(functor, Term::Compound(_, _)) {
                return Err(type_error("atomic", functor));
            }
            let arity = if let Term::Integer(arity) = arity {
                arity
            } else {
                return Err(type_error("integer", arity));
            };
            if arity < 0 {
                return Err(domain_error("not_less_than_zero", Term::Integer(arity)));
            }
            if arity > 255 {
                return Err(Term::compound("representation_error", vec![Term::atom("max_arity")]));
            }
            if arity == 0 {
                return Ok(trail.unify(&arguments[0], &functor, store));
            }
            let name = if let Term::Atom(name) = functor {
                name
            } else {
                return Err(type_error("atom", functor));
            };
            let args = (0..arity).map(|_| store.fresh()).collect();
            Ok(trail.unify(&arguments[0], &Term::Compound(name, args), store))
        },
        "arg" => {
            let n = store.dereference(&arguments[0]);
            let term = store.dereference(&arguments[1]);
            if matches!(n, Term::Variable(_)) || matches!(term, Term::Variable(_)) {
                return Err(Term::atom("instantiation_error"));
            }
            let n = if let Term::Integer(n) = n {
                n
            } else {
                return Err(type_error("integer", n));
            };
            let args = if let Term::Compound(_, args) = term {
                args
            } else {
                return Err(type_error("compound", term));
            };
            if n < 1 || n as usize > args.len() {
                Ok(false)
            } else {
                Ok(trail.unify(&args[n as usize - 1], &arguments[2], store))
            }
        },
        "=.." => {
            let term = store.dereference(&arguments[0]);
            if !matches!(term, Term::Variable(_)) {
                let elements = if let Term::Compound(name, args) = term {
                    let mut elements = vec![Term::Atom(name)];
                    elements.extend(args);
                    elements
                } else {
                    vec![term]
                };
                return Ok(trail.unify(&list(elements, Term::atom("[]")), &arguments[1], store));
            }
            let elements = proper(&arguments[1], store)?;
            if elements.is_empty() {
                return Err(domain_error("non_empty_list", Term::atom("[]")));
            }
            let head = store.dereference(&elements[0]);
            if matches!(head, Term::Variable(_)) {
                return Err(Term::atom("instantiation_error"));
            }
            if elements.len() == 1 {
                if matches!(head, Term::Compound(_, _)) {
                    return Err(type_error("atomic", head));
                }
                return Ok(trail.unify(&arguments[0], &head, store));
            }
            let name = if let Term::Atom(name) = head {
                name
            } else {
                return Err(type_error("atom", head));
            };
            if elements.len() - 1 > 255 {
                return Err(Term::compound("representation_error", vec![Term::atom("max_arity")]));
            }
            Ok(trail.unify(&arguments[0], &Term::Compound(name, elements[1..].to_vec()), store))
        },
        "copy_term" => {
            let copied = store.copy(&arguments[0]);
            Ok(trail.unify(&copied, &arguments[1], store))
        },
        "atom_length" => {
            let name = atom(&arguments[0], store)?;
            let n = store.dereference(&arguments[1]);
            if !matches!(n, Term::Variable(_) | Term::Integer(_)) {
                return Err(type_error("integer", n));
            }
            Ok(trail.unify(&Term::Integer(name.len() as i64), &arguments[1], store))
        },
        "atom_chars" => {
            if !matches!(store.dereference(&arguments[0]), Term::Variable(_)) {
                let name = atom(&arguments[0], store)?;
                let elements = name.chars().map(|c| Term::Atom(c.to_string())).collect();
                return Ok(trail.unify(&arguments[1], &list(elements, Term::atom("[]")), store));
            }
            let elements = proper(&arguments[1], store)?;
            let mut name = String::new();
            for element in elements {
                let element = store.dereference(&element);
                match element {
                    Term::Variable(_) => return Err(Term::atom("instantiation_error")),
                    Term::Atom(ref character) if character.len() == 1 => name.push_str(character),
                    _ => return Err(type_error("character", element))
                }
            }
            Ok(trail.unify(&arguments[0], &Term::Atom(name), store))
        },
        "write" | "writeq" => {
            output.push_str(&writer(&arguments[0], store, name == "writeq"));
            Ok(true)
        },
        "nl" => {
            output.push('\n');
            Ok(true)
        },
        _ => unreachable!()
    }
}
