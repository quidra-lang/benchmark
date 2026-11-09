import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
public final class Main {
    static final Set<Terms.Indicator> CONTROLS = new HashSet<>(),
                                      BUILTINS = new HashSet<>(Predicates.DETERMINISTIC);
    static {
        for (String name : List.of(",", ";", "->"))
            CONTROLS.add(new Terms.Indicator(name, 2));
        CONTROLS.add(new Terms.Indicator("!", 0));
        CONTROLS.add(new Terms.Indicator("\\+", 1));
        CONTROLS.add(new Terms.Indicator("catch", 3));
        for (int arity = 1; arity <= 8; arity++)
            CONTROLS.add(new Terms.Indicator("call", arity));
        for (Terms.Indicator key :
             List.of(new Terms.Indicator("findall", 3), new Terms.Indicator("throw", 1),
                     new Terms.Indicator("between", 3), new Terms.Indicator("length", 2)))
            BUILTINS.add(key);
    }
    static boolean is(Terms.Term term, String name, int arity) {
        term = Terms.dereference(term);
        return (term instanceof Terms.Atom || term instanceof Terms.Compound) &&
            Terms.indicator(term).equals(new Terms.Indicator(name, arity));
    }
    static Terms.Term convert(Terms.Term term) {
        term = Terms.dereference(term);
        if (term instanceof Terms.Variable)
            return Terms.compound("call", term);
        if (term instanceof Terms.IntegerTerm)
            return null;
        if (term instanceof Terms.Compound compound && compound.args().size() == 2 &&
            Set.of(",", ";", "->").contains(compound.name())) {
            Terms.Term first = convert(compound.args().get(0));
            if (first == null)
                return null;
            Terms.Term second = convert(compound.args().get(1));
            return second == null ? null : Terms.compound(compound.name(), first, second);
        }
        return term;
    }
    static String atomName(String name, boolean quoted) {
        boolean plain = Set.of("[]", "!", ";").contains(name);
        if (!name.isEmpty() && Reader.lower(name.charAt(0))) {
            boolean valid = true;
            for (int i = 1; i < name.length(); i++)
                if (!Reader.alphanumeric(name.charAt(i)))
                    valid = false;
            plain |= valid;
        }
        if (!name.isEmpty() && !name.equals(".")) {
            boolean valid = true;
            for (int i = 0; i < name.length(); i++)
                if (Reader.SYMBOLS.indexOf(name.charAt(i)) < 0)
                    valid = false;
            plain |= valid;
        }
        return !quoted || plain ? name
                                : "'" +
                                      name.replace("\\", "\\\\")
                                          .replace("'", "\\'")
                                          .replace("\n", "\\n")
                                          .replace("\t", "\\t") +
                                      "'";
    }
    static final class Writer {
        final Map<Terms.Variable, String> names = new IdentityHashMap<>();
        int nextName = 1;
        final boolean quoted;
        Writer() { quoted = true; }
        Writer(boolean quoted) { this.quoted = quoted; }
        Writer(Map<Terms.Variable, String> names) {
            this.names.putAll(names);
            quoted = true;
        }
        String write(Terms.Term term) { return write(term, 1200, false); }
        String write(Terms.Term term, int limit, boolean operand) {
            term = Terms.dereference(term);
            if (term instanceof Terms.Variable variable)
                return names.computeIfAbsent(variable, key -> "_G" + (nextName++));
            if (term instanceof Terms.IntegerTerm integer)
                return Integer.toString(integer.value());
            if (term instanceof Terms.Atom atom) {
                String text = atomName(atom.name(), quoted);
                return operand && (Reader.INFIX.containsKey(atom.name()) ||
                                   Reader.PREFIX.containsKey(atom.name()))
                    ? "(" + text + ")"
                    : text;
            }
            Terms.Compound compound = (Terms.Compound)term;
            String name = compound.name();
            List<Terms.Term> args = compound.args();
            if (name.equals(".") && args.size() == 2) {
                Terms.ListParts parts = Terms.listParts(term);
                StringJoiner elements = new StringJoiner(",");
                for (Terms.Term element : parts.elements())
                    elements.add(write(element, 999, false));
                String text = "[" + elements;
                if (!Terms.atomIs(parts.tail(), "[]"))
                    text += "|" + write(parts.tail(), 999, false);
                return text + "]";
            }
            if (args.size() == 2 && Reader.INFIX.containsKey(name)) {
                Reader.Operator op = Reader.INFIX.get(name);
                String first = write(args.get(0), op.left(), true),
                       second = write(args.get(1), op.right(), true), text;
                if (name.equals(","))
                    text = first + "," + second;
                else if (Reader.lower(name.charAt(0)) || Reader.upper(name.charAt(0)))
                    text = first + " " + name + " " + second;
                else {
                    String before = !first.isEmpty() && Reader.SYMBOLS.indexOf(
                                                            first.charAt(first.length() - 1)) >= 0
                                        ? " "
                                        : "",
                           after =
                               !second.isEmpty() && Reader.SYMBOLS.indexOf(second.charAt(0)) >= 0
                                   ? " "
                                   : "";
                    text = first + before + name + after + second;
                }
                return op.priority() > limit ? "(" + text + ")" : text;
            }
            if (args.size() == 1 && Reader.PREFIX.containsKey(name)) {
                int priority = Reader.PREFIX.get(name);
                String argument = write(args.getFirst(), priority, true);
                String space =
                    !argument.isEmpty() &&
                            (Reader.SYMBOLS.indexOf(argument.charAt(0)) >= 0 ||
                             Reader.digit(argument.charAt(0)) || argument.charAt(0) == '(')
                        ? " "
                        : "";
                String text = name + space + argument;
                return priority > limit ? "(" + text + ")" : text;
            }
            StringJoiner arguments = new StringJoiner(",");
            for (Terms.Term argument : args)
                arguments.add(write(argument, 999, false));
            return atomName(name, quoted) + "(" + arguments + ")";
        }
    }
    static String predicateName(Terms.Indicator key) {
        return new Writer().write(Terms.indicatorTerm(key));
    }
    record FilePredicate(String file, Terms.Indicator indicator) {}
    static final class Consultant {
        final Database database = new Database();
        final List<String> reports = new ArrayList<>();
        final LinkedHashMap<String, int[]> counts = new LinkedHashMap<>();
        final Map<String, Terms.Indicator> last = new HashMap<>();
        final Set<FilePredicate> discontiguous = new HashSet<>();
        Consultant() {
            counts.put("prelude.pl", new int[3]);
            counts.put("program.pl", new int[3]);
        }
        void warning(String file, int line, String message) {
            reports.add(file + ":" + line + ": warning: " + message);
            counts.get(file)[2]++;
        }
        void add(Terms.Term term, String file, int line, Reader reader) {
            Terms.Term head = term, body = null;
            if (is(term, ":-", 2)) {
                head = Terms.args(term).get(0);
                body = Terms.args(term).get(1);
            }
            Terms.Term error = null;
            if (head instanceof Terms.Variable)
                error = Terms.INSTANTIATION;
            else if (head instanceof Terms.IntegerTerm)
                error = Terms.typeError("callable", head);
            else if (CONTROLS.contains(Terms.indicator(head)) ||
                     BUILTINS.contains(Terms.indicator(head)))
                error = Terms.compound("permission_error", Terms.atom("modify"),
                                       Terms.atom("static_procedure"),
                                       Terms.indicatorTerm(Terms.indicator(head)));
            else if (body != null) {
                Terms.Term converted = convert(body);
                if (converted == null)
                    error = Terms.typeError("callable", body);
                else
                    body = converted;
            }
            if (error != null) {
                reports.add(file + ":" + line + ": error: " + new Writer().write(error));
                counts.get(file)[1]++;
                return;
            }
            Terms.Indicator key = Terms.indicator(head);
            List<Database.Clause> previous = database.predicates.getOrDefault(key, List.of());
            if (file.equals("program.pl") &&
                previous.stream().anyMatch(clause -> clause.file().equals("prelude.pl"))) {
                warning(file, line, "redefining prelude procedure " + predicateName(key));
                database.predicates.put(key, new ArrayList<>());
                previous = List.of();
            }
            if (previous.stream().anyMatch(clause -> clause.file().equals(file)) &&
                !key.equals(last.get(file)) &&
                !discontiguous.contains(new FilePredicate(file, key))) {
                warning(file, line, "clauses of " + predicateName(key) + " are not together");
                discontiguous.add(new FilePredicate(file, key));
            }
            database.add(new Database.Clause(head, body, file, line));
            last.put(file, key);
            counts.get(file)[0]++;
            List<String> singletons = new ArrayList<>(), repeated = new ArrayList<>();
            for (var entry : reader.counts.entrySet()) {
                String name = entry.getKey();
                if (!name.startsWith("_") && entry.getValue() == 1)
                    singletons.add(name);
                if (name.length() > 1 && name.startsWith("_") && entry.getValue() > 1)
                    repeated.add(name);
            }
            if (!singletons.isEmpty())
                warning(file, line, "singleton variables: " + String.join(", ", singletons));
            if (!repeated.isEmpty())
                warning(file, line,
                        "variables starting with _ occur more than once: " +
                            String.join(", ", repeated));
        }
        void consult(String file, String text) {
            Reader reader = new Reader(text);
            List<String> source = text.lines().toList();
            while (reader.peek().kind() != Reader.Kind.EOF) {
                int line = reader.peek().line();
                try {
                    add(reader.clause(false), file, line, reader);
                } catch (Reader.SyntaxIssue issue) {
                    Reader.Token token = issue.token;
                    counts.get(file)[1]++;
                    reports.add(file + ":" + token.line() + ":" + token.column() +
                                ": syntax error: " + issue.getMessage());
                    if (token.kind() != Reader.Kind.EOF) {
                        reports.add("    " + source.get(token.line() - 1));
                        reports.add(" ".repeat(token.column() + 3) + "^");
                    }
                    reader.position = token.index();
                    while (reader.peek().kind() != Reader.Kind.END &&
                           reader.peek().kind() != Reader.Kind.EOF)
                        reader.take();
                    if (reader.peek().kind() == Reader.Kind.END)
                        reader.take();
                }
            }
        }
        void finish() {
            Set<Terms.Indicator> reported = new HashSet<>();
            for (var entry : database.predicates.entrySet())
                for (Database.Clause clause : entry.getValue()) {
                    Deque<Terms.Term> pending = new ArrayDeque<>();
                    if (clause.body() != null)
                        pending.push(clause.body());
                    while (!pending.isEmpty()) {
                        Terms.Term term = Terms.dereference(pending.pop());
                        if (term instanceof Terms.Variable || term instanceof Terms.IntegerTerm)
                            continue;
                        Terms.Indicator key = Terms.indicator(term);
                        List<Terms.Term> args = Terms.args(term);
                        if (key.arity() == 2 && Set.of(",", ";", "->").contains(key.name())) {
                            pending.push(args.get(1));
                            pending.push(args.get(0));
                        } else if (key.equals(new Terms.Indicator("\\+", 1)) ||
                                   key.equals(new Terms.Indicator("call", 1)))
                            pending.push(args.get(0));
                        else if (key.equals(new Terms.Indicator("findall", 3)))
                            pending.push(args.get(1));
                        else if (key.equals(new Terms.Indicator("catch", 3))) {
                            pending.push(args.get(2));
                            pending.push(args.get(0));
                        } else if (!CONTROLS.contains(key) && !BUILTINS.contains(key) &&
                                   !database.predicates.containsKey(key) && reported.add(key))
                            warning(clause.file(), clause.line(),
                                    "undefined procedure " + predicateName(key) + " called from " +
                                        predicateName(entry.getKey()));
                    }
                }
            for (var entry : counts.entrySet()) {
                int[] values = entry.getValue();
                reports.add(entry.getKey() + ": clauses=" + values[0] + " errors=" + values[1] +
                            " warnings=" + values[2]);
            }
            reports.add("database: predicates=" + database.predicates.size() + " clauses=" +
                        database.predicates.values().stream().mapToInt(List::size).sum());
        }
    }
    static List<String> listing(Database database) {
        List<String> result = new ArrayList<>();
        for (List<Database.Clause> clauses : database.predicates.values()) {
            if (!result.isEmpty())
                result.add("");
            for (Database.Clause clause : clauses) {
                List<Terms.Variable> occurrences = Terms.variables(clause.head(), clause.body());
                Map<Terms.Variable, Integer> counts = new IdentityHashMap<>();
                for (Terms.Variable variable : occurrences)
                    counts.merge(variable, 1, Integer::sum);
                Map<Terms.Variable, String> names = new IdentityHashMap<>();
                int number = 0;
                for (Terms.Variable variable : occurrences)
                    if (!names.containsKey(variable)) {
                        if (counts.get(variable) == 1)
                            names.put(variable, "_");
                        else {
                            names.put(variable,
                                      String.valueOf((char)('A' + number % 26)) +
                                          (number < 26 ? "" : Integer.toString(number / 26)));
                            number++;
                        }
                    }
                Writer writer = new Writer(names);
                String head = writer.write(clause.head());
                if (clause.body() == null) {
                    result.add(head + ".");
                    continue;
                }
                result.add(head + " :-");
                List<Terms.Term> goals = new ArrayList<>();
                Terms.Term body = clause.body();
                while (is(body, ",", 2)) {
                    goals.add(Terms.args(body).get(0));
                    body = Terms.args(body).get(1);
                }
                goals.add(body);
                for (int i = 0; i < goals.size(); i++)
                    result.add("    " + writer.write(goals.get(i), 999, false) +
                               (i + 1 == goals.size() ? "." : ","));
            }
        }
        return result;
    }
    record QueryVariable(String name, Terms.Variable variable) {}
    static String answer(List<QueryVariable> variables) {
        Map<Terms.Variable, String> names = new IdentityHashMap<>();
        for (QueryVariable variable : variables)
            if (Terms.dereference(variable.variable()) instanceof Terms.Variable value)
                names.putIfAbsent(value, variable.name());
        Writer writer = new Writer(names);
        Map<Terms.Variable, String> previous = new IdentityHashMap<>();
        List<String> items = new ArrayList<>();
        for (QueryVariable variable : variables) {
            Terms.Term value = Terms.dereference(variable.variable());
            if (value instanceof Terms.Variable unbound) {
                if (previous.containsKey(unbound))
                    items.add(previous.get(unbound) + " = " + variable.name());
                previous.put(unbound, variable.name());
            } else
                items.add(variable.name() + " = " + writer.write(value, 699, true));
        }
        return items.isEmpty() ? "true" : String.join(", ", items);
    }
    sealed interface Marker permits IteMarker, NafMarker, ExitMarker, CollectMarker {}
    record IteMarker(int height) implements Marker {}
    record NafMarker(int height) implements Marker {}
    record ExitMarker(CatchChoice choice) implements Marker {}
    record CollectMarker(FindallChoice choice) implements Marker {}
    record GoalEntry(Terms.Term term, Marker marker, int barrier, CatchChoice context) {}
    record GoalList(GoalEntry head, GoalList tail) {}
    static GoalEntry entry(Terms.Term term, int barrier, CatchChoice context) {
        return new GoalEntry(term, null, barrier, context);
    }
    static GoalEntry entry(Marker marker, int barrier, CatchChoice context) {
        return new GoalEntry(null, marker, barrier, context);
    }
    static GoalList prepend(GoalList continuation, GoalEntry... entries) {
        for (int i = entries.length - 1; i >= 0; i--)
            continuation = new GoalList(entries[i], continuation);
        return continuation;
    }
    abstract static sealed class Choice permits AltChoice, ClausesChoice, BetweenChoice,
        LengthChoice, CatchChoice, FindallChoice {
        final int mark;
        final GoalList resume;
        Choice(int mark, GoalList resume) {
            this.mark = mark;
            this.resume = resume;
        }
    }
    static final class AltChoice extends Choice {
        AltChoice(int mark, GoalList resume) { super(mark, resume); }
    }
    static final class ClausesChoice extends Choice {
        final Terms.Term goal;
        final List<Database.Clause> candidates;
        final int barrier;
        final CatchChoice context;
        int next = 1;
        ClausesChoice(int mark, GoalList resume, Terms.Term goal, List<Database.Clause> candidates,
                      int barrier, CatchChoice context) {
            super(mark, resume);
            this.goal = goal;
            this.candidates = candidates;
            this.barrier = barrier;
            this.context = context;
        }
    }
    static final class BetweenChoice extends Choice {
        final int upper;
        final Terms.Term target;
        int next;
        BetweenChoice(int mark, GoalList resume, int upper, Terms.Term target, int next) {
            super(mark, resume);
            this.upper = upper;
            this.target = target;
            this.next = next;
        }
    }
    static final class LengthChoice extends Choice {
        final Terms.Term tail, number;
        final int count;
        int next;
        LengthChoice(int mark, GoalList resume, Terms.Term tail, Terms.Term number, int count) {
            super(mark, resume);
            this.tail = tail;
            this.number = number;
            this.count = count;
            next = count + 1;
        }
    }
    static final class CatchChoice extends Choice {
        final Terms.Term catcher, recovery;
        final CatchChoice parent;
        CatchChoice(int mark, GoalList resume, Terms.Term catcher, Terms.Term recovery,
                    CatchChoice parent) {
            super(mark, resume);
            this.catcher = catcher;
            this.recovery = recovery;
            this.parent = parent;
        }
    }
    static final class FindallChoice extends Choice {
        final Terms.Term template, result;
        final List<Terms.Term> results = new ArrayList<>();
        FindallChoice(int mark, GoalList resume, Terms.Term template, Terms.Term result) {
            super(mark, resume);
            this.template = template;
            this.result = result;
        }
    }
    static final class InferenceLimit extends RuntimeException {}
    static final class Engine {
        final Database database;
        final List<QueryVariable> queryVariables;
        final int limit;
        final Map<Terms.Indicator, Integer> calls, tries;
        final Unify.Trail trail = new Unify.Trail();
        GoalList goals;
        final List<Choice> choices = new ArrayList<>();
        CatchChoice context;
        Terms.Indicator currentKey;
        int solutions, inferences, choicepoints, backtracks;
        final List<String> answers = new ArrayList<>();
        final StringBuilder output = new StringBuilder();
        Engine(Database database, Terms.Term query, List<QueryVariable> queryVariables, int limit,
               Map<Terms.Indicator, Integer> calls, Map<Terms.Indicator, Integer> tries) {
            this.database = database;
            this.queryVariables = queryVariables;
            this.limit = limit;
            this.calls = calls;
            this.tries = tries;
            goals = prepend(null, entry(Terms.compound("call", query), 0, null));
        }
        <T extends Choice> T push(T choice) {
            choices.add(choice);
            choicepoints++;
            return choice;
        }
        void cut(int height) {
            while (choices.size() > height)
                choices.removeLast();
        }
        void infer(Terms.Indicator key) {
            if (inferences == 20000)
                throw new InferenceLimit();
            inferences++;
            calls.merge(key, 1, Integer::sum);
        }
        void writeOutput(Terms.Term term, boolean quoted) {
            output.append(term == null ? "\n" : new Writer(quoted).write(term));
        }
        boolean tryClause(Database.Clause clause, Terms.Term goal, int barrier, CatchChoice context,
                          GoalList continuation) {
            tries.merge(Terms.indicator(goal), 1, Integer::sum);
            Database.Copied copied = clause.copy();
            if (!trail.unify(copied.head(), goal))
                return false;
            goals = copied.body() == null
                        ? continuation
                        : prepend(continuation, entry(copied.body(), barrier, context));
            return true;
        }
        boolean userCall(Terms.Term goal, CatchChoice context) {
            Terms.Indicator key = Terms.indicator(goal);
            if (!database.predicates.containsKey(key))
                throw new Terms.Fault(Terms.compound("existence_error", Terms.atom("procedure"),
                                                     Terms.indicatorTerm(key)));
            List<Database.Clause> candidates = database.candidates(goal);
            if (candidates.isEmpty())
                return false;
            int height = choices.size();
            if (candidates.size() > 1)
                push(new ClausesChoice(trail.mark(), goals, goal, candidates, height, context));
            return tryClause(candidates.getFirst(), goal, height, context, goals);
        }
        boolean control(Terms.Term goal, int barrier, CatchChoice context) {
            Terms.Indicator key = Terms.indicator(goal);
            List<Terms.Term> args = Terms.args(goal);
            GoalList continuation = goals;
            int height = choices.size();
            switch (key.name()) {
            case "," ->
                goals = prepend(continuation, entry(args.get(0), barrier, context),
                                entry(args.get(1), barrier, context));
            case "!" -> cut(barrier);
            case ";" -> {
                push(new AltChoice(trail.mark(),
                                   prepend(continuation, entry(args.get(1), barrier, context))));
                Terms.Term left = Terms.dereference(args.get(0));
                if (is(left, "->", 2))
                    goals =
                        prepend(continuation, entry(Terms.args(left).get(0), height + 1, context),
                                entry(new IteMarker(height), barrier, context),
                                entry(Terms.args(left).get(1), barrier, context));
                else
                    goals = prepend(continuation, entry(left, barrier, context));
            }
            case "->" ->
                goals = prepend(continuation, entry(args.get(0), height, context),
                                entry(new IteMarker(height), barrier, context),
                                entry(args.get(1), barrier, context));
            case "\\+" -> {
                push(new AltChoice(trail.mark(), continuation));
                goals = prepend(continuation,
                                entry(Terms.compound("call", args.get(0)), barrier, context),
                                entry(new NafMarker(height), barrier, context));
            }
            case "call" -> {
                Terms.Term target = Terms.dereference(args.get(0));
                if (target instanceof Terms.Variable)
                    throw new Terms.Fault(Terms.INSTANTIATION);
                if (target instanceof Terms.IntegerTerm)
                    throw new Terms.Fault(Terms.typeError("callable", target));
                if (args.size() > 1) {
                    List<Terms.Term> arguments = new ArrayList<>(Terms.args(target));
                    arguments.addAll(args.subList(1, args.size()));
                    String name = target instanceof Terms.Atom atom
                                      ? atom.name()
                                      : ((Terms.Compound)target).name();
                    target = new Terms.Compound(name, arguments);
                }
                Terms.Term converted = convert(target);
                if (converted == null)
                    throw new Terms.Fault(Terms.typeError("callable", target));
                goals = prepend(continuation, entry(converted, height, context));
            }
            case "catch" -> {
                CatchChoice frame = push(
                    new CatchChoice(trail.mark(), continuation, args.get(1), args.get(2), context));
                goals = prepend(continuation,
                                entry(Terms.compound("call", args.get(0)), barrier, frame),
                                entry(new ExitMarker(frame), barrier, context));
            }
            default -> throw new AssertionError();
            }
            return true;
        }
        boolean marker(Marker marker) {
            return switch (marker) {
                case IteMarker ite -> {
                    cut(ite.height());
                    yield true;
                }
                case NafMarker naf -> {
                    cut(naf.height());
                    yield false;
                }
                case ExitMarker exit -> {
                    if (!choices.isEmpty() && choices.getLast() == exit.choice())
                        choices.removeLast();
                    yield true;
                }
                case CollectMarker collect -> {
                    collect.choice().results.add(Terms.copy(collect.choice().template));
                    yield false;
                }
            };
        }
        boolean between(List<Terms.Term> args) {
            int lower = Predicates.requireInteger(args.get(0)),
                upper = Predicates.requireInteger(args.get(1));
            Terms.Term value = Terms.dereference(args.get(2));
            if (!(value instanceof Terms.Variable) && !(value instanceof Terms.IntegerTerm))
                throw new Terms.Fault(Terms.typeError("integer", value));
            if (value instanceof Terms.IntegerTerm integer)
                return lower <= integer.value() && integer.value() <= upper;
            if (lower > upper)
                return false;
            if (lower < upper)
                push(new BetweenChoice(trail.mark(), goals, upper, value, lower + 1));
            return trail.unify(value, Terms.integer(lower));
        }
        static Terms.Term freshList(int count) {
            List<Terms.Term> variables = new ArrayList<>();
            for (int i = 0; i < count; i++)
                variables.add(new Terms.Variable());
            return Terms.list(variables);
        }
        boolean length(List<Terms.Term> args) {
            Terms.Term sequence = args.get(0), number = Terms.dereference(args.get(1));
            if (!(number instanceof Terms.Variable) && !(number instanceof Terms.IntegerTerm))
                throw new Terms.Fault(Terms.typeError("integer", number));
            if (number instanceof Terms.IntegerTerm integer && integer.value() < 0)
                throw new Terms.Fault(Terms.domainError("not_less_than_zero", number));
            Terms.ListParts parts = Terms.listParts(sequence);
            int count = parts.elements().size();
            Terms.Term tail = parts.tail();
            if (Terms.atomIs(tail, "[]"))
                return trail.unify(number, Terms.integer(count));
            if (!(tail instanceof Terms.Variable))
                throw new Terms.Fault(Terms.typeError("list", sequence));
            if (number instanceof Terms.IntegerTerm integer)
                return integer.value() >= count &&
                    trail.unify(tail, freshList(integer.value() - count));
            push(new LengthChoice(trail.mark(), goals, tail, number, count));
            return trail.unify(tail, Terms.NIL) && trail.unify(number, Terms.integer(count));
        }
        boolean step() {
            GoalEntry entry = goals.head();
            goals = goals.tail();
            context = entry.context();
            if (entry.marker() != null)
                return marker(entry.marker());
            Terms.Term goal = Terms.dereference(entry.term());
            Terms.Indicator key = currentKey = Terms.indicator(goal);
            if (CONTROLS.contains(key))
                return control(goal, entry.barrier(), entry.context());
            infer(key);
            List<Terms.Term> args = Terms.args(goal);
            if (key.equals(new Terms.Indicator("findall", 3))) {
                FindallChoice frame =
                    push(new FindallChoice(trail.mark(), goals, args.get(0), args.get(2)));
                goals = prepend(
                    null,
                    entry(Terms.compound("call", args.get(1)), entry.barrier(), entry.context()),
                    entry(new CollectMarker(frame), entry.barrier(), entry.context()));
                return true;
            }
            if (key.equals(new Terms.Indicator("throw", 1))) {
                Terms.Term ball = Terms.dereference(args.getFirst());
                if (ball instanceof Terms.Variable)
                    throw new Terms.Fault(Terms.INSTANTIATION);
                throw new Terms.Ball(ball);
            }
            if (key.equals(new Terms.Indicator("between", 3)))
                return between(args);
            if (key.equals(new Terms.Indicator("length", 2)))
                return length(args);
            if (Predicates.DETERMINISTIC.contains(key))
                return Predicates.execute(goal, trail, this::writeOutput);
            return userCall(goal, entry.context());
        }
        boolean backtrack() {
            while (true) {
                backtracks++;
                Choice choice = null;
                while (!choices.isEmpty()) {
                    choice = choices.getLast();
                    trail.undo(choice.mark);
                    if (choice instanceof CatchChoice) {
                        choices.removeLast();
                        continue;
                    }
                    break;
                }
                if (choices.isEmpty())
                    return false;
                switch (choice) {
                case AltChoice alt -> {
                    choices.removeLast();
                    goals = alt.resume;
                    return true;
                }
                case ClausesChoice clauses -> {
                    Database.Clause clause = clauses.candidates.get(clauses.next);
                    if (clauses.next + 1 == clauses.candidates.size())
                        choices.removeLast();
                    else
                        clauses.next++;
                    if (tryClause(clause, clauses.goal, clauses.barrier, clauses.context,
                                  clauses.resume))
                        return true;
                }
                case BetweenChoice between -> {
                    infer(new Terms.Indicator("between", 3));
                    int value = between.next;
                    if (value == between.upper)
                        choices.removeLast();
                    else
                        between.next++;
                    if (trail.unify(between.target, Terms.integer(value))) {
                        goals = between.resume;
                        return true;
                    }
                }
                case LengthChoice length -> {
                    infer(new Terms.Indicator("length", 2));
                    int count = length.next++;
                    if (trail.unify(length.tail, freshList(count - length.count)) &&
                        trail.unify(length.number, Terms.integer(count))) {
                        goals = length.resume;
                        return true;
                    }
                }
                case FindallChoice findall -> {
                    choices.removeLast();
                    if (trail.unify(Terms.list(findall.results), findall.result)) {
                        goals = findall.resume;
                        return true;
                    }
                }
                default -> throw new AssertionError();
                }
            }
        }
        boolean handleException(Terms.Term ball) {
            ball = Terms.copy(ball);
            CatchChoice frame = context;
            while (frame != null) {
                int index = choices.indexOf(frame);
                choices.subList(index, choices.size()).clear();
                trail.undo(frame.mark);
                int mark = trail.mark();
                if (trail.unify(Terms.copy(ball), frame.catcher)) {
                    goals = prepend(frame.resume, entry(Terms.compound("call", frame.recovery),
                                                        choices.size(), frame.parent));
                    return true;
                }
                trail.undo(mark);
                frame = frame.parent;
            }
            answers.add("uncaught exception: " + new Writer().write(ball));
            return false;
        }
        int[] run() {
            while (true) {
                try {
                    boolean success;
                    if (goals == null) {
                        solutions++;
                        String text = answer(queryVariables);
                        if (solutions == limit || choices.isEmpty()) {
                            answers.add(text + ".");
                            break;
                        }
                        answers.add(text + " ;");
                        success = backtrack();
                    } else {
                        success = step();
                        if (!success)
                            success = backtrack();
                    }
                    if (!success) {
                        answers.add("false.");
                        break;
                    }
                } catch (Terms.Fault fault) {
                    if (!handleException(
                            Terms.compound("error", fault.term, Terms.indicatorTerm(currentKey))))
                        break;
                } catch (Terms.Ball ball) {
                    if (!handleException(ball.term))
                        break;
                } catch (InferenceLimit limit) {
                    answers.add("inference limit exceeded");
                    break;
                }
            }
            return new int[] {solutions, inferences, choicepoints, backtracks};
        }
    }
    static String statistics(String prefix, int[] values) {
        return prefix + " solutions=" + values[0] + " inferences=" + values[1] +
            " choicepoints=" + values[2] + " backtracks=" + values[3];
    }
    static String read(String file) throws IOException {
        return Files.readString(Path.of("input", file), StandardCharsets.US_ASCII);
    }
    static void write(String file, List<String> lines) throws IOException {
        Files.writeString(Path.of("output", file),
                          String.join("\n", lines) + (lines.isEmpty() ? "" : "\n"),
                          StandardCharsets.US_ASCII);
    }
    public static void main(String[] args) throws IOException {
        Consultant consultant = new Consultant();
        for (String file : List.of("prelude.pl", "program.pl"))
            consultant.consult(file, read(file));
        consultant.finish();
        List<String> answers = new ArrayList<>(), stats = new ArrayList<>();
        StringBuilder writes = new StringBuilder();
        Map<Terms.Indicator, Integer> calls = new HashMap<>(), tries = new HashMap<>();
        int[] totals = new int[4];
        List<String> queries = read("queries.txt").lines().toList();
        for (int index = 0; index < queries.size(); index++) {
            int number = index + 1;
            String source = queries.get(index);
            answers.add(source);
            writes.append("== query ").append(number).append(" ==\n");
            int marker = source.indexOf("?- "),
                limit = marker == 0 ? 0 : Integer.parseInt(source.substring(0, marker).trim()),
                bodyStart = marker + 3;
            Reader reader = new Reader(source.substring(bodyStart), bodyStart + 1);
            Terms.Term query;
            try {
                query = reader.clause(true);
            } catch (Reader.SyntaxIssue issue) {
                answers.add("syntax error at column " + issue.token.column() + ": " +
                            issue.getMessage());
                stats.add("query " + number + ": syntax error");
                continue;
            }
            List<QueryVariable> variables = new ArrayList<>();
            for (var entry : reader.names.entrySet())
                if (!entry.getKey().startsWith("_"))
                    variables.add(new QueryVariable(entry.getKey(), entry.getValue()));
            Engine engine = new Engine(consultant.database, query, variables, limit, calls, tries);
            int[] counts = engine.run();
            for (int i = 0; i < 4; i++)
                totals[i] += counts[i];
            answers.addAll(engine.answers);
            writes.append(engine.output);
            if (!engine.output.isEmpty() &&
                engine.output.charAt(engine.output.length() - 1) != '\n')
                writes.append('\n');
            stats.add(statistics("query " + number + ":", counts));
        }
        stats.add(statistics("total:", totals));
        stats.add("== profile ==");
        List<Terms.Indicator> profile = new ArrayList<>(calls.keySet());
        profile.sort(Comparator.comparingInt((Terms.Indicator key) -> calls.get(key))
                         .reversed()
                         .thenComparing(Main::predicateName));
        for (Terms.Indicator key : profile)
            stats.add(predicateName(key) + " calls=" + calls.get(key) +
                      (consultant.database.predicates.containsKey(key)
                           ? " tries=" + tries.getOrDefault(key, 0)
                           : ""));
        Files.createDirectories(Path.of("output"));
        write("consult.txt", consultant.reports);
        write("listing.txt", listing(consultant.database));
        write("answers.txt", answers);
        write("stats.txt", stats);
        Files.writeString(Path.of("output/write_output.txt"), writes, StandardCharsets.US_ASCII);
    }
}
