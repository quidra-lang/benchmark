import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;

public class Main {
    record Line(int number, String text) { }

    static class EvaluationError extends RuntimeException { }

    static class Node {
        String kind, text;
        Node left, right;

        Node(String kind, String text, Node left, Node right) {
            this.kind = kind;
            this.text = text;
            this.left = left;
            this.right = right;
        }

        String reference(Chart chart) {
            if (kind.equals("variable")) return text.equals("_data") || chart.variables.containsKey(text) ? null : "unknown variable " + text;
            if (kind.equals("in")) return chart.states.containsKey(text) ? null : "unknown state " + text;
            String error = left == null ? null : left.reference(chart);
            return error != null ? error : right == null ? null : right.reference(chart);
        }

        long evaluate(Chart chart) {
            if (kind.equals("number")) return Long.parseLong(text);
            if (kind.equals("variable")) return text.equals("_data") ? chart.data : chart.variables.get(text);
            if (kind.equals("in")) return chart.states.get(text).active ? 1 : 0;
            long a = left.evaluate(chart);
            if (kind.equals("unary")) return text.equals("-") ? -a : a == 0 ? 1 : 0;
            if (text.equals("&&") && a == 0) return 0;
            if (text.equals("||") && a != 0) return 1;
            long b = right.evaluate(chart);
            if ((text.equals("/") || text.equals("%")) && b == 0) throw new EvaluationError();
            return switch (text) {
                case "+" -> a + b;
                case "-" -> a - b;
                case "*" -> a * b;
                case "/" -> a / b;
                case "%" -> a % b;
                case "==" -> a == b ? 1 : 0;
                case "!=" -> a != b ? 1 : 0;
                case "<" -> a < b ? 1 : 0;
                case "<=" -> a <= b ? 1 : 0;
                case ">" -> a > b ? 1 : 0;
                case ">=" -> a >= b ? 1 : 0;
                case "&&", "||" -> b != 0 ? 1 : 0;
                default -> throw new IllegalStateException();
            };
        }
    }

    static class ExpressionParser {
        static final List<List<String>> OPERATORS = List.of(List.of("||"), List.of("&&"), List.of("==", "!=", "<", "<=", ">", ">="), List.of("+", "-"), List.of("*", "/", "%"));
        List<String> tokens = new ArrayList<>();
        int position;

        ExpressionParser(String text) {
            for (int i = 0; i < text.length();) {
                char c = text.charAt(i);
                if (c == ' ') {
                    i++;
                    continue;
                }
                int start = i;
                if (Character.isLetterOrDigit(c) || c == '_') {
                    while (i < text.length() && (Character.isLetterOrDigit(text.charAt(i)) || text.charAt(i) == '_')) i++;
                } else if (i + 1 < text.length() && List.of("||", "&&", "==", "!=", "<=", ">=").contains(text.substring(i, i + 2))) i += 2;
                else i++;
                tokens.add(text.substring(start, i));
            }
        }

        Node parse() {
            return level(0);
        }

        Node level(int precedence) {
            if (precedence == OPERATORS.size()) return unary();
            Node result = level(precedence + 1);
            while (position < tokens.size() && OPERATORS.get(precedence).contains(tokens.get(position))) {
                String operator = tokens.get(position++);
                result = new Node("binary", operator, result, level(precedence + 1));
            }
            return result;
        }

        Node unary() {
            String token = tokens.get(position++);
            if (token.equals("!") || token.equals("-")) return new Node("unary", token, unary(), null);
            if (token.equals("(")) {
                Node result = level(0);
                position++;
                return result;
            }
            if (token.equals("in")) {
                position++;
                String state = tokens.get(position++);
                position++;
                return new Node("in", state, null, null);
            }
            return new Node(token.charAt(0) >= '0' && token.charAt(0) <= '9' ? "number" : "variable", token, null, null);
        }
    }

    static Node expression(String text) {
        return new ExpressionParser(text).parse();
    }

    static class Action {
        String kind, name, literal;
        Node expression;
        int delay;

        String reference(Chart chart) {
            if (kind.equals("assign") && !chart.variables.containsKey(name)) return "unknown variable " + name;
            return expression == null ? null : expression.reference(chart);
        }
    }

