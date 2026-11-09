import * as fs from "node:fs";

interface SourceLine {
    text: string;
    line: number;
}
interface Reference {
    kind: "state" | "variable";
    name: string;
}
type Node =
    | { kind: "number"; value: number }
    | { kind: "variable"; name: string }
    | { kind: "state"; name: string }
    | { kind: "unary"; operator: string; value: Node }
    | { kind: "binary"; operator: string; left: Node; right: Node };
interface Expression {
    node: Node;
    references: Reference[];
}
type Action =
    | { kind: "assign"; name: string; expression: Expression }
    | { kind: "raise" | "send"; event: string; delay: number; expression: Expression | null }
    | { kind: "cancel"; event: string; expression: null }
    | { kind: "log"; text: string; expression: Expression | null };
interface State {
    name: string;
    kind: string;
    parent: State | null;
    line: number;
    initial: string | null;
    mode: string;
    fallback: string | null;
    children: State[];
    entries: Action[][];
    exits: Action[][];
    transitions: Transition[];
    depth: number;
    entered: number;
    taken: number;
    dwell: number;
    enteredAt: number;
    history: State[] | null;
}
interface Transition {
    source: State;
    kind: string;
    target: State | null;
    guard: Expression | null;
    type: string;
    delay: number;
    descriptors: string[];
    actions: Action[];
}
interface TransitionParts {
    trigger: string;
    guard: Expression | null;
    target: string | null;
    kind: string;
    actions: Action[];
}
interface Definition extends SourceLine {
    kind: string;
    name: string;
    state: State | null;
}
interface Chart {
    root: State;
    states: Map<string, State>;
    variables: Map<string, number>;
    errors: Map<number, string>;
    order: State[];
    checkReferences: (references: Reference[]) => string | null;
}
interface Event {
    name: string;
    value: number;
}
type SelectionTrigger =
    | { kind: "always" }
    | { kind: "timer"; transition: Transition }
    | { kind: "event"; event: Event };
type Trigger = Extract<SelectionTrigger, { kind: "event" | "timer" }> | { kind: "start" };
interface TimerReservation {
    kind: "timer";
    due: number;
    serial: number;
    transition: Transition;
}
interface SendReservation {
    kind: "send";
    due: number;
    serial: number;
    event: Event;
}
type Reservation = TimerReservation | SendReservation;
type NewReservation = Omit<TimerReservation, "serial"> | Omit<SendReservation, "serial">;
interface Choice {
    transition: Transition;
    scope: State | null;
    exits: Set<State>;
}

