using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

class Program
{
    record Line(int Number, string Text);

    class EvaluationError : Exception { }

    class Node(string kind, string text, Node? left = null, Node? right = null)
    {
        public string? Reference(Chart chart)
        {
            if (kind == "variable") return text == "_data" || chart.Variables.ContainsKey(text) ? null : "unknown variable " + text;
            if (kind == "in") return chart.States.ContainsKey(text) ? null : "unknown state " + text;
            return left?.Reference(chart) ?? right?.Reference(chart);
        }

        public long Evaluate(Chart chart)
        {
            if (kind == "number") return long.Parse(text, CultureInfo.InvariantCulture);
            if (kind == "variable") return text == "_data" ? chart.Data : chart.Variables[text];
            if (kind == "in") return chart.States[text].Active ? 1 : 0;
            long a = left!.Evaluate(chart);
            if (kind == "unary") return text == "-" ? -a : a == 0 ? 1 : 0;
            if (text == "&&" && a == 0) return 0;
            if (text == "||" && a != 0) return 1;
            long b = right!.Evaluate(chart);
            if ((text == "/" || text == "%") && b == 0) throw new EvaluationError();
            return text switch
            {
                "+" => a + b,
                "-" => a - b,
                "*" => a * b,
                "/" => a / b,
                "%" => a % b,
                "==" => a == b ? 1 : 0,
                "!=" => a != b ? 1 : 0,
                "<" => a < b ? 1 : 0,
                "<=" => a <= b ? 1 : 0,
                ">" => a > b ? 1 : 0,
                ">=" => a >= b ? 1 : 0,
                "&&" or "||" => b != 0 ? 1 : 0,
                _ => throw new InvalidOperationException()
            };
        }
    }

    class ExpressionParser
    {
        static readonly string[][] Operators = [["||"], ["&&"], ["==", "!=", "<", "<=", ">", ">="], ["+", "-"], ["*", "/", "%"]];
        readonly List<string> tokens = [];
        int position;

        public ExpressionParser(string text)
        {
            for (int i = 0; i < text.Length;)
            {
                char c = text[i];
                if (c == ' ')
                {
                    i++;
                    continue;
                }
                int start = i;
                if (char.IsAsciiLetterOrDigit(c) || c == '_')
                {
                    while (i < text.Length && (char.IsAsciiLetterOrDigit(text[i]) || text[i] == '_')) i++;
                }
                else if (i + 1 < text.Length && new[] { "||", "&&", "==", "!=", "<=", ">=" }.Contains(text.Substring(i, 2))) i += 2;
                else i++;
                tokens.Add(text[start..i]);
            }
        }

        public Node Parse() => Level(0);

        Node Level(int precedence)
        {
            if (precedence == Operators.Length) return Unary();
            Node result = Level(precedence + 1);
            while (position < tokens.Count && Operators[precedence].Contains(tokens[position]))
            {
                string operation = tokens[position++];
                result = new Node("binary", operation, result, Level(precedence + 1));
            }
            return result;
        }

        Node Unary()
        {
            string token = tokens[position++];
            if (token is "!" or "-") return new Node("unary", token, Unary());
            if (token == "(")
            {
                Node result = Level(0);
                position++;
                return result;
            }
            if (token == "in")
            {
                position++;
                string state = tokens[position++];
                position++;
                return new Node("in", state);
            }
            return new Node(token[0] is >= '0' and <= '9' ? "number" : "variable", token);
        }
    }

    static Node Expression(string text) => new ExpressionParser(text).Parse();

    class Action
    {
        public string Kind = "", Name = "", Literal = "";
        public Node? Expression;
        public int Delay;

        public string? Reference(Chart chart)
        {
            if (Kind == "assign" && !chart.Variables.ContainsKey(Name)) return "unknown variable " + Name;
            return Expression?.Reference(chart);
        }
    }