    static List<Action> actions(String text) {
        List<Action> result = new ArrayList<>();
        for (String raw : text.split("; ", -1)) {
            Action action = new Action();
            String[] parts = raw.split(" ", 2);
            String first = parts[0], rest = parts.length > 1 ? parts[1] : "";
            switch (first) {
                case "raise", "send" -> {
                    action.kind = first;
                    String[] args = rest.split(" ", first.equals("raise") ? 2 : 3);
                    action.name = args[0];
                    if (first.equals("send")) {
                        action.delay = Integer.parseInt(args[1]);
                        if (args.length == 3) action.expression = expression(args[2]);
                    } else if (args.length == 2) action.expression = expression(args[1]);
                }
                case "cancel" -> {
                    action.kind = "cancel";
                    action.name = rest;
                }
                case "log" -> {
                    action.kind = "log";
                    action.literal = "";
                    if (rest.startsWith("\"")) {
                        int end = rest.indexOf('"', 1);
                        action.literal = rest.substring(1, end);
                        if (end + 1 < rest.length()) action.expression = expression(rest.substring(end + 2));
                    } else action.expression = expression(rest);
                }
                default -> {
                    action.kind = "assign";
                    action.name = first;
                    action.expression = expression(rest.substring(2));
                }
            }
            result.add(action);
        }
        return result;
    }

    static class State {
        String name, kind, initialName, defaultName;
        boolean deep, active;
        State parent;
        List<State> children = new ArrayList<>();
        List<List<Action>> entries = new ArrayList<>(), exits = new ArrayList<>();
        List<Transition> transitions = new ArrayList<>();
        List<State> history;
        int depth, order;
        long entered, taken, dwell, entryTime;

        State(String name, String kind, State parent) {
            this.name = name;
            this.kind = kind;
            this.parent = parent;
            depth = parent == null ? 0 : parent.depth + 1;
        }

        List<State> childStates() {
            return children.stream().filter(s -> !s.kind.equals("history")).toList();
        }

        boolean compound() {
            return parent == null || kind.equals("state") && !childStates().isEmpty();
        }

        boolean parallel() {
            return kind.equals("parallel") && !childStates().isEmpty();
        }

        boolean atomic() {
            return !kind.equals("history") && childStates().isEmpty();
        }

        boolean descendantOf(State ancestor) {
            for (State p = parent; p != null; p = p.parent) if (p == ancestor) return true;
            return false;
        }
    }

    static class Definition {
        Line line;
        String error;
        State state;

        Definition(Line line) {
            this.line = line;
        }
    }

    static class Transition {
        State source, target;
        String targetName, trigger, mode = "internal";
        String[] descriptors;
        Node guard;
        int delay;
        List<Action> actions = new ArrayList<>();
    }

    record Event(String name, long value) { }

    static class Reservation {
        long due, number;
        Transition timer;
        Event event;
    }

    record Trigger(String kind, Event event, Transition timer) { }

    record Choice(Transition transition, State scope, Set<State> exits) { }

    static class Chart {
        final State root = new State("", "state", null);
        final Map<String, State> states = new LinkedHashMap<>();
        final TreeMap<String, Long> variables = new TreeMap<>();
        final List<State> order = new ArrayList<>();
        final List<Reservation> reservations = new ArrayList<>();
        final ArrayDeque<Event> queue = new ArrayDeque<>();
        long time, data, creations, macrosteps, microsteps;
        int inMacro;
        boolean trace, halted;

        State initial(State state) {
            return state.initialName == null ? state.childStates().getFirst() : states.get(state.initialName);
        }

        State defaultTarget(State history) {
            return history.defaultName == null ? initial(history.parent) : states.get(history.defaultName);
        }

        void visit(State state) {
            state.order = order.size();
            order.add(state);
            for (State child : state.children) visit(child);
        }

        static String firstReference(List<Action> list, Chart chart) {
            for (Action action : list) {
                String error = action.reference(chart);
                if (error != null) return error;
            }
            return null;
        }

