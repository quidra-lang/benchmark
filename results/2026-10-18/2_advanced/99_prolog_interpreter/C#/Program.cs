global using System;
global using System.IO;
global using System.Linq;
global using System.Collections.Generic;
global using System.Text;
using System.Globalization;
sealed class Writer(Store store, bool quoted) {
    public Dictionary<int, string> Names = new();
    int generated;
    string Atom(string name) {
        bool plain = name.Length > 0 && ReaderLex.Lower(name[0]) && name.All(c => ReaderLex.Alpha(c) || ReaderLex.Digit(c) || c == '_') || name.Length > 0 && name != "." && name.All(ReaderLex.Symbol) || name is "[]" or "!" or ";";
        if (!quoted || plain) return name;
        StringBuilder result = new();
        result.Append((char)39);
        foreach (char c in name) {
            if (c is (char)92 or (char)39) result.Append((char)92).Append(c);
            else if (c == 10) result.Append((char)92).Append('n');
            else if (c == 9) result.Append((char)92).Append('t');
            else result.Append(c);
        } return result.Append((char)39).ToString();
    }
    public string Write(Term source, int limit = 1200, bool operand = false) {
        Term value = store.Dereference(source);
        switch (value) {
            case IntegerTerm integer: return integer.Value.ToString();
            case VariableTerm variable: if (!Names.ContainsKey(variable.Id)) Names[variable.Id] = "_G" + ++generated;
            return Names[variable.Id];
            case AtomTerm atom: {
                string text = Atom(atom.Name);
                return operand && ReaderLex.IsOperator(atom.Name) ? "(" + text + ")" : text;
            }
            case CompoundTerm compound: {
                string name = compound.Name;
                List<Term> args = compound.Args;
                if (name == "." && args.Count == 2) {
                    var (elements, tail) = store.Parts(compound);
                    return "[" + string.Join(",", elements.Select(element => Write(element, 999))) + (tail.Nil ? "" : "|" + Write(tail, 999)) + "]";
                }
                Operator? infix = args.Count == 2 ? ReaderLex.Infix(name) : null;
                int? prefix = args.Count == 1 ? ReaderLex.Prefix(name) : null;
                if (infix.HasValue) {
                    string a = Write(args[0], infix.Value.Left, true), b = Write(args[1], infix.Value.Right, true);
                    string text = name == "," ? a + "," + b : ReaderLex.Alpha(name[0]) ? a + " " + name + " " + b : a + (a.Length > 0 && ReaderLex.Symbol(a[^1]) ? " " : "") + name + (b.Length > 0 && ReaderLex.Symbol(b[0]) ? " " : "") + b;
                    return infix.Value.Priority > limit ? "(" + text + ")" : text;
                }
                if (prefix.HasValue) {
                    string argument = Write(args[0], prefix.Value, true);
                    bool space = argument.Length > 0 && (ReaderLex.Symbol(argument[0]) || ReaderLex.Digit(argument[0]) || argument[0] == '(');
                    string text = name + (space ? " " : "") + argument;
                    return prefix.Value > limit ? "(" + text + ")" : text;
                }
                return Atom(name) + "(" + string.Join(",", args.Select(argument => Write(argument, 999))) + ")";
            }
            default: throw new InvalidOperationException();
        }
    }
    public static string WriteTerm(Term term, Store store, bool quoted = true) => new Writer(store, quoted).Write(term);
    public static string IndicatorText(Indicator key) => WriteTerm(Terms.IndicatorTerm(key), new());
}
static class GoalConversion {
    public static Term? Convert(Term term, Store store) {
        Term value = store.Dereference(term);
        if (value is VariableTerm) return new CompoundTerm("call", new() {
            value
        });
        if (value is IntegerTerm) return null;
        if (value is CompoundTerm compound && compound.Name is "," or ";" or "->" && compound.Args.Count == 2) {
            Term? left = Convert(compound.Args[0], store);
            if (left == null) return null;
            Term? right = Convert(compound.Args[1], store);
            return right == null ? null : new CompoundTerm(compound.Name, new() {
                left, right
            });
        } return value;
    }
}
sealed class Consult {
    public Database Database = new();
    public Store Store = new();
    public List<string> Reports = new();
    readonly int[][] counts = {
        new int[3], new int[3]
    };
    void Warning(int file, int line, string message) {
        counts[file][2]++;
        Reports.Add($"{(file == 0 ? "prelude.pl" : "program.pl")}:{line}: warning: {message}");
    }
    public void Read(int file, string text) {
        string name = file == 0 ? "prelude.pl" : "program.pl";
        List<Token> tokens = ReaderLex.Lex(text, 1);
        string[] source = text.Split((char)10);
        int start = 0;
        int? last = null;
        HashSet<int> discontiguous = new();
        while (tokens[start].Kind != "eof") {
            int line = tokens[start].Line;
            Parsed parsed;
            try {
                parsed = new Reader(tokens, start, Store).Clause();
            }
            catch (ReadError error) {
                counts[file][1]++;
                Reports.Add($"{name}:{error.Line}:{error.Column}: syntax error: {error.Message}");
                if (!error.Eof) {
                    Reports.Add("    " + source[error.Line - 1]);
                    Reports.Add(new string(' ', error.Column + 3) + "^");
                } start = error.Index;
                while (tokens[start].Kind is not ("eof" or "end")) start++;
                if (tokens[start].Kind == "end") start++;
                continue;
            }
            start = parsed.Next;
            bool rule = parsed.Term is CompoundTerm compound && compound.Name == ":-" && compound.Args.Count == 2;
            Term head = rule ? parsed.Term.Arguments[0] : parsed.Term;
            Term? body = rule ? parsed.Term.Arguments[1] : null;
            Term? clauseError = head is VariableTerm ? new AtomTerm("instantiation_error") : head is IntegerTerm ? Terms.TypeError("callable", head) : null;
            Indicator? key = head.Indicator;
            if (clauseError == null && key.HasValue && (Predicates.Control(key.Value) || Predicates.Builtin(key.Value))) clauseError = new CompoundTerm("permission_error", new() {
                new AtomTerm("modify"), new AtomTerm("static_procedure"), Terms.IndicatorTerm(key.Value)
            });
            Term? converted = body == null ? null : GoalConversion.Convert(body, Store);
            if (clauseError == null && body != null && converted == null) clauseError = Terms.TypeError("callable", body);
            if (clauseError != null) {
                counts[file][1]++;
                Reports.Add($"{name}:{line}: error: {Writer.WriteTerm(clauseError, Store)}");
                continue;
            }
            Indicator indicator = key!.Value;
            int index;
            int? found = Database.Find(indicator);
            if (found.HasValue) index = found.Value;
            else {
                index = Database.Predicates.Count;
                Database.Predicates.Add(new(indicator));
            } Predicate predicate = Database.Predicates[index];
            if (file == 1 && predicate.Clauses.Any(clause => clause.File == "prelude.pl")) {
                Warning(file, line, "redefining prelude procedure " + Writer.IndicatorText(indicator));
                predicate.Clauses.Clear();
            }
            if (predicate.Clauses.Any(clause => clause.File == name) && last != index && discontiguous.Add(index)) Warning(file, line, "clauses of " + Writer.IndicatorText(indicator) + " are not together");
            predicate.Clauses.Add(new(head, converted, name, line));
            last = index;
            counts[file][0]++;
            List<string> singletons = parsed.Variables.Where(variable => !variable.Name.StartsWith('_') && variable.Count == 1).Select(variable => variable.Name).ToList();
            if (singletons.Count > 0) Warning(file, line, "singleton variables: " + string.Join(", ", singletons));
            List<string> repeated = parsed.Variables.Where(variable => variable.Name.StartsWith('_') && variable.Name.Length > 1 && variable.Count >= 2).Select(variable => variable.Name).ToList();
            if (repeated.Count > 0) Warning(file, line, "variables starting with _ occur more than once: " + string.Join(", ", repeated));
        }
    }
    public void Undefined() {
        static void Visit(Term term, List<Indicator> result) {
            Indicator? indicator = term.Indicator;
            if (!indicator.HasValue) return;
            Indicator key = indicator.Value;
            List<Term> args = term.Arguments;
            if (key.Name is "," or ";" or "->" && key.Arity == 2) {
                Visit(args[0], result);
                Visit(args[1], result);
            }
            else if (key.Name is "\\+" or "call" && key.Arity == 1) Visit(args[0], result);
            else if (key == new Indicator("findall", 3)) Visit(args[1], result);
            else if (key == new Indicator("catch", 3)) {
                Visit(args[0], result);
                Visit(args[2], result);
            }
            else if (!Predicates.Control(key) && !Predicates.Builtin(key)) result.Add(key);
        }
        List<(int File, int Line, string Message)> warnings = new();
        HashSet<Indicator> reported = new();
        foreach (Predicate predicate in Database.Predicates) foreach (Clause clause in predicate.Clauses) {
            if (clause.Body == null) continue;
            List<Indicator> indicators = new();
            Visit(clause.Body, indicators);
            foreach (Indicator key in indicators) {
                if (!Database.Find(key).HasValue && reported.Add(key)) warnings.Add((clause.File == "prelude.pl" ? 0 : 1, clause.Line, $"undefined procedure {Writer.IndicatorText(key)} called from {Writer.IndicatorText(predicate.Indicator)}"));
            }
        }
        foreach (var (file, line, message) in warnings) Warning(file, line, message);
        string[] names = {
            "prelude.pl", "program.pl"
        };
        for (int i = 0; i < 2; i++) Reports.Add($"{names[i]}: clauses={counts[i][0]} errors={counts[i][1]} warnings={counts[i][2]}");
        Reports.Add($"database: predicates={Database.Predicates.Count} clauses={Database.Predicates.Sum(predicate => predicate.Clauses.Count)}");
    }
    public List<string> Listing() {
        List<string> output = new();
        for (int p = 0; p < Database.Predicates.Count; p++) {
            if (p > 0) output.Add("");
            foreach (Clause clause in Database.Predicates[p].Clauses) {
                List<Term> terms = new() {
                    clause.Head
                };
                if (clause.Body != null) terms.Add(clause.Body);
                List<int> variables = Store.Variables(terms);
                Dictionary<int, int> occurrences = variables.GroupBy(id => id).ToDictionary(group => group.Key, group => group.Count());
                Writer writer = new(Store, true);
                int number = 0;
                foreach (int id in variables) {
                    if (writer.Names.ContainsKey(id)) continue;
                    if (occurrences[id] == 1) writer.Names[id] = "_";
                    else {
                        writer.Names[id] = ((char)(65 + number % 26)).ToString() + (number >= 26 ? (number / 26).ToString() : "");
                        number++;
                    }
                }
                string head = writer.Write(clause.Head);
                if (clause.Body == null) output.Add(head + ".");
                else {
                    output.Add(head + " :-");
                    List<Term> goals = new();
                    Term rest = clause.Body;
                    while (rest is CompoundTerm compound && compound.Name == "," && compound.Args.Count == 2) {
                        goals.Add(compound.Args[0]);
                        rest = compound.Args[1];
                    } goals.Add(rest);
                    for (int i = 0; i < goals.Count; i++) output.Add("    " + writer.Write(goals[i], 999) + (i + 1 == goals.Count ? "." : ","));
                }
            }
        }
        return output;
    }
}
sealed class Profile {
    public int Calls, Tries;
}
abstract record Goal;
sealed record TermGoal(Term Term) : Goal;
sealed record IteGoal(int Height) : Goal;
sealed record NafGoal(int Height) : Goal;
sealed record ExitGoal(Choice Point) : Goal;
sealed record CollectGoal(Choice Point) : Goal;
sealed record Entry(Goal Goal, int Barrier, Choice? Context);
sealed class Goals(Entry entry, Goals? next) {
    public Entry Entry = entry;
    public Goals? Next = next;
}
abstract class ChoiceKind {
}
sealed class AlternativeChoice : ChoiceKind {
}
sealed class ClausesChoice(int predicate, List<int> candidates, int next, Term goal, int barrier, Choice? context) : ChoiceKind {
    public int Predicate = predicate, Next = next, Barrier = barrier;
    public List<int> Candidates = candidates;
    public Term Goal = goal;
    public Choice? Context = context;
}
sealed class BetweenChoice(long high, Term variable, long next) : ChoiceKind {
    public long High = high, Next = next;
    public Term Variable = variable;
}
sealed class LengthChoice(Term tail, Term length, int prefix, int next) : ChoiceKind {
    public Term Tail = tail, Length = length;
    public int Prefix = prefix, Next = next;
}
sealed class CatchChoice(Term catcher, Term recovery, Choice? parent) : ChoiceKind {
    public Term Catcher = catcher, Recovery = recovery;
    public Choice? Parent = parent;
}
sealed class FindallChoice(Term template, Term result) : ChoiceKind {
    public Term Template = template, Result = result;
    public List<Term> Values = new();
}
sealed class Choice(int mark, Goals? resume, ChoiceKind kind) {
    public int Mark = mark;
    public Goals? Resume = resume;
    public ChoiceKind Kind = kind;
}
sealed class Engine {
    readonly Database database;
    readonly Dictionary<Indicator, Profile> profile;
    readonly Store store;
    readonly Trail trail = new();
    Goals? goals;
    readonly List<Choice> choices = new();
    public int Solutions, Inferences, Choicepoints, Backtracks;
    bool limitReached;
    public StringBuilder Output = new();
    public List<string> Answers = new();
    public Engine(Database database, Dictionary<Indicator, Profile> profile, Store store, Term query) {
        this.database = database;
        this.profile = profile;
        this.store = store;
        goals = new(TermEntry(new CompoundTerm("call", new() {
            query
        }), 0, null), null);
    }
    static Entry TermEntry(Term term, int barrier, Choice? context) => new(new TermGoal(term), barrier, context);
    Choice Push(ChoiceKind kind, Goals? resume) {
        Choicepoints++;
        Choice result = new(trail.Mark, resume, kind);
        choices.Add(result);
        return result;
    }
    void Prepend(params Entry[] entries) {
        for (int i = entries.Length - 1; i >= 0; i--) goals = new(entries[i], goals);
    }
    void Cut(int height) {
        if (choices.Count > height) choices.RemoveRange(height, choices.Count - height);
    }
    bool Inference(Indicator key) {
        if (Inferences == 20000) {
            limitReached = true;
            return false;
        } Inferences++;
        if (!profile.ContainsKey(key)) profile[key] = new();
        profile[key].Calls++;
        return true;
    }
    bool Unify(Term a, Term b) => trail.Unify(a, b, store);
    bool TryClause(int predicate, int clause, Term goal, int barrier, Choice? context, Goals? resume) {
        Indicator key = database.Predicates[predicate].Indicator;
        if (!profile.ContainsKey(key)) profile[key] = new();
        profile[key].Tries++;
        var (head, body) = database.Copy(predicate, clause, store);
        if (!Unify(head, goal)) return false;
        goals = resume;
        if (body != null) goals = new(TermEntry(body, barrier, context), goals);
        return true;
    }
    bool Execute(Entry current) {
        int barrier = current.Barrier;
        Choice? context = current.Context;
        Term term;
        switch (current.Goal) {
            case IteGoal goal: Cut(goal.Height);
            return true;
            case NafGoal goal: Cut(goal.Height);
            return false;
            case ExitGoal goal: if (choices.Count > 0 && ReferenceEquals(choices.Last(), goal.Point)) choices.RemoveAt(choices.Count - 1);
            return true;
            case CollectGoal goal: FindallChoice collector = (FindallChoice)goal.Point.Kind;
            collector.Values.Add(store.Copy(collector.Template));
            return false;
            case TermGoal goal: term = store.Dereference(goal.Term);
            break;
            default: throw new InvalidOperationException();
        }
        Indicator key = term.Indicator!.Value;
        List<Term> args = term.Arguments;
        if (Predicates.Control(key)) {
            switch (key.Name) {
                case ",": Prepend(TermEntry(args[0], barrier, context), TermEntry(args[1], barrier, context));
                break;
                case "!": Cut(barrier);
                break;
                case ";": {
                    int height = choices.Count;
                    Push(new AlternativeChoice(), new Goals(TermEntry(args[1], barrier, context), goals));
                    Term left = store.Dereference(args[0]);
                    if (left is CompoundTerm compound && compound.Name == "->" && compound.Args.Count == 2) Prepend(TermEntry(compound.Args[0], height + 1, context), new Entry(new IteGoal(height), barrier, context), TermEntry(compound.Args[1], barrier, context));
                    else Prepend(TermEntry(left, barrier, context));
                    break;
                }
                case "->": {
                    int height = choices.Count;
                    Prepend(TermEntry(args[0], height, context), new Entry(new IteGoal(height), barrier, context), TermEntry(args[1], barrier, context));
                    break;
                }
                case "\\+": {
                    int height = choices.Count;
                    Push(new AlternativeChoice(), goals);
                    Prepend(TermEntry(new CompoundTerm("call", new() {
                        args[0]
                    }), barrier, context), new Entry(new NafGoal(height), barrier, context));
                    break;
                }
                case "call": {
                    Term first = store.Dereference(args[0]);
                    if (first is VariableTerm) throw new PrologError(Terms.ErrorBall(new AtomTerm("instantiation_error"), key));
                    if (first is IntegerTerm) throw new PrologError(Terms.ErrorBall(Terms.TypeError("callable", first), key));
                    Term applied = args.Count == 1 ? first : first is AtomTerm atom ? new CompoundTerm(atom.Name, args.Skip(1).ToList()) : new CompoundTerm(((CompoundTerm)first).Name, ((CompoundTerm)first).Args.Concat(args.Skip(1)).ToList());
                    Term? converted = GoalConversion.Convert(applied, store);
                    if (converted == null) throw new PrologError(Terms.ErrorBall(Terms.TypeError("callable", applied), key));
                    Prepend(TermEntry(converted, choices.Count, context));
                    break;
                }
                case "catch": {
                    Choice point = Push(new CatchChoice(args[1], args[2], context), goals);
                    Prepend(TermEntry(new CompoundTerm("call", new() {
                        args[0]
                    }), barrier, point), new Entry(new ExitGoal(point), barrier, context));
                    break;
                }
            }
            return true;
        }
        if (!Inference(key)) return false;
        if (key == new Indicator("findall", 3)) {
            Choice point = Push(new FindallChoice(args[0], args[2]), goals);
            goals = null;
            Prepend(TermEntry(new CompoundTerm("call", new() {
                args[1]
            }), barrier, context), new Entry(new CollectGoal(point), barrier, context));
            return true;
        }
        if (key == new Indicator("throw", 1)) {
            Term ball = store.Dereference(args[0]);
            throw new PrologError(ball is VariableTerm ? Terms.ErrorBall(new AtomTerm("instantiation_error"), key) : ball);
        }
        if (key == new Indicator("between", 3)) {
            try {
                long low = Predicates.Integer(args[0], store), high = Predicates.Integer(args[1], store);
                Term variable = store.Dereference(args[2]);
                if (variable is IntegerTerm number) return low <= number.Value && number.Value <= high;
                if (variable is not VariableTerm) throw new PrologError(Terms.TypeError("integer", variable));
                if (low > high) return false;
                if (low < high) Push(new BetweenChoice(high, variable, low + 1), goals);
                return Unify(variable, new IntegerTerm(low));
            }
            catch (PrologError error) {
                throw new PrologError(Terms.ErrorBall(error.Term, key));
            }
        }
        if (key == new Indicator("length", 2)) {
            Term length = store.Dereference(args[1]);
            if (length is not VariableTerm) {
                if (length is not IntegerTerm number) throw new PrologError(Terms.ErrorBall(Terms.TypeError("integer", length), key));
                if (number.Value < 0) throw new PrologError(Terms.ErrorBall(Terms.DomainError("not_less_than_zero", length), key));
            }
            var (elements, tail) = store.Parts(args[0]);
            int prefix = elements.Count;
            if (tail.Nil) return Unify(args[1], new IntegerTerm(prefix));
            if (tail is not VariableTerm) throw new PrologError(Terms.ErrorBall(Terms.TypeError("list", args[0]), key));
            if (length is IntegerTerm n) {
                if (n.Value < prefix) return false;
                return Unify(tail, Terms.List(Enumerable.Range(0, (int)(n.Value - prefix)).Select(_ => store.Fresh())));
            }
            Push(new LengthChoice(tail, length, prefix, prefix + 1), goals);
            return Unify(tail, new AtomTerm("[]")) && Unify(length, new IntegerTerm(prefix));
        }
        if (Predicates.Builtin(key)) {
            try {
                return Predicates.Deterministic(key, args, store, trail, Output);
            } catch (PrologError error) {
                throw new PrologError(Terms.ErrorBall(error.Term, key));
            }
        }
        int? found = database.Find(key);
        if (!found.HasValue) throw new PrologError(Terms.ErrorBall(new CompoundTerm("existence_error", new() {
            new AtomTerm("procedure"), Terms.IndicatorTerm(key)
        }), key));
        int predicate = found.Value;
        List<int> candidates = database.Candidates(predicate, term, store);
        if (candidates.Count == 0) return false;
        int callBarrier = choices.Count;
        Goals? resume = goals;
        if (candidates.Count > 1) Push(new ClausesChoice(predicate, candidates, 1, term, callBarrier, context), resume);
        return TryClause(predicate, candidates[0], term, callBarrier, context, resume);
    }
    bool Backtrack() {
        while (true) {
            Backtracks++;
            while (choices.Count > 0 && choices.Last().Kind is CatchChoice) {
                Choice catcher = choices.Last();
                trail.Undo(catcher.Mark, store);
                choices.RemoveAt(choices.Count - 1);
            }
            if (choices.Count == 0) return false;
            Choice point = choices.Last();
            trail.Undo(point.Mark, store);
            switch (point.Kind) {
                case AlternativeChoice: choices.RemoveAt(choices.Count - 1);
                goals = point.Resume;
                return true;
                case ClausesChoice kind: {
                    int next = kind.Next;
                    if (next + 1 == kind.Candidates.Count) choices.RemoveAt(choices.Count - 1);
                    else kind.Next++;
                    if (TryClause(kind.Predicate, kind.Candidates[next], kind.Goal, kind.Barrier, kind.Context, point.Resume)) return true;
                    break;
                }
                case BetweenChoice kind: {
                    if (!Inference(new("between", 3))) return false;
                    long next = kind.Next;
                    if (next == kind.High) choices.RemoveAt(choices.Count - 1);
                    else kind.Next++;
                    if (Unify(kind.Variable, new IntegerTerm(next))) {
                        goals = point.Resume;
                        return true;
                    } break;
                }
                case LengthChoice kind: {
                    if (!Inference(new("length", 2))) return false;
                    int next = kind.Next++;
                    if (Unify(kind.Tail, Terms.List(Enumerable.Range(0, next - kind.Prefix).Select(_ => store.Fresh()))) && Unify(kind.Length, new IntegerTerm(next))) {
                        goals = point.Resume;
                        return true;
                    } break;
                }
                case FindallChoice kind: choices.RemoveAt(choices.Count - 1);
                if (Unify(Terms.List(kind.Values), kind.Result)) {
                    goals = point.Resume;
                    return true;
                } break;
            }
        }
    }
    bool Exception(Term original, Choice? initial) {
        Term ball = store.Copy(original);
        Choice? context = initial;
        while (context != null) {
            Choice point = context;
            int index = choices.FindIndex(candidate => ReferenceEquals(candidate, point));
            if (index < 0) throw new InvalidOperationException();
            CatchChoice kind = (CatchChoice)point.Kind;
            choices.RemoveRange(index, choices.Count - index);
            trail.Undo(point.Mark, store);
            int mark = trail.Mark;
            Term copied = store.Copy(ball);
            if (Unify(copied, kind.Catcher)) {
                goals = point.Resume;
                Prepend(TermEntry(new CompoundTerm("call", new() {
                    kind.Recovery
                }), choices.Count, kind.Parent));
                return true;
            } trail.Undo(mark, store);
            context = kind.Parent;
        }
        Answers.Add("uncaught exception: " + Writer.WriteTerm(ball, store));
        return false;
    }
    string Answer(List<Variable> source) {
        List<Variable> variables = source.Where(variable => !variable.Name.StartsWith('_')).ToList();
        List<Term> values = variables.Select(variable => store.Dereference(variable.Term)).ToList();
        Writer writer = new(store, true);
        for (int i = 0; i < variables.Count; i++) {
            if (values[i].VariableId is int id && !writer.Names.ContainsKey(id)) writer.Names[id] = variables[i].Name;
        }
        List<string> items = new();
        for (int i = 0; i < variables.Count; i++) {
            if (values[i].VariableId is int id) {
                int? previous = null;
                for (int j = i - 1; j >= 0; j--) {
                    if (values[j].VariableId == id) {
                        previous = j;
                        break;
                    }
                } if (previous.HasValue) items.Add(variables[previous.Value].Name + " = " + variables[i].Name);
            }
            else items.Add(variables[i].Name + " = " + writer.Write(values[i], 699, true));
        }
        return items.Count == 0 ? "true" : string.Join(", ", items);
    }
    public void Run(List<Variable> variables, int? limit) {
        while (true) {
            Goals? current = goals;
            if (current == null) {
                Solutions++;
                string text = Answer(variables);
                if (limit == Solutions || choices.Count == 0) {
                    Answers.Add(text + ".");
                    return;
                } Answers.Add(text + " ;");
                if (!Backtrack()) {
                    Answers.Add(limitReached ? "inference limit exceeded" : "false.");
                    return;
                } continue;
            }
            goals = current.Next;
            try {
                if (!Execute(current.Entry)) {
                    if (limitReached || !Backtrack()) {
                        Answers.Add(limitReached ? "inference limit exceeded" : "false.");
                        return;
                    }
                }
            } catch (PrologError error) {
                if (!Exception(error.Term, current.Entry.Context)) return;
            }
        }
    }
}
static class Program {
    static string LinesText(List<string> lines) => lines.Count == 0 ? "" : string.Join("\n", lines) + "\n";
    static void Write(string name, string text) {
        Directory.CreateDirectory("output");
        File.WriteAllText("output/" + name, text);
    }
    static void Main() {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Consult consult = new();
        consult.Read(0, File.ReadAllText("input/prelude.pl"));
        consult.Read(1, File.ReadAllText("input/program.pl"));
        consult.Undefined();
        List<string> answers = new(), statistics = new();
        StringBuilder output = new();
        int[] totals = new int[4];
        Dictionary<Indicator, Profile> profile = new();
        string[] queries = File.ReadAllLines("input/queries.txt");
        for (int i = 0; i < queries.Length; i++) {
            string line = queries[i];
            answers.Add(line);
            output.Append($"== query {i + 1} ==\n");
            int at = line.IndexOf("?- ", StringComparison.Ordinal);
            string prefix = line[..at].Trim();
            int? limit = prefix.Length == 0 ? null : int.Parse(prefix);
            int start = at + 3;
            List<Token> tokens = ReaderLex.Lex(line[start..], start + 1);
            Store store = consult.Store.Clone();
            try {
                Parsed parsed = new Reader(tokens, 0, store).Clause(true);
                Engine engine = new(consult.Database, profile, store, parsed.Term);
                engine.Run(parsed.Variables, limit);
                answers.AddRange(engine.Answers);
                output.Append(engine.Output);
                if (engine.Output.Length > 0 && engine.Output[^1] != 10) output.Append((char)10);
                statistics.Add($"query {i + 1}: solutions={engine.Solutions} inferences={engine.Inferences} choicepoints={engine.Choicepoints} backtracks={engine.Backtracks}");
                totals[0] += engine.Solutions;
                totals[1] += engine.Inferences;
                totals[2] += engine.Choicepoints;
                totals[3] += engine.Backtracks;
            }
            catch (ReadError error) {
                answers.Add($"syntax error at column {error.Column}: {error.Message}");
                statistics.Add($"query {i + 1}: syntax error");
            }
        }
        statistics.Add($"total: solutions={totals[0]} inferences={totals[1]} choicepoints={totals[2]} backtracks={totals[3]}");
        statistics.Add("== profile ==");
        foreach (var (key, counts) in profile.Where(pair => pair.Value.Calls > 0).OrderByDescending(pair => pair.Value.Calls).ThenBy(pair => Writer.IndicatorText(pair.Key), StringComparer.Ordinal)) statistics.Add($"{Writer.IndicatorText(key)} calls={counts.Calls}" + (consult.Database.Find(key).HasValue ? $" tries={counts.Tries}" : ""));
        Write("consult.txt", LinesText(consult.Reports));
        Write("listing.txt", LinesText(consult.Listing()));
        Write("answers.txt", LinesText(answers));
        Write("write_output.txt", output.ToString());
        Write("stats.txt", LinesText(statistics));
    }
}