    static List<Action> Actions(string text)
    {
        List<Action> result = [];
        foreach (string raw in text.Split("; ", StringSplitOptions.None))
        {
            Action action = new();
            string[] parts = raw.Split(' ', 2);
            string first = parts[0], rest = parts.Length == 2 ? parts[1] : "";
            switch (first)
            {
                case "raise":
                case "send":
                    action.Kind = first;
                    string[] arguments = rest.Split(' ', first == "raise" ? 2 : 3);
                    action.Name = arguments[0];
                    if (first == "send")
                    {
                        action.Delay = int.Parse(arguments[1]);
                        if (arguments.Length == 3) action.Expression = Expression(arguments[2]);
                    }
                    else if (arguments.Length == 2) action.Expression = Expression(arguments[1]);
                    break;
                case "cancel":
                    action.Kind = "cancel";
                    action.Name = rest;
                    break;
                case "log":
                    action.Kind = "log";
                    if (rest.StartsWith('"'))
                    {
                        int end = rest.IndexOf('"', 1);
                        action.Literal = rest[1..end];
                        if (end + 1 < rest.Length) action.Expression = Expression(rest[(end + 2)..]);
                    }
                    else action.Expression = Expression(rest);
                    break;
                default:
                    action.Kind = "assign";
                    action.Name = first;
                    action.Expression = Expression(rest[2..]);
                    break;
            }
            result.Add(action);
        }
        return result;
    }

    class State(string name, string kind, State? parent)
    {
        public string Name = name, Kind = kind;
        public string? InitialName, DefaultName;
        public bool Deep, Active;
        public State? Parent = parent;
        public List<State> Children = [];
        public List<List<Action>> Entries = [], Exits = [];
        public List<Transition> Transitions = [];
        public List<State>? History;
        public int Depth = parent == null ? 0 : parent.Depth + 1;
        public int Order;
        public long Entered, Taken, Dwell, EntryTime;
        public IEnumerable<State> ChildStates => Children.Where(s => s.Kind != "history");
        public bool Compound => Parent == null || Kind == "state" && ChildStates.Any();
        public bool Parallel => Kind == "parallel" && ChildStates.Any();
        public bool Atomic => Kind != "history" && !ChildStates.Any();

        public bool DescendantOf(State? ancestor)
        {
            for (State? p = Parent; p != null; p = p.Parent) if (p == ancestor) return true;
            return false;
        }
    }

    class Definition(Line line)
    {
        public Line Line = line;
        public string? Error;
        public State? State;
    }

    class Transition
    {
        public State Source = null!;
        public State? Target;
        public string? TargetName;
        public string Trigger = "", Mode = "internal";
        public string[] Descriptors = [];
        public Node? Guard;
        public int Delay;
        public List<Action> Actions = [];
    }

    record Event(string Name, long Value);

    class Reservation
    {
        public long Due, Number;
        public Transition? Timer;
        public Event? Event;
    }

    record Trigger(string Kind, Event? Event = null, Transition? Timer = null);

    record Choice(Transition Transition, State? Scope, HashSet<State> Exits);

    class Chart
    {
        readonly State root = new("", "state", null);
        public readonly Dictionary<string, State> States = new(StringComparer.Ordinal);
        public readonly SortedDictionary<string, long> Variables = new(StringComparer.Ordinal);
        readonly List<State> order = [];
        readonly List<Reservation> reservations = [];
        readonly Queue<Event> queue = new();
        public long Data;
        long time, creations, macrosteps, microsteps;
        int inMacro;
        bool trace, halted;

        State Initial(State state) => state.InitialName == null ? state.ChildStates.First() : States[state.InitialName];

        State DefaultTarget(State history) => history.DefaultName == null ? Initial(history.Parent!) : States[history.DefaultName];

        void Visit(State state)
        {
            state.Order = order.Count;
            order.Add(state);
            foreach (State child in state.Children) Visit(child);
        }

        string? FirstReference(List<Action> list)
        {
            foreach (Action action in list)
            {
                string? error = action.Reference(this);
                if (error != null) return error;
            }
            return null;
        }

        Transition ParseTransition(string text)
        {
            int end = text.IndexOf(' ', 3);
            Transition transition = new() { Source = States[text[3..end]] };
            string rest = text[(end + 1)..];
            if (rest.StartsWith("after ", StringComparison.Ordinal))
            {
                int space = rest.IndexOf(' ', 6);
                transition.Trigger = "timer";
                transition.Delay = int.Parse(space < 0 ? rest[6..] : rest[6..space]);
                rest = space < 0 ? "" : rest[(space + 1)..];
            }
            else
            {
                int space = rest.IndexOf(' ');
                string trigger = space < 0 ? rest : rest[..space];
                transition.Trigger = trigger == "always" ? "always" : "event";
                transition.Descriptors = trigger.Split('|');
                rest = space < 0 ? "" : rest[(space + 1)..];
            }
            if (rest.StartsWith('['))
            {
                int close = rest.IndexOf(']');
                transition.Guard = Expression(rest[1..close]);
                rest = rest[(close + 1)..].TrimStart(' ');
            }
            if (rest.StartsWith("-> ", StringComparison.Ordinal) || rest.StartsWith("~> ", StringComparison.Ordinal))
            {
                transition.Mode = rest[0] == '~' ? "local" : "external";
                rest = rest[3..];
                int space = rest.IndexOf(' ');
                transition.TargetName = space < 0 ? rest : rest[..space];
                rest = space < 0 ? "" : rest[(space + 1)..];
            }
            if (rest.StartsWith("/ ", StringComparison.Ordinal)) transition.Actions = Program.Actions(rest[2..]);
            return transition;
        }