        Transition parseTransition(String text) {
            int end = text.indexOf(' ', 3);
            Transition transition = new Transition();
            transition.source = states.get(text.substring(3, end));
            String rest = text.substring(end + 1);
            if (rest.startsWith("after ")) {
                int space = rest.indexOf(' ', 6);
                transition.trigger = "timer";
                transition.delay = Integer.parseInt(space < 0 ? rest.substring(6) : rest.substring(6, space));
                rest = space < 0 ? "" : rest.substring(space + 1);
            } else {
                int space = rest.indexOf(' ');
                String trigger = space < 0 ? rest : rest.substring(0, space);
                transition.trigger = trigger.equals("always") ? "always" : "event";
                transition.descriptors = trigger.split("\\|");
                rest = space < 0 ? "" : rest.substring(space + 1);
            }
            if (rest.startsWith("[")) {
                int close = rest.indexOf(']');
                transition.guard = expression(rest.substring(1, close));
                rest = rest.substring(close + 1).stripLeading();
            }
            if (rest.startsWith("-> ") || rest.startsWith("~> ")) {
                transition.mode = rest.startsWith("~>") ? "local" : "external";
                rest = rest.substring(3);
                int space = rest.indexOf(' ');
                transition.targetName = space < 0 ? rest : rest.substring(0, space);
                rest = space < 0 ? "" : rest.substring(space + 1);
            }
            if (rest.startsWith("/ ")) transition.actions = actions(rest.substring(2));
            return transition;
        }

        boolean define(List<Line> lines) {
            List<Definition> definitions = new ArrayList<>();
            for (Line line : lines) {
                Definition definition = new Definition(line);
                definitions.add(definition);
                String[] a = line.text.split(" ");
                String kind = a[0];
                if (List.of("state", "parallel", "final", "history").contains(kind)) {
                    String parentName = a.length > 2 && !a[2].equals("initial") ? a[2] : null;
                    if (states.containsKey(a[1])) definition.error = "duplicate state " + a[1];
                    else if (parentName != null && !states.containsKey(parentName)) definition.error = "unknown state " + parentName;
                    else if (parentName != null && List.of("final", "history").contains(states.get(parentName).kind)) definition.error = parentName + " cannot have children";
                    else {
                        State parent = parentName == null ? root : states.get(parentName);
                        State state = new State(a[1], kind, parent);
                        definition.state = state;
                        states.put(a[1], state);
                        parent.children.add(state);
                        if (kind.equals("state")) for (int i = 2; i < a.length; i++) if (a[i].equals("initial")) state.initialName = a[i + 1];
                        if (kind.equals("history")) {
                            state.deep = a[3].equals("deep");
                            if (a.length == 5) state.defaultName = a[4];
                        }
                    }
                } else if (kind.equals("var")) {
                    if (variables.containsKey(a[1])) definition.error = "duplicate variable " + a[1];
                    else variables.put(a[1], Long.parseLong(a[2]));
                }
            }
            for (Definition definition : definitions) {
                if (definition.error != null) continue;
                String text = definition.line.text;
                String[] a = text.split(" ");
                String kind = a[0];
                State state = definition.state;
                if (kind.equals("state") && state.initialName != null) {
                    State child = states.get(state.initialName);
                    if (child == null) definition.error = "unknown state " + state.initialName;
                    else if (child.parent != state || child.kind.equals("history")) definition.error = child.name + " is not a child of " + state.name;
                } else if (kind.equals("final") || kind.equals("history")) {
                    if (!state.parent.kind.equals("state") || state.parent.childStates().isEmpty()) definition.error = state.name + " needs a compound parent";
                    else if (kind.equals("history") && state.defaultName != null) {
                        State target = states.get(state.defaultName);
                        if (target == null) definition.error = "unknown state " + state.defaultName;
                        else if (!target.descendantOf(state.parent) || target.kind.equals("history")) definition.error = target.name + " is not a descendant of " + state.parent.name;
                    }
                } else if (kind.equals("entry") || kind.equals("exit")) {
                    State source = states.get(a[1]);
                    if (source == null) definition.error = "unknown state " + a[1];
                    else if (source.kind.equals("history")) definition.error = source.name + " cannot have actions";
                    else {
                        List<Action> list = actions(text.substring(text.indexOf(" / ") + 3));
                        definition.error = firstReference(list, this);
                        if (definition.error == null) (kind.equals("entry") ? source.entries : source.exits).add(list);
                    }
                } else if (kind.equals("on")) {
                    State source = states.get(a[1]);
                    if (source == null) definition.error = "unknown state " + a[1];
                    else if (List.of("final", "history").contains(source.kind)) definition.error = source.name + " cannot have transitions";
                    else {
                        Transition transition = parseTransition(text);
                        String error = transition.guard == null ? null : transition.guard.reference(this);
                        if (error == null && transition.targetName != null && !states.containsKey(transition.targetName)) error = "unknown state " + transition.targetName;
                        if (error == null) error = firstReference(transition.actions, this);
                        definition.error = error;
                        if (error == null) {
                            transition.target = transition.targetName == null ? null : states.get(transition.targetName);
                            source.transitions.add(transition);
                        }
                    }
                }
            }
            boolean valid = true;
            for (Definition definition : definitions) if (definition.error != null) {
                System.out.println("error line " + definition.line.number + ": " + definition.error);
                valid = false;
            }
            if (!valid) return false;
            for (State child : root.children) visit(child);
            return true;
        }