class EvaluationError extends Error {}
function expression(text: string): Expression {
    const tokens = text.match(/[0-9]+|[A-Za-z_][A-Za-z0-9_]*|\|\||&&|==|!=|<=|>=|[<>+*/%!()-]/g)!;
    const references: Reference[] = [];
    let at = 0;
    function primary(): Node {
        const token = tokens[at++];
        if (token === "-" || token === "!")
            return { kind: "unary", operator: token, value: primary() };
        if (token === "(") {
            const value = binary(0);
            at++;
            return value;
        }
        if (/^[0-9]/.test(token)) return { kind: "number", value: Number(token) };
        if (token === "in") {
            at++;
            const name = tokens[at++];
            at++;
            references.push({ kind: "state", name });
            return { kind: "state", name };
        }
        if (token !== "_data") references.push({ kind: "variable", name: token });
        return { kind: "variable", name: token };
    }
    function binary(level: number): Node {
        if (level === 5) return primary();
        const operators = [
            ["||"],
            ["&&"],
            ["==", "!=", "<", "<=", ">", ">="],
            ["+", "-"],
            ["*", "/", "%"],
        ][level];
        let left: Node = binary(level + 1);
        while (operators.includes(tokens[at])) {
            const operator = tokens[at++],
                right = binary(level + 1);
            left = { kind: "binary", operator, left, right };
        }
        return left;
    }
    return { node: binary(0), references };
}
function actions(text: string): Action[] {
    if (text === "") return [];
    return text.split("; ").map((part): Action => {
        const space = part.indexOf(" "),
            first = part.slice(0, space),
            rest = part.slice(space + 1);
        if (first === "log") {
            if (rest.startsWith('"')) {
                const close = rest.indexOf('"', 1);
                return {
                    kind: "log",
                    text: rest.slice(1, close),
                    expression:
                        close + 1 === rest.length ? null : expression(rest.slice(close + 2)),
                };
            }
            return { kind: "log", text: "", expression: expression(rest) };
        }
        if (first === "cancel") return { kind: "cancel", event: rest, expression: null };
        if (first === "raise" || first === "send") {
            const words = rest.split(" "),
                event = words.shift()!,
                delay = first === "send" ? Number(words.shift()) : 0;
            return {
                kind: first,
                event,
                delay,
                expression: words.length ? expression(words.join(" ")) : null,
            };
        }
        return { kind: "assign", name: first, expression: expression(rest.slice(2)) };
    });
}
function actionReferences(list: Action[]): Reference[] {
    const references: Reference[] = [];
    for (const action of list) {
        if (action.kind === "assign") references.push({ kind: "variable", name: action.name });
        if (action.expression !== null) references.push(...action.expression.references);
    }
    return references;
}
function transitionParts(text: string): TransitionParts {
    const first = text.indexOf(" ");
    let trigger: string, rest: string;
    if (text.startsWith("after ")) {
        const end = text.indexOf(" ", 6);
        trigger = end < 0 ? text : text.slice(0, end);
        rest = end < 0 ? "" : text.slice(end);
    } else {
        trigger = first < 0 ? text : text.slice(0, first);
        rest = first < 0 ? "" : text.slice(first);
    }
    let guard: Expression | null = null;
    let target: string | null = null;
    let kind = "internal";
    if (rest.startsWith(" [")) {
        const end = rest.indexOf("]");
        guard = expression(rest.slice(2, end));
        rest = rest.slice(end + 1);
    }
    if (rest.startsWith(" -> ") || rest.startsWith(" ~> ")) {
        kind = rest[1] === "-" ? "external" : "local";
        rest = rest.slice(4);
        const end = rest.indexOf(" ");
        target = end < 0 ? rest : rest.slice(0, end);
        rest = end < 0 ? "" : rest.slice(end);
    }
    return { trigger, guard, target, kind, actions: actions(rest === "" ? "" : rest.slice(3)) };
}
function stateNode(
    name: string,
    kind: string,
    parent: State | null,
    line: number,
    initial: string | null,
    mode: string,
    fallback: string | null,
): State {
    return {
        name,
        kind,
        parent,
        line,
        initial,
        mode,
        fallback,
        children: [],
        entries: [],
        exits: [],
        transitions: [],
        depth: parent === null ? 0 : parent.depth + 1,
        entered: 0,
        taken: 0,
        dwell: 0,
        enteredAt: 0,
        history: null,
    };
}
function childStates(state: State): State[] {
    return state.children.filter((child) => child.kind !== "history");
}
function compound(state: State): boolean {
    return state.parent === null || (state.kind === "state" && childStates(state).length > 0);
}
function parallel(state: State): boolean {
    return state.kind === "parallel" && childStates(state).length > 0;
}
function atomic(state: State): boolean {
    return state.kind !== "history" && childStates(state).length === 0;
}
function descendant(state: State, ancestor: State): boolean {
    for (let parent = state.parent; parent !== null; parent = parent.parent)
        if (parent === ancestor) return true;
    return false;
}
function initial(state: State, states: Map<string, State>): State {
    return state.initial === null ? childStates(state)[0] : states.get(state.initial)!;
}
function fallback(state: State, states: Map<string, State>): State {
    return state.fallback === null ? initial(state.parent!, states) : states.get(state.fallback)!;
}
function document(root: State): State[] {
    const result: State[] = [];
    function visit(state: State): void {
        result.push(state);
        for (const child of state.children) visit(child);
    }
    for (const state of root.children) visit(state);
    return result;
}
function build(lines: SourceLine[]): Chart {
    const root = stateNode("", "state", null, 0, null, "", null);
    const states = new Map<string, State>(),
        variables = new Map<string, number>(),
        errors = new Map<number, string>();
    const definitions: Definition[] = [];
    for (const source of lines) {
        const words = source.text.split(" "),
            kind = words[0],
            name = words[1];
        const definition: Definition = { ...source, kind, name, state: null };
        definitions.push(definition);
        if (["state", "parallel", "final", "history"].includes(kind)) {
            let parentName: string | null = null,
                selected: string | null = null,
                defaultTarget: string | null = null;
            let mode = "";
            if (kind === "state") {
                if (words[2] === "initial") selected = words[3];
                else {
                    parentName = words[2] ?? null;
                    if (words[3] === "initial") selected = words[4];
                }
            } else {
                parentName = words[2] ?? null;
                if (kind === "history") {
                    mode = words[3];
                    defaultTarget = words[4] ?? null;
                }
            }
            if (states.has(name)) errors.set(source.line, "duplicate state " + name);
            else if (parentName !== null && !states.has(parentName))
                errors.set(source.line, "unknown state " + parentName);
            else if (
                parentName !== null &&
                ["final", "history"].includes(states.get(parentName)!.kind)
            )
                errors.set(source.line, parentName + " cannot have children");
            else {
                const parent = parentName === null ? root : states.get(parentName)!,
                    state = stateNode(
                        name,
                        kind,
                        parent,
                        source.line,
                        selected,
                        mode,
                        defaultTarget,
                    );
                parent.children.push(state);
                states.set(name, state);
                definition.state = state;
            }
        } else if (kind === "var") {
            if (variables.has(name)) errors.set(source.line, "duplicate variable " + name);
            else variables.set(name, Number(words[2]));
        }
    }
    function checkReferences(references: Reference[]): string | null {
        for (const reference of references)
            if (!(reference.kind === "state" ? states : variables).has(reference.name))
                return "unknown " + reference.kind + " " + reference.name;
        return null;
    }
    for (const definition of definitions) {
        if (errors.has(definition.line)) continue;
        const { kind, name } = definition;
        const state = definition.state!;
        let error: string | null = null;
        if (kind === "state" && state.initial !== null) {
            const child = states.get(state.initial)!;
            if (child === undefined) error = "unknown state " + state.initial;
            else if (child.parent !== state || child.kind === "history")
                error = child.name + " is not a child of " + name;
        } else if (kind === "final" || kind === "history") {
            if (state.parent!.kind !== "state" || !compound(state.parent!))
                error = name + " needs a compound parent";
            else if (kind === "history" && state.fallback !== null) {
                const target = states.get(state.fallback);
                if (target === undefined) error = "unknown state " + state.fallback;
                else if (!descendant(target, state.parent!) || target.kind === "history")
                    error = target.name + " is not a descendant of " + state.parent!.name;
            }
        } else if (kind === "entry" || kind === "exit" || kind === "on") {
            const source = states.get(name);
            if (source === undefined) error = "unknown state " + name;
            else if (source.kind === "history" && kind !== "on")
                error = name + " cannot have actions";
            else if (kind === "on" && ["final", "history"].includes(source.kind))
                error = name + " cannot have transitions";
            else if (kind === "on") {
                const part = transitionParts(definition.text.slice(("on " + name + " ").length));
                const references: Reference[] =
                    part.guard === null ? [] : [...part.guard.references];
                if (part.target !== null) references.push({ kind: "state", name: part.target });
                references.push(...actionReferences(part.actions));
                error = checkReferences(references);
                if (error === null)
                    source.transitions.push({
                        source,
                        kind: part.kind,
                        target: part.target === null ? null : states.get(part.target)!,
                        guard: part.guard,
                        type:
                            part.trigger === "always"
                                ? "always"
                                : part.trigger.startsWith("after ")
                                  ? "timer"
                                  : "event",
                        delay: part.trigger.startsWith("after ")
                            ? Number(part.trigger.slice(6))
                            : 0,
                        descriptors: part.trigger.split("|"),
                        actions: part.actions,
                    });
            } else {
                const list = actions(definition.text.slice(definition.text.indexOf(" / ") + 3));
                error = checkReferences(actionReferences(list));
                if (error === null) (kind === "entry" ? source.entries : source.exits).push(list);
            }
        }
        if (error !== null) errors.set(definition.line, error);
    }
    return { root, states, variables, errors, order: document(root), checkReferences };
}
function names(states: State[]): string {
    return states.map((state) => state.name).join(",") || "-";
}
function warnings(chart: Chart, output: string[]): void {
    const reachable = new Set([initial(chart.root, chart.states)]);
    let changed = true;
    while (changed) {
        changed = false;
        function add(state: State): void {
            if (!reachable.has(state)) {
                reachable.add(state);
                changed = true;
            }
        }
        for (const state of [...reachable]) {
            if (state.parent !== chart.root) add(state.parent!);
            if (compound(state)) add(initial(state, chart.states));
            if (parallel(state)) for (const child of childStates(state)) add(child);
            for (const transition of state.transitions)
                if (transition.target !== null)
                    add(
                        transition.target.kind === "history"
                            ? fallback(transition.target, chart.states)
                            : transition.target,
                    );
        }
    }
    for (const state of chart.order)
        if (state.kind !== "history" && !reachable.has(state))
            output.push("warning: unreachable state " + state.name);
}
class Machine {
    chart: Chart;
    output: string[];
    configuration: Set<State>;
    variables: Map<string, number>;
    data: number;
    queue: Event[];
    reservations: Reservation[];
    serial: number;
    time: number;
    trace: boolean;
    halted: boolean;
    macrosteps: number;
    microsteps: number;
    constructor(chart: Chart, output: string[]) {
        this.chart = chart;
        this.output = output;
        this.configuration = new Set();
        this.variables = new Map(chart.variables);
        this.data = 0;
        this.queue = [];
        this.reservations = [];
        this.serial = 0;
        this.time = 0;
        this.trace = false;
        this.halted = false;
        this.macrosteps = 0;
        this.microsteps = 0;
    }
    evaluate(expression: Expression): number {
        return this.value(expression.node);
    }
    value(node: Node): number {
        if (node.kind === "number") return node.value;
        if (node.kind === "variable")
            return node.name === "_data" ? this.data : this.variables.get(node.name)!;
        if (node.kind === "state")
            return Number(this.configuration.has(this.chart.states.get(node.name)!));
        if (node.kind === "unary") {
            const value = this.value(node.value);
            return node.operator === "-" ? -value : Number(value === 0);
        }
        const a = this.value(node.left);
        if (node.operator === "&&" && a === 0) return 0;
        if (node.operator === "||" && a !== 0) return 1;
        const b = this.value(node.right);
        if (["/", "%"].includes(node.operator) && b === 0) throw new EvaluationError();
        switch (node.operator) {
            case "+":
                return a + b;
            case "-":
                return a - b;
            case "*":
                return a * b;
            case "/":
                return Math.trunc(a / b);
            case "%":
                return a % b;
            case "==":
                return Number(a === b);
            case "!=":
                return Number(a !== b);
            case "<":
                return Number(a < b);
            case "<=":
                return Number(a <= b);
            case ">":
                return Number(a > b);
            case ">=":
                return Number(a >= b);
            default:
                return Number(b !== 0);
        }
    }
    enqueue(name: string, value = 0): void {
        this.queue.push({ name, value });
    }
    reserve(reservation: NewReservation): void {
        this.reservations.push({ ...reservation, serial: ++this.serial });
    }
    actionList(list: Action[]): void {
        for (const action of list) {
            try {
                const value = action.expression === null ? 0 : this.evaluate(action.expression);
                switch (action.kind) {
                    case "assign":
                        this.variables.set(action.name, value);
                        break;
                    case "raise":
                        this.enqueue(action.event, value);
                        break;
                    case "send":
                        this.reserve({
                            kind: "send",
                            due: this.time + action.delay,
                            event: { name: action.event, value },
                        });
                        break;
                    case "cancel":
                        this.reservations = this.reservations.filter(
                            (item) => item.kind !== "send" || item.event.name !== action.event,
                        );
                        break;
                    case "log":
                        this.output.push(
                            action.text + (action.expression === null ? "" : String(value)),
                        );
                        break;
                }
            } catch (error) {
                if (!(error instanceof EvaluationError)) throw error;
                this.enqueue("error.execution");
                break;
            }
        }
    }
    effective(transition: Transition): State[] {
        const target = transition.target!;
        return target.kind === "history"
            ? (target.history ?? [fallback(target, this.chart.states)])
            : [target];
    }
    choice(transition: Transition): Choice {
        if (transition.kind === "internal") return { transition, scope: null, exits: new Set() };
        const targets = this.effective(transition);
        let scope =
            transition.kind === "local" &&
            compound(transition.source) &&
            targets.every((target) => descendant(target, transition.source))
                ? transition.source
                : transition.source.parent;
        while (!compound(scope!) || !targets.every((target) => descendant(target, scope!)))
            scope = scope!.parent;
        return {
            transition,
            scope,
            exits: new Set(
                this.chart.order.filter(
                    (state) => this.configuration.has(state) && descendant(state, scope!),
                ),
            ),
        };
    }
    matches(transition: Transition, trigger: SelectionTrigger): boolean {
        if (trigger.kind === "always") return transition.type === "always";
        if (trigger.kind === "timer") return transition === trigger.transition;
        return (
            transition.type === "event" &&
            transition.descriptors.some(
                (descriptor) =>
                    descriptor === "*" ||
                    descriptor === trigger.event.name ||
                    trigger.event.name.startsWith(descriptor + "."),
            )
        );
    }
    select(trigger: SelectionTrigger): Choice[] {
        const candidates: Choice[] = [];
        const seen = new Set<Transition>();
        for (const leaf of this.chart.order)
            if (atomic(leaf) && this.configuration.has(leaf)) {
                let found: Transition | null = null;
                for (
                    let state = leaf;
                    state !== this.chart.root && found === null;
                    state = state.parent!
                ) {
                    for (const transition of state.transitions)
                        if (this.matches(transition, trigger)) {
                            let enabled = true;
                            try {
                                enabled =
                                    transition.guard === null ||
                                    this.evaluate(transition.guard) !== 0;
                            } catch (error) {
                                if (!(error instanceof EvaluationError)) throw error;
                                this.enqueue("error.execution");
                                enabled = false;
                            }
                            if (enabled) {
                                found = transition;
                                break;
                            }
                        }
                }
                if (found !== null && !seen.has(found)) {
                    seen.add(found);
                    candidates.push(this.choice(found));
                }
            }
        const chosen: Choice[] = [];
        const exited = new Set<State>();
        for (const choice of candidates)
            if (![...choice.exits].some((state) => exited.has(state))) {
                chosen.push(choice);
                for (const state of choice.exits) exited.add(state);
            }
        return chosen;
    }
    closeEntry(set: Set<State>): State[] {
        let changed = true;
        while (changed) {
            changed = false;
            for (const state of [...set]) {
                const children = parallel(state)
                    ? childStates(state)
                    : compound(state) && !childStates(state).some((child) => set.has(child))
                      ? [initial(state, this.chart.states)]
                      : [];
                for (const child of children)
                    if (!set.has(child)) {
                        set.add(child);
                        changed = true;
                    }
            }
        }
        return this.chart.order.filter((state) => set.has(state));
    }
    complete(state: State): boolean {
        if (atomic(state)) return false;
        if (compound(state))
            return childStates(state).some(
                (child) => child.kind === "final" && this.configuration.has(child),
            );
        return parallel(state) && childStates(state).every((child) => this.complete(child));
    }
    enter(states: State[]): void {
        for (const state of states) {
            this.configuration.add(state);
            state.entered++;
            state.enteredAt = this.time;
            for (const transition of state.transitions)
                if (transition.type === "timer")
                    this.reserve({ kind: "timer", due: this.time + transition.delay, transition });
            for (const list of state.entries) this.actionList(list);
            if (state.kind === "final") {
                this.enqueue("done.state." + state.parent!.name);
                const grandparent = state.parent!.parent!;
                if (
                    parallel(grandparent) &&
                    childStates(grandparent).every((child) => this.complete(child))
                )
                    this.enqueue("done.state." + grandparent.name);
            }
        }
    }
    display(trigger: SelectionTrigger): string {
        return trigger.kind === "always"
            ? "always"
            : trigger.kind === "timer"
              ? `after(${trigger.transition.delay})@${trigger.transition.source.name}`
              : trigger.event.name + (trigger.event.value === 0 ? "" : "=" + trigger.event.value);
    }
    microstep(chosen: Choice[], trigger: SelectionTrigger): void {
        const exits = new Set(chosen.flatMap((choice) => [...choice.exits]));
        for (const history of this.chart.order)
            if (history.kind === "history" && exits.has(history.parent!))
                history.history = this.chart.order.filter(
                    (state) =>
                        this.configuration.has(state) &&
                        (history.mode === "deep"
                            ? atomic(state) && descendant(state, history.parent!)
                            : state.parent === history.parent && state.kind !== "history"),
                );
        const set = new Set<State>();
        for (const choice of chosen)
            if (choice.transition.kind !== "internal")
                for (const target of this.effective(choice.transition))
                    for (
                        let state: State | null = target;
                        state !== choice.scope;
                        state = state!.parent
                    )
                        set.add(state!);
        const entries = this.closeEntry(set),
            leaving = this.chart.order.filter((state) => exits.has(state)).reverse();
        if (this.trace)
            this.output.push(
                `[t=${this.time}] ${this.display(trigger)} (${names(chosen.map((choice) => choice.transition.source))}): exit ${names(leaving)}; enter ${names(entries)}`,
            );
        for (const state of leaving) {
            for (const list of state.exits) this.actionList(list);
            this.configuration.delete(state);
            state.dwell += this.time - state.enteredAt;
            this.reservations = this.reservations.filter(
                (item) => item.kind !== "timer" || item.transition.source !== state,
            );
        }
        for (const choice of chosen) {
            this.actionList(choice.transition.actions);
            choice.transition.source.taken++;
        }
        this.enter(entries);
    }
    macrostep(trigger: Trigger): void {
        this.macrosteps++;
        let count = 0;
        const perform = (chosen: Choice[], cause: SelectionTrigger): void => {
            if (count === 1000) {
                this.output.push("LIVELOCK t=" + this.time);
                this.halted = true;
                return;
            }
            count++;
            this.microsteps++;
            this.microstep(chosen, cause);
        };
        if (trigger.kind === "start") {
            this.data = 0;
            this.enter(this.closeEntry(new Set([initial(this.chart.root, this.chart.states)])));
        } else {
            this.data = trigger.kind === "timer" ? 0 : trigger.event.value;
            const chosen = this.select(trigger);
            if (chosen.length) perform(chosen, trigger);
        }
        while (!this.halted) {
            this.data = 0;
            const always: SelectionTrigger = { kind: "always" };
            const chosen = this.select(always);
            if (chosen.length) {
                perform(chosen, always);
                continue;
            }
            if (!this.queue.length) break;
            const event = this.queue.shift()!;
            const cause: SelectionTrigger = { kind: "event", event };
            this.data = event.value;
            const selected = this.select(cause);
            if (selected.length) perform(selected, cause);
        }
    }
    sortedReservations(): Reservation[] {
        return [...this.reservations].sort((a, b) => a.due - b.due || a.serial - b.serial);
    }
    nextReservation(): Reservation | undefined {
        let result: Reservation | undefined;
        for (const item of this.reservations) {
            if (
                result === undefined ||
                item.due < result.due ||
                (item.due === result.due && item.serial < result.serial)
            )
                result = item;
        }
        return result;
    }
    script(line: string): void {
        if (this.halted) return;
        const words = line.split(" "),
            command = words[0];
        if (command === "event")
            this.macrostep({
                kind: "event",
                event: { name: words[1], value: words.length === 3 ? Number(words[2]) : 0 },
            });
        else if (command === "tick") {
            const finish = this.time + Number(words[1]);
            while (!this.halted) {
                const first = this.nextReservation();
                if (first === undefined || first.due > finish) break;
                this.reservations.splice(this.reservations.indexOf(first), 1);
                this.time = first.due;
                this.macrostep(
                    first.kind === "timer"
                        ? { kind: "timer", transition: first.transition }
                        : { kind: "event", event: first.event },
                );
            }
            if (!this.halted) this.time = finish;
        } else if (command === "set") {
            if (!this.variables.has(words[1]))
                this.output.push("error: unknown variable " + words[1]);
            else this.variables.set(words[1], Number(words[2]));
        } else if (command === "trace") this.trace = words[1] === "on";
        else if (command === "eval") {
            const text = line.slice(5),
                parsed = expression(text),
                error = this.chart.checkReferences(parsed.references);
            if (error !== null) this.output.push("error: " + error);
            else {
                this.data = 0;
                try {
                    this.output.push(text + " -> " + this.evaluate(parsed));
                } catch (error) {
                    if (!(error instanceof EvaluationError)) throw error;
                    this.output.push("error: division by zero");
                }
            }
        } else if (command === "dump") {
            this.output.push("dump t=" + this.time);
            for (const state of this.chart.order)
                if (this.configuration.has(state))
                    this.output.push(" ".repeat(2 * state.depth) + state.name);
            for (const name of [...this.variables.keys()].sort())
                this.output.push(`  var ${name} = ${this.variables.get(name)}`);
            for (const state of this.chart.order)
                if (state.kind === "history" && state.history !== null)
                    this.output.push(`  history ${state.name} = ${names(state.history)}`);
            for (const reservation of this.sortedReservations())
                this.output.push(
                    reservation.kind === "timer"
                        ? `  timer ${reservation.due} after(${reservation.transition.delay})@${reservation.transition.source.name}`
                        : `  send ${reservation.due} ${reservation.event.name} ${reservation.event.value}`,
                );
        }
    }
    statistics(): void {
        this.output.push(
            `end t=${this.time} macrosteps=${this.macrosteps} microsteps=${this.microsteps}`,
        );
        for (const state of this.chart.order)
            if (state.kind !== "history")
                this.output.push(
                    `  ${state.name} entered=${state.entered} taken=${state.taken} time=${state.dwell + (this.configuration.has(state) ? this.time - state.enteredAt : 0)}`,
                );
    }
}
const input = fs.readFileSync(0, "utf8").split(/\r?\n/);
const output: string[] = [];
let at = 1;
for (let chartNumber = 0; chartNumber < Number(input[0]); chartNumber++) {
    const name = input[at++].slice(6);
    const definitions: SourceLine[] = [];
    const script: string[] = [];
    while (input[at] !== "RUN") {
        definitions.push({ text: input[at], line: at + 1 });
        at++;
    }
    at++;
    while (input[at] !== "END") script.push(input[at++]);
    at++;
    output.push("chart " + name);
    const chart = build(definitions);
    if (chart.errors.size) {
        for (const [line, error] of [...chart.errors].sort((a, b) => a[0] - b[0]))
            output.push(`error line ${line}: ${error}`);
        continue;
    }
    warnings(chart, output);
    const machine = new Machine(chart, output);
    machine.macrostep({ kind: "start" });
    for (const line of script) machine.script(line);
    machine.statistics();
}
process.stdout.write(output.join("\n") + "\n");