        public bool Define(List<Line> lines)
        {
            List<Definition> definitions = [];
            foreach (Line line in lines)
            {
                Definition definition = new(line);
                definitions.Add(definition);
                string[] a = line.Text.Split(' ');
                string kind = a[0];
                if (kind is "state" or "parallel" or "final" or "history")
                {
                    string? parentName = a.Length > 2 && a[2] != "initial" ? a[2] : null;
                    if (States.ContainsKey(a[1])) definition.Error = "duplicate state " + a[1];
                    else if (parentName != null && !States.ContainsKey(parentName)) definition.Error = "unknown state " + parentName;
                    else if (parentName != null && (States[parentName].Kind is "final" or "history")) definition.Error = parentName + " cannot have children";
                    else
                    {
                        State parent = parentName == null ? root : States[parentName];
                        State state = new(a[1], kind, parent);
                        definition.State = state;
                        States.Add(a[1], state);
                        parent.Children.Add(state);
                        if (kind == "state") for (int i = 2; i < a.Length; i++) if (a[i] == "initial") state.InitialName = a[i + 1];
                        if (kind == "history")
                        {
                            state.Deep = a[3] == "deep";
                            if (a.Length == 5) state.DefaultName = a[4];
                        }
                    }
                }
                else if (kind == "var")
                {
                    if (Variables.ContainsKey(a[1])) definition.Error = "duplicate variable " + a[1];
                    else Variables.Add(a[1], long.Parse(a[2]));
                }
            }
            foreach (Definition definition in definitions)
            {
                if (definition.Error != null) continue;
                string text = definition.Line.Text;
                string[] a = text.Split(' ');
                string kind = a[0];
                State? state = definition.State;
                if (kind == "state" && state!.InitialName != null)
                {
                    if (!States.TryGetValue(state.InitialName, out State? child)) definition.Error = "unknown state " + state.InitialName;
                    else if (child.Parent != state || child.Kind == "history") definition.Error = child.Name + " is not a child of " + state.Name;
                }
                else if (kind is "final" or "history")
                {
                    if (state!.Parent!.Kind != "state" || !state.Parent.ChildStates.Any()) definition.Error = state.Name + " needs a compound parent";
                    else if (kind == "history" && state.DefaultName != null)
                    {
                        if (!States.TryGetValue(state.DefaultName, out State? target)) definition.Error = "unknown state " + state.DefaultName;
                        else if (!target.DescendantOf(state.Parent) || target.Kind == "history") definition.Error = target.Name + " is not a descendant of " + state.Parent.Name;
                    }
                }
                else if (kind is "entry" or "exit")
                {
                    if (!States.TryGetValue(a[1], out State? source)) definition.Error = "unknown state " + a[1];
                    else if (source.Kind == "history") definition.Error = source.Name + " cannot have actions";
                    else
                    {
                        List<Action> list = Program.Actions(text[(text.IndexOf(" / ", StringComparison.Ordinal) + 3)..]);
                        definition.Error = FirstReference(list);
                        if (definition.Error == null) (kind == "entry" ? source.Entries : source.Exits).Add(list);
                    }
                }
                else if (kind == "on")
                {
                    if (!States.TryGetValue(a[1], out State? source)) definition.Error = "unknown state " + a[1];
                    else if (source.Kind is "final" or "history") definition.Error = source.Name + " cannot have transitions";
                    else
                    {
                        Transition transition = ParseTransition(text);
                        string? error = transition.Guard?.Reference(this);
                        if (error == null && transition.TargetName != null && !States.ContainsKey(transition.TargetName)) error = "unknown state " + transition.TargetName;
                        error ??= FirstReference(transition.Actions);
                        definition.Error = error;
                        if (error == null)
                        {
                            transition.Target = transition.TargetName == null ? null : States[transition.TargetName];
                            source.Transitions.Add(transition);
                        }
                    }
                }
            }
            bool valid = true;
            foreach (Definition definition in definitions) if (definition.Error != null)
            {
                Console.WriteLine($"error line {definition.Line.Number}: {definition.Error}");
                valid = false;
            }
            if (!valid) return false;
            foreach (State child in root.Children) Visit(child);
            return true;
        }