        void warnings() {
            Set<State> reachable = new HashSet<>();
            reachable.add(initial(root));
            boolean changed;
            do {
                int before = reachable.size();
                for (State state : new ArrayList<>(reachable)) {
                    if (state.parent != root) reachable.add(state.parent);
                    if (state.compound()) reachable.add(initial(state));
                    if (state.parallel()) reachable.addAll(state.childStates());
                    for (Transition transition : state.transitions) if (transition.target != null) reachable.add(transition.target.kind.equals("history") ? defaultTarget(transition.target) : transition.target);
                }
                changed = reachable.size() != before;
            } while (changed);
            for (State state : order) if (!state.kind.equals("history") && !reachable.contains(state)) System.out.println("warning: unreachable state " + state.name);
        }

        List<State> effective(Transition transition) {
            State target = transition.target;
            if (!target.kind.equals("history")) return List.of(target);
            return target.history == null ? List.of(defaultTarget(target)) : target.history;
        }

        Choice choice(Transition transition) {
            if (transition.target == null) return new Choice(transition, null, Set.of());
            List<State> targets = effective(transition);
            State scope = null;
            if (transition.mode.equals("local") && transition.source.compound() && targets.stream().allMatch(s -> s.descendantOf(transition.source))) scope = transition.source;
            else for (State ancestor = transition.source.parent; ancestor != null; ancestor = ancestor.parent) {
                State candidate = ancestor;
                if (candidate.compound() && targets.stream().allMatch(s -> s.descendantOf(candidate))) {
                    scope = candidate;
                    break;
                }
            }
            Set<State> exits = new HashSet<>();
            for (State state : order) if (state.active && state.descendantOf(scope)) exits.add(state);
            return new Choice(transition, scope, exits);
        }

        boolean matches(Transition transition, Trigger trigger) {
            if (trigger.kind.equals("always")) return transition.trigger.equals("always");
            if (trigger.kind.equals("timer")) return transition == trigger.timer;
            if (!transition.trigger.equals("event")) return false;
            for (String descriptor : transition.descriptors) if (descriptor.equals("*") || descriptor.equals(trigger.event.name) || trigger.event.name.startsWith(descriptor + ".")) return true;
            return false;
        }

        List<Choice> select(Trigger trigger) {
            List<Transition> candidates = new ArrayList<>();
            Set<Transition> seen = new HashSet<>();
            for (State atomic : order) if (atomic.active && atomic.atomic()) {
                Transition selected = null;
                search: for (State state = atomic; state != root; state = state.parent) for (Transition transition : state.transitions) if (matches(transition, trigger)) {
                    boolean guard = true;
                    try {
                        guard = transition.guard == null || transition.guard.evaluate(this) != 0;
                    } catch (EvaluationError error) {
                        queue.add(new Event("error.execution", 0));
                        guard = false;
                    }
                    if (guard) {
                        selected = transition;
                        break search;
                    }
                }
                if (selected != null && seen.add(selected)) candidates.add(selected);
            }
            List<Choice> result = new ArrayList<>();
            Set<State> exited = new HashSet<>();
            for (Transition transition : candidates) {
                Choice candidate = choice(transition);
                if (candidate.exits.stream().noneMatch(exited::contains)) {
                    result.add(candidate);
                    exited.addAll(candidate.exits);
                }
            }
            return result;
        }

        void reserve(Transition timer, Event event, long delay) {
            Reservation reservation = new Reservation();
            reservation.timer = timer;
            reservation.event = event;
            reservation.due = time + delay;
            reservation.number = ++creations;
            reservations.add(reservation);
        }

