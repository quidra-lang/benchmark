static class Predicates {
    static readonly HashSet<Indicator> Controls = new() {
        new(",", 2), new("!", 0), new(";", 2), new("->", 2), new("\\+", 1), new("catch", 3)
    };
    static readonly Dictionary<string, int> Arities = new(StringComparer.Ordinal) {
        ["findall"] = 3, ["throw"] = 1, ["between"] = 3, ["length"] = 2, ["true"] = 0, ["fail"] = 0, ["false"] = 0, ["="] = 2, ["\\="] = 2, ["=="] = 2, ["\\=="] = 2, ["var"] = 1, ["nonvar"] = 1, ["atom"] = 1, ["number"] = 1, ["integer"] = 1, ["atomic"] = 1, ["compound"] = 1, ["callable"] = 1, ["is_list"] = 1, ["is"] = 2, ["=:="] = 2, ["=\\="] = 2, ["<"] = 2, [">"] = 2, ["=<"] = 2, [">="] = 2, ["functor"] = 3, ["arg"] = 3, ["=.."] = 2, ["copy_term"] = 2, ["atom_length"] = 2, ["atom_chars"] = 2, ["write"] = 1, ["writeq"] = 1, ["nl"] = 0
    };
    public static bool Control(Indicator key) => Controls.Contains(key) || key.Name == "call" && key.Arity >= 1 && key.Arity <= 8;
    public static bool Builtin(Indicator key) => Arities.TryGetValue(key.Name, out int arity) && arity == key.Arity;
    public static long Integer(Term term, Store store) {
        Term value = store.Dereference(term);
        return value is IntegerTerm number ? number.Value : throw new PrologError(value is VariableTerm ? new AtomTerm("instantiation_error") : Terms.TypeError("integer", value));
    }
    public static string Atom(Term term, Store store) {
        Term value = store.Dereference(term);
        return value is AtomTerm atom ? atom.Name : throw new PrologError(value is VariableTerm ? new AtomTerm("instantiation_error") : Terms.TypeError("atom", value));
    }
    static List<Term> Proper(Term term, Store store) {
        var (elements, tail) = store.Parts(term);
        if (tail.Nil) return elements;
        throw new PrologError(tail is VariableTerm ? new AtomTerm("instantiation_error") : Terms.TypeError("list", term));
    }
    static long Arithmetic(Term term, Store store) {
        Term value = store.Dereference(term);
        if (value is VariableTerm) throw new PrologError(new AtomTerm("instantiation_error"));
        if (value is IntegerTerm number) return number.Value;
        if (value is AtomTerm atom) throw new PrologError(Terms.TypeError("evaluable", Terms.IndicatorTerm(new(atom.Name, 0))));
        CompoundTerm compound = (CompoundTerm)value;
        string name = compound.Name;
        List<Term> args = compound.Args;
        bool valid = args.Count == 2 && new[] {
            "+", "-", "*", "//", "mod", "rem", "min", "max"
        }.Contains(name) || args.Count == 1 && name is "-" or "abs";
        if (!valid) throw new PrologError(Terms.TypeError("evaluable", Terms.IndicatorTerm(new(name, args.Count))));
        long a = Arithmetic(args[0], store), b = args.Count == 2 ? Arithmetic(args[1], store) : 0;
        if (name is "//" or "mod" or "rem" && b == 0) throw new PrologError(new CompoundTerm("evaluation_error", new() {
            new AtomTerm("zero_divisor")
        }));
        long result;
        switch (name) {
            case "+": result = a + b;
            break;
            case "-": result = args.Count == 1 ? -a : a - b;
            break;
            case "*": result = a * b;
            break;
            case "//": result = a / b;
            break;
            case "rem": result = a % b;
            break;
            case "mod": long quotient = a / b;
            if (a % b != 0 && (a < 0) != (b < 0)) quotient--;
            result = a - b * quotient;
            break;
            case "abs": result = Math.Abs(a);
            break;
            case "min": result = Math.Min(a, b);
            break;
            default: result = Math.Max(a, b);
            break;
        }
        if (result < int.MinValue || result > int.MaxValue) throw new PrologError(new CompoundTerm("evaluation_error", new() {
            new AtomTerm("int_overflow")
        }));
        return result;
    }
    public static bool Deterministic(Indicator key, List<Term> args, Store store, Trail trail, StringBuilder output) {
        string name = key.Name;
        switch (name) {
            case "true": return true;
            case "fail": case "false": return false;
            case "=": return trail.Unify(args[0], args[1], store);
            case "\\=": {
                int mark = trail.Mark;
                bool result = trail.Unify(args[0], args[1], store);
                trail.Undo(mark, store);
                return !result;
            }
            case "==": case "\\==": return Trail.Identical(args[0], args[1], store) == (name == "==");
            case "var": case "nonvar": case "atom": case "number": case "integer": case "atomic": case "compound": case "callable": case "is_list": {
                Term term = store.Dereference(args[0]);
                return name switch {
                    "var" => term is VariableTerm, "nonvar" => term is not VariableTerm, "atom" => term is AtomTerm, "number" or "integer" => term is IntegerTerm, "atomic" => term is IntegerTerm or AtomTerm, "compound" => term is CompoundTerm, "callable" => term.Indicator.HasValue, _ => store.Parts(term).Tail.Nil
                };
            }
            case "is": return trail.Unify(args[0], new IntegerTerm(Arithmetic(args[1], store)), store);
            case "=:=": case "=\\=": case "<": case ">": case "=<": case ">=": {
                long a = Arithmetic(args[0], store), b = Arithmetic(args[1], store);
                return name switch {
                    "=:=" => a == b, "=\\=" => a != b, "<" => a < b, ">" => a > b, "=<" => a <= b, _ => a >= b
                };
            }
            case "functor": {
                Term term = store.Dereference(args[0]);
                if (term is not VariableTerm) {
                    Term functorValue = term is CompoundTerm compound ? new AtomTerm(compound.Name) : term;
                    int count = term is CompoundTerm value ? value.Args.Count : 0;
                    return trail.Unify(args[1], functorValue, store) && trail.Unify(args[2], new IntegerTerm(count), store);
                }
                Term functor = store.Dereference(args[1]), arity = store.Dereference(args[2]);
                if (functor is VariableTerm || arity is VariableTerm) throw new PrologError(new AtomTerm("instantiation_error"));
                if (functor is CompoundTerm) throw new PrologError(Terms.TypeError("atomic", functor));
                if (arity is not IntegerTerm n) throw new PrologError(Terms.TypeError("integer", arity));
                if (n.Value < 0) throw new PrologError(Terms.DomainError("not_less_than_zero", arity));
                if (n.Value > 255) throw new PrologError(new CompoundTerm("representation_error", new() {
                    new AtomTerm("max_arity")
                }));
                if (n.Value == 0) return trail.Unify(args[0], functor, store);
                if (functor is not AtomTerm atom) throw new PrologError(Terms.TypeError("atom", functor));
                return trail.Unify(args[0], new CompoundTerm(atom.Name, Enumerable.Range(0, (int)n.Value).Select(_ => store.Fresh()).ToList()), store);
            }
            case "arg": {
                Term n = store.Dereference(args[0]), term = store.Dereference(args[1]);
                if (n is VariableTerm || term is VariableTerm) throw new PrologError(new AtomTerm("instantiation_error"));
                if (n is not IntegerTerm number) throw new PrologError(Terms.TypeError("integer", n));
                if (term is not CompoundTerm compound) throw new PrologError(Terms.TypeError("compound", term));
                return number.Value >= 1 && number.Value <= compound.Args.Count && trail.Unify(compound.Args[(int)number.Value - 1], args[2], store);
            }
            case "=..": {
                Term term = store.Dereference(args[0]);
                if (term is not VariableTerm) {
                    List<Term> parts = term is CompoundTerm compound ? new[] {
                        new AtomTerm(compound.Name)
                    }.Cast<Term>().Concat(compound.Args).ToList() : new() {
                        term
                    };
                    return trail.Unify(Terms.List(parts), args[1], store);
                }
                List<Term> values = Proper(args[1], store);
                if (values.Count == 0) throw new PrologError(Terms.DomainError("non_empty_list", new AtomTerm("[]")));
                Term head = store.Dereference(values[0]);
                if (head is VariableTerm) throw new PrologError(new AtomTerm("instantiation_error"));
                if (values.Count == 1) {
                    if (head is CompoundTerm) throw new PrologError(Terms.TypeError("atomic", head));
                    return trail.Unify(args[0], head, store);
                } if (head is not AtomTerm atom) throw new PrologError(Terms.TypeError("atom", head));
                if (values.Count - 1 > 255) throw new PrologError(new CompoundTerm("representation_error", new() {
                    new AtomTerm("max_arity")
                }));
                return trail.Unify(args[0], new CompoundTerm(atom.Name, values.Skip(1).ToList()), store);
            }
            case "copy_term": return trail.Unify(store.Copy(args[0]), args[1], store);
            case "atom_length": {
                string text = Atom(args[0], store);
                Term n = store.Dereference(args[1]);
                if (n is not (VariableTerm or IntegerTerm)) throw new PrologError(Terms.TypeError("integer", n));
                return trail.Unify(new IntegerTerm(text.Length), args[1], store);
            }
            case "atom_chars": {
                if (store.Dereference(args[0]) is not VariableTerm) {
                    string text = Atom(args[0], store);
                    return trail.Unify(args[1], Terms.List(text.Select(c => new AtomTerm(c.ToString()))), store);
                }
                List<Term> values = Proper(args[1], store);
                StringBuilder textValue = new();
                foreach (Term source in values) {
                    Term value = store.Dereference(source);
                    if (value is VariableTerm) throw new PrologError(new AtomTerm("instantiation_error"));
                    if (value is not AtomTerm character || character.Name.Length != 1) throw new PrologError(Terms.TypeError("character", value));
                    textValue.Append(character.Name);
                } return trail.Unify(args[0], new AtomTerm(textValue.ToString()), store);
            }
            case "write": case "writeq": output.Append(Writer.WriteTerm(args[0], store, name == "writeq"));
            return true;
            case "nl": output.Append((char)10);
            return true;
            default: throw new InvalidOperationException();
        }
    }
}