        public void Warnings()
        {
            HashSet<State> reachable = [Initial(root)];
            bool changed;
            do
            {
                int before = reachable.Count;
                foreach (State state in reachable.ToArray())
                {
                    if (state.Parent != root) reachable.Add(state.Parent!);
                    if (state.Compound) reachable.Add(Initial(state));
                    if (state.Parallel) reachable.UnionWith(state.ChildStates);
                    foreach (Transition transition in state.Transitions) if (transition.Target != null) reachable.Add(transition.Target.Kind == "history" ? DefaultTarget(transition.Target) : transition.Target);
                }
                changed = reachable.Count != before;
            } while (changed);
            foreach (State state in order) if (state.Kind != "history" && !reachable.Contains(state)) Console.WriteLine("warning: unreachable state " + state.Name);
        }

        IEnumerable<State> Effective(Transition transition)
        {
            State target = transition.Target!;
            return target.Kind != "history" ? [target] : target.History ?? [DefaultTarget(target)];
        }

        Choice MakeChoice(Transition transition)
        {
            if (transition.Target == null) return new Choice(transition, null, []);
            State[] targets = Effective(transition).ToArray();
            State? scope = null;
            if (transition.Mode == "local" && transition.Source.Compound && targets.All(s => s.DescendantOf(transition.Source))) scope = transition.Source;
            else for (State? ancestor = transition.Source.Parent; ancestor != null; ancestor = ancestor.Parent) if (ancestor.Compound && targets.All(s => s.DescendantOf(ancestor)))
            {
                scope = ancestor;
                break;
            }
            return new Choice(transition, scope, order.Where(s => s.Active && s.DescendantOf(scope)).ToHashSet());
        }

        static bool Matches(Transition transition, Trigger trigger)
        {
            if (trigger.Kind == "always") return transition.Trigger == "always";
            if (trigger.Kind == "timer") return transition == trigger.Timer;
            if (transition.Trigger != "event") return false;
            string name = trigger.Event!.Name;
            return transition.Descriptors.Any(d => d == "*" || d == name || name.StartsWith(d + ".", StringComparison.Ordinal));
        }

        List<Choice> Select(Trigger trigger)
        {
            List<Transition> candidates = [];
            HashSet<Transition> seen = [];
            foreach (State atomic in order.Where(s => s.Active && s.Atomic))
            {
                Transition? selected = null;
                for (State? state = atomic; state != root && selected == null; state = state!.Parent)
                {
                    foreach (Transition transition in state!.Transitions) if (Matches(transition, trigger))
                    {
                        bool guard;
                        try
                        {
                            guard = transition.Guard == null || transition.Guard.Evaluate(this) != 0;
                        }
                        catch (EvaluationError)
                        {
                            queue.Enqueue(new Event("error.execution", 0));
                            guard = false;
                        }
                        if (guard)
                        {
                            selected = transition;
                            break;
                        }
                    }
                }
                if (selected != null && seen.Add(selected)) candidates.Add(selected);
            }
            List<Choice> result = [];
            HashSet<State> exited = [];
            foreach (Transition transition in candidates)
            {
                Choice candidate = MakeChoice(transition);
                if (!candidate.Exits.Overlaps(exited))
                {
                    result.Add(candidate);
                    exited.UnionWith(candidate.Exits);
                }
            }
            return result;
        }

        void Reserve(Transition? timer, Event? @event, long delay) => reservations.Add(new Reservation { Timer = timer, Event = @event, Due = time + delay, Number = ++creations });

