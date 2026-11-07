import java.util.*;
final class Predicates {
    static final Set<Terms.Indicator> DETERMINISTIC = new HashSet<>();
    static {
        add(0, "true", "fail", "false", "nl");
        add(1, "var", "nonvar", "atom", "number", "integer", "atomic", "compound", "callable",
            "is_list", "write", "writeq");
        add(2, "=", "\\=", "==", "\\==", "is", "=:=", "=\\=", "<", ">", "=<", ">=", "=..",
            "copy_term", "atom_length", "atom_chars");
        add(3, "functor", "arg");
    }
    static void add(int arity, String... names) {
        for (String name : names)
            DETERMINISTIC.add(new Terms.Indicator(name, arity));
    }
    static int checked(long value) {
        if (value < Integer.MIN_VALUE || value > Integer.MAX_VALUE)
            throw new Terms.Fault(Terms.compound("evaluation_error", Terms.atom("int_overflow")));
        return (int)value;
    }
    static int evaluate(Terms.Term term) {
        term = Terms.dereference(term);
        if (term instanceof Terms.Variable)
            throw new Terms.Fault(Terms.INSTANTIATION);
        if (term instanceof Terms.IntegerTerm integer)
            return integer.value();
        Terms.Indicator key = Terms.indicator(term);
        if (term instanceof Terms.Atom)
            throw new Terms.Fault(Terms.typeError("evaluable", Terms.indicatorTerm(key)));
        Terms.Compound compound = (Terms.Compound)term;
        boolean supported =
            key.arity() == 1 && (key.name().equals("-") || key.name().equals("abs")) ||
            key.arity() == 2 &&
                Set.of("+", "-", "*", "//", "mod", "rem", "min", "max").contains(key.name());
        if (!supported)
            throw new Terms.Fault(Terms.typeError("evaluable", Terms.indicatorTerm(key)));
        long first = evaluate(compound.args().getFirst());
        if (key.arity() == 1)
            return checked(key.name().equals("-") ? -first : Math.abs(first));
        long second = evaluate(compound.args().get(1));
        if (Set.of("//", "mod", "rem").contains(key.name()) && second == 0)
            throw new Terms.Fault(Terms.compound("evaluation_error", Terms.atom("zero_divisor")));
        return checked(switch (key.name()) {
            case "+" -> first + second;
            case "-" -> first - second;
            case "*" -> first *second;
            case "//" -> first / second;
            case "mod" -> Math.floorMod(first, second);
            case "rem" -> first % second;
            case "min" -> Math.min(first, second);
            default -> Math.max(first, second);
        });
    }
    static int requireInteger(Terms.Term term) {
        term = Terms.dereference(term);
        if (term instanceof Terms.Variable)
            throw new Terms.Fault(Terms.INSTANTIATION);
        if (!(term instanceof Terms.IntegerTerm integer))
            throw new Terms.Fault(Terms.typeError("integer", term));
        return integer.value();
    }
    static String requireAtom(Terms.Term term) {
        term = Terms.dereference(term);
        if (term instanceof Terms.Variable)
            throw new Terms.Fault(Terms.INSTANTIATION);
        if (!(term instanceof Terms.Atom atom))
            throw new Terms.Fault(Terms.typeError("atom", term));
        return atom.name();
    }
    static List<Terms.Term> requireList(Terms.Term term) {
        Terms.ListParts parts = Terms.listParts(term);
        if (parts.tail() instanceof Terms.Variable)
            throw new Terms.Fault(Terms.INSTANTIATION);
        if (!Terms.atomIs(parts.tail(), "[]"))
            throw new Terms.Fault(Terms.typeError("list", term));
        return parts.elements();
    }
    interface Output {
        void write(Terms.Term term, boolean quoted);
    }
    static boolean execute(Terms.Term goal, Unify.Trail trail, Output output) {
        String name = Terms.indicator(goal).name();
        List<Terms.Term> args = Terms.args(goal).stream().map(Terms::dereference).toList();
        switch (name) {
        case "true":
            return true;
        case "fail", "false":
            return false;
        case "=":
            return trail.unify(args.get(0), args.get(1));
        case "\\=": {
            int mark = trail.mark();
            boolean result = trail.unify(args.get(0), args.get(1));
            trail.undo(mark);
            return !result;
        }
        case "==", "\\==": {
            boolean result = Unify.identical(args.get(0), args.get(1));
            return name.equals("==") == result;
        }
        case "var", "nonvar", "atom", "number", "integer", "atomic", "compound", "callable",
            "is_list": {
            Terms.Term term = args.getFirst();
            return switch (name) {
                case "var" -> term instanceof Terms.Variable;
                case "nonvar" -> !(term instanceof Terms.Variable);
                case "atom" -> term instanceof Terms.Atom;
                case "number", "integer" -> term instanceof Terms.IntegerTerm;
                case "atomic" -> term instanceof Terms.Atom || term instanceof Terms.IntegerTerm;
                case "compound" -> term instanceof Terms.Compound;
                case "callable" -> term instanceof Terms.Atom || term instanceof Terms.Compound;
                default -> Terms.atomIs(Terms.listParts(term).tail(), "[]");
            };
        }
        case "is":
            return trail.unify(args.get(0), Terms.integer(evaluate(args.get(1))));
        case "=:=", "=\\=", "<", ">", "=<", ">=": {
            int first = evaluate(args.get(0)), second = evaluate(args.get(1));
            return switch (name) {
                case "=:=" -> first == second;
                case "=\\=" -> first != second;
                case "<" -> first < second;
                case ">" -> first > second;
                case "=<" -> first <= second;
                default -> first >= second;
            };
        }
        case "functor": {
            Terms.Term term = args.get(0), functor = args.get(1), count = args.get(2);
            if (!(term instanceof Terms.Variable)) {
                if (term instanceof Terms.Compound compound)
                    return trail.unify(functor, Terms.atom(compound.name())) &&
                        trail.unify(count, Terms.integer(compound.args().size()));
                return trail.unify(functor, term) && trail.unify(count, Terms.integer(0));
            }
            if (functor instanceof Terms.Variable || count instanceof Terms.Variable)
                throw new Terms.Fault(Terms.INSTANTIATION);
            if (functor instanceof Terms.Compound)
                throw new Terms.Fault(Terms.typeError("atomic", functor));
            if (!(count instanceof Terms.IntegerTerm integer))
                throw new Terms.Fault(Terms.typeError("integer", count));
            int arity = integer.value();
            if (arity < 0)
                throw new Terms.Fault(Terms.domainError("not_less_than_zero", count));
            if (arity > 255)
                throw new Terms.Fault(
                    Terms.compound("representation_error", Terms.atom("max_arity")));
            if (arity == 0)
                return trail.unify(term, functor);
            if (functor instanceof Terms.IntegerTerm)
                throw new Terms.Fault(Terms.typeError("atom", functor));
            List<Terms.Term> fresh = new ArrayList<>();
            for (int i = 0; i < arity; i++)
                fresh.add(new Terms.Variable());
            return trail.unify(term, new Terms.Compound(((Terms.Atom)functor).name(), fresh));
        }
        case "arg": {
            Terms.Term number = args.get(0), term = args.get(1);
            if (number instanceof Terms.Variable || term instanceof Terms.Variable)
                throw new Terms.Fault(Terms.INSTANTIATION);
            if (!(number instanceof Terms.IntegerTerm integer))
                throw new Terms.Fault(Terms.typeError("integer", number));
            if (!(term instanceof Terms.Compound compound))
                throw new Terms.Fault(Terms.typeError("compound", term));
            return integer.value() >= 1 && integer.value() <= compound.args().size() &&
                trail.unify(compound.args().get(integer.value() - 1), args.get(2));
        }
        case "=..": {
            Terms.Term term = args.get(0), sequence = args.get(1);
            if (term instanceof Terms.Compound compound) {
                List<Terms.Term> elements = new ArrayList<>();
                elements.add(Terms.atom(compound.name()));
                elements.addAll(compound.args());
                return trail.unify(Terms.list(elements), sequence);
            }
            if (!(term instanceof Terms.Variable))
                return trail.unify(Terms.list(List.of(term)), sequence);
            List<Terms.Term> elements = requireList(sequence);
            if (elements.isEmpty())
                throw new Terms.Fault(Terms.domainError("non_empty_list", Terms.NIL));
            Terms.Term head = Terms.dereference(elements.getFirst());
            if (head instanceof Terms.Variable)
                throw new Terms.Fault(Terms.INSTANTIATION);
            if (elements.size() == 1) {
                if (head instanceof Terms.Compound)
                    throw new Terms.Fault(Terms.typeError("atomic", head));
                return trail.unify(term, head);
            }
            if (!(head instanceof Terms.Atom atom))
                throw new Terms.Fault(Terms.typeError("atom", head));
            if (elements.size() > 256)
                throw new Terms.Fault(
                    Terms.compound("representation_error", Terms.atom("max_arity")));
            return trail.unify(
                term, new Terms.Compound(atom.name(),
                                         new ArrayList<>(elements.subList(1, elements.size()))));
        }
        case "copy_term":
            return trail.unify(Terms.copy(args.get(0)), args.get(1));
        case "atom_length": {
            String atom = requireAtom(args.get(0));
            Terms.Term count = args.get(1);
            if (!(count instanceof Terms.Variable) && !(count instanceof Terms.IntegerTerm))
                throw new Terms.Fault(Terms.typeError("integer", count));
            return trail.unify(Terms.integer(atom.length()), count);
        }
        case "atom_chars": {
            Terms.Term atom = args.get(0), sequence = args.get(1);
            if (!(atom instanceof Terms.Variable)) {
                String text = requireAtom(atom);
                List<Terms.Term> elements = new ArrayList<>();
                for (int i = 0; i < text.length(); i++)
                    elements.add(Terms.atom(text.substring(i, i + 1)));
                return trail.unify(sequence, Terms.list(elements));
            }
            List<Terms.Term> elements = requireList(sequence);
            StringBuilder text = new StringBuilder();
            for (Terms.Term element : elements) {
                Terms.Term character = Terms.dereference(element);
                if (character instanceof Terms.Variable)
                    throw new Terms.Fault(Terms.INSTANTIATION);
                if (!(character instanceof Terms.Atom a) || a.name().length() != 1)
                    throw new Terms.Fault(Terms.typeError("character", character));
                text.append(a.name());
            }
            return trail.unify(atom, Terms.atom(text.toString()));
        }
        case "write", "writeq":
            output.write(args.getFirst(), name.equals("writeq"));
            return true;
        case "nl":
            output.write(null, false);
            return true;
        default:
            throw new AssertionError();
        }
    }
}