        void perform(List<Action> list) {
            for (Action action : list) {
                long value;
                try {
                    value = action.expression == null ? 0 : action.expression.evaluate(this);
                } catch (EvaluationError error) {
                    queue.add(new Event("error.execution", 0));
                    return;
                }
                switch (action.kind) {
                    case "assign" -> variables.put(action.name, value);
                    case "raise" -> queue.add(new Event(action.name, value));
                    case "send" -> reserve(null, new Event(action.name, value), action.delay);
                    case "cancel" -> reservations.removeIf(r -> r.event != null && r.event.name.equals(action.name));
                    case "log" -> System.out.println(action.literal + (action.expression == null ? "" : Long.toString(value)));
                    default -> throw new IllegalStateException();
                }
            }
        }

        void expand(Set<State> entry) {
            boolean changed;
            do {
                int before = entry.size();
                for (State state : order) if (entry.contains(state)) {
                    if (state.parallel()) entry.addAll(state.childStates());
                    if (state.compound() && state.childStates().stream().noneMatch(entry::contains)) entry.add(initial(state));
                }
                changed = entry.size() != before;
            } while (changed);
        }

        boolean complete(State state) {
            if (state.compound()) return state.childStates().stream().anyMatch(s -> s.kind.equals("final") && s.active);
            if (state.parallel()) return state.childStates().stream().allMatch(this::complete);
            return false;
        }

        void enter(Set<State> entry) {
            for (State state : order) if (entry.contains(state)) {
                state.active = true;
                state.entered++;
                state.entryTime = time;
                for (Transition transition : state.transitions) if (transition.trigger.equals("timer")) reserve(transition, null, transition.delay);
                for (List<Action> list : state.entries) perform(list);
                if (state.kind.equals("final")) {
                    State parent = state.parent;
                    queue.add(new Event("done.state." + parent.name, 0));
                    State grandparent = parent.parent;
                    if (grandparent != null && grandparent.parallel() && grandparent.childStates().stream().allMatch(this::complete)) queue.add(new Event("done.state." + grandparent.name, 0));
                }
            }
        }

        String list(List<State> list) {
            return list.isEmpty() ? "-" : String.join(",", list.stream().map(s -> s.name).toList());
        }

        String display(Trigger trigger) {
            if (trigger.kind.equals("always")) return "always";
            if (trigger.kind.equals("timer")) return "after(" + trigger.timer.delay + ")@" + trigger.timer.source.name;
            return trigger.event.name + (trigger.event.value == 0 ? "" : "=" + trigger.event.value);
        }

        boolean micro(List<Choice> selected, Trigger trigger) {
            if (inMacro == 1000) {
                System.out.println("LIVELOCK t=" + time);
                halted = true;
                return false;
            }
            inMacro++;
            microsteps++;
            Set<State> exits = new HashSet<>();
            for (Choice choice : selected) exits.addAll(choice.exits);
            for (State history : order) if (history.kind.equals("history") && exits.contains(history.parent)) history.history = order.stream().filter(s -> s.active && (history.deep ? s.atomic() && s.descendantOf(history.parent) : s.parent == history.parent && !s.kind.equals("history"))).toList();
            Set<State> entry = new HashSet<>();
            for (Choice choice : selected) if (choice.transition.target != null) for (State target : effective(choice.transition)) for (State state = target; state != choice.scope; state = state.parent) entry.add(state);
            expand(entry);
            List<State> exitOrder = order.stream().filter(exits::contains).sorted(Comparator.comparingInt((State s) -> s.order).reversed()).toList();
            if (trace) System.out.println("[t=" + time + "] " + display(trigger) + " (" + list(selected.stream().map(c -> c.transition.source).toList()) + "): exit " + list(exitOrder) + "; enter " + list(order.stream().filter(entry::contains).toList()));
            for (State state : exitOrder) {
                for (List<Action> list : state.exits) perform(list);
                state.active = false;
                state.dwell += time - state.entryTime;
                reservations.removeIf(r -> r.timer != null && r.timer.source == state);
            }
            for (Choice choice : selected) {
                perform(choice.transition.actions);
                choice.transition.source.taken++;
            }
            enter(entry);
            return true;
        }