        void Perform(List<Action> list)
        {
            foreach (Action action in list)
            {
                long value;
                try
                {
                    value = action.Expression?.Evaluate(this) ?? 0;
                }
                catch (EvaluationError)
                {
                    queue.Enqueue(new Event("error.execution", 0));
                    return;
                }
                switch (action.Kind)
                {
                    case "assign":
                        Variables[action.Name] = value;
                        break;
                    case "raise":
                        queue.Enqueue(new Event(action.Name, value));
                        break;
                    case "send":
                        Reserve(null, new Event(action.Name, value), action.Delay);
                        break;
                    case "cancel":
                        reservations.RemoveAll(r => r.Event != null && r.Event.Name == action.Name);
                        break;
                    case "log":
                        Console.WriteLine(action.Literal + (action.Expression == null ? "" : value.ToString(CultureInfo.InvariantCulture)));
                        break;
                }
            }
        }

        void Expand(HashSet<State> entry)
        {
            bool changed;
            do
            {
                int before = entry.Count;
                foreach (State state in order) if (entry.Contains(state))
                {
                    if (state.Parallel) entry.UnionWith(state.ChildStates);
                    if (state.Compound && !state.ChildStates.Any(entry.Contains)) entry.Add(Initial(state));
                }
                changed = entry.Count != before;
            } while (changed);
        }

        bool Complete(State state)
        {
            if (state.Compound) return state.ChildStates.Any(s => s.Kind == "final" && s.Active);
            return state.Parallel && state.ChildStates.All(Complete);
        }

        void Enter(HashSet<State> entry)
        {
            foreach (State state in order) if (entry.Contains(state))
            {
                state.Active = true;
                state.Entered++;
                state.EntryTime = time;
                foreach (Transition transition in state.Transitions) if (transition.Trigger == "timer") Reserve(transition, null, transition.Delay);
                foreach (List<Action> list in state.Entries) Perform(list);
                if (state.Kind == "final")
                {
                    State parent = state.Parent!;
                    queue.Enqueue(new Event("done.state." + parent.Name, 0));
                    State? grandparent = parent.Parent;
                    if (grandparent != null && grandparent.Parallel && grandparent.ChildStates.All(Complete)) queue.Enqueue(new Event("done.state." + grandparent.Name, 0));
                }
            }
        }

        static string Names(IEnumerable<State> states)
        {
            string text = string.Join(",", states.Select(s => s.Name));
            return text.Length == 0 ? "-" : text;
        }

        static string Display(Trigger trigger)
        {
            if (trigger.Kind == "always") return "always";
            if (trigger.Kind == "timer") return $"after({trigger.Timer!.Delay})@{trigger.Timer.Source.Name}";
            return trigger.Event!.Name + (trigger.Event.Value == 0 ? "" : "=" + trigger.Event.Value.ToString(CultureInfo.InvariantCulture));
        }

        bool Micro(List<Choice> selected, Trigger trigger)
        {
            if (inMacro == 1000)
            {
                Console.WriteLine($"LIVELOCK t={time}");
                halted = true;
                return false;
            }
            inMacro++;
            microsteps++;
            HashSet<State> exits = selected.SelectMany(c => c.Exits).ToHashSet();
            foreach (State history in order) if (history.Kind == "history" && exits.Contains(history.Parent!)) history.History = order.Where(s => s.Active && (history.Deep ? s.Atomic && s.DescendantOf(history.Parent) : s.Parent == history.Parent && s.Kind != "history")).ToList();
            HashSet<State> entry = [];
            foreach (Choice choice in selected) if (choice.Transition.Target != null) foreach (State target in Effective(choice.Transition)) for (State? state = target; state != choice.Scope; state = state!.Parent) entry.Add(state!);
            Expand(entry);
            List<State> exitOrder = order.Where(exits.Contains).Reverse().ToList();
            if (trace) Console.WriteLine($"[t={time}] {Display(trigger)} ({Names(selected.Select(c => c.Transition.Source))}): exit {Names(exitOrder)}; enter {Names(order.Where(entry.Contains))}");
            foreach (State state in exitOrder)
            {
                foreach (List<Action> list in state.Exits) Perform(list);
                state.Active = false;
                state.Dwell += time - state.EntryTime;
                reservations.RemoveAll(r => r.Timer != null && r.Timer.Source == state);
            }
            foreach (Choice choice in selected)
            {
                Perform(choice.Transition.Actions);
                choice.Transition.Source.Taken++;
            }
            Enter(entry);
            return true;
        }

        public void Macro(Trigger trigger)
        {
            macrosteps++;
            inMacro = 0;
            if (trigger.Kind == "start")
            {
                Data = 0;
                HashSet<State> entry = [Initial(root)];
                Expand(entry);
                Enter(entry);
            }
            else
            {
                Data = trigger.Kind == "timer" ? 0 : trigger.Event!.Value;
                List<Choice> selected = Select(trigger);
                if (selected.Count > 0 && !Micro(selected, trigger)) return;
            }
            while (!halted)
            {
                Data = 0;
                Trigger always = new("always");
                List<Choice> selected = Select(always);
                if (selected.Count > 0)
                {
                    if (!Micro(selected, always)) return;
                    continue;
                }
                if (queue.Count == 0) return;
                Event @event = queue.Dequeue();
                Data = @event.Value;
                Trigger internalTrigger = new("event", @event);
                selected = Select(internalTrigger);
                if (selected.Count > 0 && !Micro(selected, internalTrigger)) return;
            }
        }

        IEnumerable<Reservation> OrderedReservations() => reservations.OrderBy(r => r.Due).ThenBy(r => r.Number);

        public void Script(string text)
        {
            if (halted) return;
            string[] a = text.Split(' ', 3);
            switch (a[0])
            {
                case "event":
                    Macro(new Trigger("event", new Event(a[1], a.Length == 3 ? long.Parse(a[2]) : 0)));
                    break;
                case "tick":
                    long finish = time + long.Parse(a[1]);
                    while (!halted)
                    {
                        Reservation? next = OrderedReservations().FirstOrDefault(r => r.Due <= finish);
                        if (next == null) break;
                        reservations.Remove(next);
                        time = next.Due;
                        Macro(next.Timer == null ? new Trigger("event", next.Event) : new Trigger("timer", Timer: next.Timer));
                    }
                    if (!halted) time = finish;
                    break;
                case "set":
                    if (!Variables.ContainsKey(a[1])) Console.WriteLine("error: unknown variable " + a[1]);
                    else Variables[a[1]] = long.Parse(a[2]);
                    break;
                case "trace":
                    trace = a[1] == "on";
                    break;
                case "eval":
                    string raw = text[5..];
                    Node node = Expression(raw);
                    string? error = node.Reference(this);
                    if (error != null) Console.WriteLine("error: " + error);
                    else
                    {
                        Data = 0;
                        try
                        {
                            Console.WriteLine(raw + " -> " + node.Evaluate(this));
                        }
                        catch (EvaluationError)
                        {
                            Console.WriteLine("error: division by zero");
                        }
                    }
                    break;
                case "dump":
                    Console.WriteLine($"dump t={time}");
                    foreach (State state in order) if (state.Active) Console.WriteLine(new string(' ', 2 * state.Depth) + state.Name);
                    foreach (var variable in Variables) Console.WriteLine($"  var {variable.Key} = {variable.Value}");
                    foreach (State state in order) if (state.Kind == "history" && state.History != null) Console.WriteLine($"  history {state.Name} = {Names(state.History)}");
                    foreach (Reservation reservation in OrderedReservations())
                    {
                        if (reservation.Timer != null) Console.WriteLine($"  timer {reservation.Due} after({reservation.Timer.Delay})@{reservation.Timer.Source.Name}");
                        else Console.WriteLine($"  send {reservation.Due} {reservation.Event!.Name} {reservation.Event.Value}");
                    }
                    break;
            }
        }

        public void Statistics()
        {
            Console.WriteLine($"end t={time} macrosteps={macrosteps} microsteps={microsteps}");
            foreach (State state in order) if (state.Kind != "history") Console.WriteLine($"  {state.Name} entered={state.Entered} taken={state.Taken} time={state.Dwell + (state.Active ? time - state.EntryTime : 0)}");
        }
    }

    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        int count = int.Parse(Console.ReadLine()!);
        int number = 1;
        for (int chartIndex = 0; chartIndex < count; chartIndex++)
        {
            string header = Console.ReadLine()!;
            number++;
            List<Line> definitions = [], script = [];
            string line;
            while ((line = Console.ReadLine()!) != "RUN") definitions.Add(new Line(++number, line));
            number++;
            while ((line = Console.ReadLine()!) != "END") script.Add(new Line(++number, line));
            number++;
            Console.WriteLine("chart " + header[6..]);
            Chart chart = new();
            if (!chart.Define(definitions)) continue;
            chart.Warnings();
            chart.Macro(new Trigger("start"));
            foreach (Line command in script) chart.Script(command.Text);
            chart.Statistics();
        }
    }
}