        void macro(Trigger trigger) {
            macrosteps++;
            inMacro = 0;
            if (trigger.kind.equals("start")) {
                data = 0;
                Set<State> entry = new HashSet<>();
                entry.add(initial(root));
                expand(entry);
                enter(entry);
            } else {
                data = trigger.kind.equals("timer") ? 0 : trigger.event.value;
                List<Choice> selected = select(trigger);
                if (!selected.isEmpty() && !micro(selected, trigger)) return;
            }
            while (!halted) {
                data = 0;
                Trigger always = new Trigger("always", null, null);
                List<Choice> selected = select(always);
                if (!selected.isEmpty()) {
                    if (!micro(selected, always)) return;
                    continue;
                }
                if (queue.isEmpty()) return;
                Event event = queue.remove();
                data = event.value;
                Trigger internal = new Trigger("event", event, null);
                selected = select(internal);
                if (!selected.isEmpty() && !micro(selected, internal)) return;
            }
        }
        static final Comparator<Reservation> RESERVATION_ORDER = Comparator.comparingLong((Reservation r) -> r.due).thenComparingLong(r -> r.number);

        void script(String text) {
            if (halted) return;
            String[] a = text.split(" ", 3);
            switch (a[0]) {
                case "event" -> macro(new Trigger("event", new Event(a[1], a.length == 3 ? Long.parseLong(a[2]) : 0), null));
                case "tick" -> {
                    long finish = time + Long.parseLong(a[1]);
                    while (!halted) {
                        Reservation next = reservations.stream().filter(r -> r.due <= finish).min(RESERVATION_ORDER).orElse(null);
                        if (next == null) break;
                        reservations.remove(next);
                        time = next.due;
                        macro(next.timer == null ? new Trigger("event", next.event, null) : new Trigger("timer", null, next.timer));
                    }
                    if (!halted) time = finish;
                }
                case "set" -> {
                    if (!variables.containsKey(a[1])) System.out.println("error: unknown variable " + a[1]);
                    else variables.put(a[1], Long.parseLong(a[2]));
                }
                case "trace" -> trace = a[1].equals("on");
                case "eval" -> {
                    String raw = text.substring(5);
                    Node node = expression(raw);
                    String error = node.reference(this);
                    if (error != null) System.out.println("error: " + error);
                    else {
                        data = 0;
                        try {
                            System.out.println(raw + " -> " + node.evaluate(this));
                        } catch (EvaluationError failure) {
                            System.out.println("error: division by zero");
                        }
                    }
                }
                case "dump" -> {
                    System.out.println("dump t=" + time);
                    for (State state : order) if (state.active) System.out.println("  ".repeat(state.depth) + state.name);
                    for (Map.Entry<String, Long> variable : variables.entrySet()) System.out.println("  var " + variable.getKey() + " = " + variable.getValue());
                    for (State state : order) if (state.kind.equals("history") && state.history != null) System.out.println("  history " + state.name + " = " + list(state.history));
                    for (Reservation reservation : reservations.stream().sorted(RESERVATION_ORDER).toList()) {
                        if (reservation.timer != null) System.out.println("  timer " + reservation.due + " after(" + reservation.timer.delay + ")@" + reservation.timer.source.name);
                        else System.out.println("  send " + reservation.due + " " + reservation.event.name + " " + reservation.event.value);
                    }
                }
                default -> throw new IllegalStateException();
            }
        }

        void statistics() {
            System.out.println("end t=" + time + " macrosteps=" + macrosteps + " microsteps=" + microsteps);
            for (State state : order) if (!state.kind.equals("history")) System.out.println("  " + state.name + " entered=" + state.entered + " taken=" + state.taken + " time=" + (state.dwell + (state.active ? time - state.entryTime : 0)));
        }
    }
    public static void main(String[] args) throws Exception {
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
        int count = Integer.parseInt(reader.readLine()), number = 1;
        for (int chartIndex = 0; chartIndex < count; chartIndex++) {
            String header = reader.readLine();
            number++;
            List<Line> definitions = new ArrayList<>(), script = new ArrayList<>();
            String line;
            while (!(line = reader.readLine()).equals("RUN")) definitions.add(new Line(++number, line));
            number++;
            while (!(line = reader.readLine()).equals("END")) script.add(new Line(++number, line));
            number++;
            System.out.println("chart " + header.substring(6));
            Chart chart = new Chart();
            if (!chart.define(definitions)) continue;
            chart.warnings();
            chart.macro(new Trigger("start", null, null));
            for (Line command : script) chart.script(command.text);
            chart.statistics();
        }
    }
}
