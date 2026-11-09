import * as fs from "node:fs";

type CircuitElement = {
    name: string;
    terminals: string[];
    reference: string | null;
    value: Rational;
};
type Equations = {
    nodes: string[];
    sources: CircuitElement[];
    count: number;
    nodeIndex: Map<string, number>;
    sourceIndex: Map<string, number>;
    a: Rational[][];
    b: Rational[];
};
type ResistanceEdge = { x: string; y: string; value: Rational };
type Resistor = { name: string; a: string; b: string; value: Rational };

class Problem extends Error {}
function fail(message: string): never {
    throw new Problem(message);
}
function gcd(a: bigint, b: bigint): bigint {
    while (b !== 0n) [a, b] = [b, a % b];
    return a;
}
class Rational {
    readonly n: bigint;
    readonly d: bigint;
    constructor(n: bigint, d = 1n) {
        if (d < 0n) {
            n = -n;
            d = -d;
        }
        const g = gcd(n < 0n ? -n : n, d);
        this.n = n / g;
        this.d = d / g;
    }
    add(b: Rational): Rational {
        return new Rational(this.n * b.d + b.n * this.d, this.d * b.d);
    }
    sub(b: Rational): Rational {
        return new Rational(this.n * b.d - b.n * this.d, this.d * b.d);
    }
    mul(b: Rational): Rational {
        return new Rational(this.n * b.n, this.d * b.d);
    }
    div(b: Rational): Rational {
        return new Rational(this.n * b.d, this.d * b.n);
    }
    neg(): Rational {
        return new Rational(-this.n, this.d);
    }
    compare(b: Rational): number {
        const difference = this.n * b.d - b.n * this.d;
        return difference < 0n ? -1 : difference > 0n ? 1 : 0;
    }
    get zero(): boolean {
        return this.n === 0n;
    }
    get positive(): boolean {
        return this.n > 0n;
    }
    toString(): string {
        return this.d === 1n ? String(this.n) : `${this.n}/${this.d}`;
    }
    value(): string {
        const scaled = ((this.n < 0n ? -this.n : this.n) * 1000000n) / this.d;
        return `${this} (${this.n < 0n ? "-" : ""}${scaled / 1000000n}.${String(scaled % 1000000n).padStart(6, "0")})`;
    }
}
const ZERO = new Rational(0n),
    ONE = new Rational(1n);
function readNumber(word: string): Rational | null {
    let text = word,
        multiplier = ONE;
    const multipliers: Array<[string, Rational]> = [
        ["meg", new Rational(1000000n)],
        ["k", new Rational(1000n)],
        ["m", new Rational(1n, 1000n)],
        ["u", new Rational(1n, 1000000n)],
    ];
    for (const [suffix, value] of multipliers) {
        if (text.endsWith(suffix)) {
            text = text.slice(0, -suffix.length);
            multiplier = value;
            break;
        }
    }
    const negative = text.startsWith("-");
    if (negative) text = text.slice(1);
    if (!/^[0-9]+(?:\.[0-9]+|\/[0-9]+)?$/.test(text)) return null;
    let numerator: bigint, denominator: bigint;
    if (text.includes("/")) {
        const parts = text.split("/");
        numerator = BigInt(parts[0]);
        denominator = BigInt(parts[1]);
        if (denominator === 0n) return null;
    } else if (text.includes(".")) {
        const parts = text.split(".");
        numerator = BigInt(parts.join(""));
        denominator = 10n ** BigInt(parts[1].length);
    } else {
        numerator = BigInt(text);
        denominator = 1n;
    }
    return new Rational(negative ? -numerator : numerator, denominator).mul(multiplier);
}
function numberCheck(word: string): Rational {
    const value = readNumber(word);
    if (value === null) fail("invalid value " + word);
    return value;
}
function validNode(name: string): boolean {
    return name === "0" || /^[a-z][a-z0-9]{0,7}$/.test(name);
}
function voltageType(element: CircuitElement): boolean {
    return "VEH".includes(element.name[0]);
}
function independent(element: CircuitElement): boolean {
    return "VI".includes(element.name[0]);
}
function zeros(count: number): Rational[] {
    return Array<Rational>(count).fill(ZERO);
}
function matrix(count: number): Rational[][] {
    return Array.from({ length: count }, () => zeros(count));
}
function solve(a: Rational[][], b: Rational[]): Rational[] | null {
    const n = a.length,
        rows = a.map((row, i) => [...row, b[i]]);
    for (let k = 0; k < n; k++) {
        let r = k;
        while (r < n && rows[r][k].zero) r++;
        if (r === n) return null;
        [rows[k], rows[r]] = [rows[r], rows[k]];
        const pivot = rows[k][k];
        for (let j = 0; j <= n; j++) rows[k][j] = rows[k][j].div(pivot);
        for (let i = 0; i < n; i++)
            if (i !== k && !rows[i][k].zero) {
                const factor = rows[i][k];
                for (let j = 0; j <= n; j++) rows[i][j] = rows[i][j].sub(factor.mul(rows[k][j]));
            }
    }
    return rows.map((row) => row[n]);
}
function reachable(start: string, edges: string[][]): Set<string> {
    const seen = new Set([start]),
        pending = [start];
    while (pending.length > 0) {
        const node = pending.pop()!;
        for (const [a, b] of edges) {
            const next = a === node ? b : b === node ? a : null;
            if (next !== null && !seen.has(next)) {
                seen.add(next);
                pending.push(next);
            }
        }
    }
    return seen;
}
class Groups {
    readonly parent: Map<string, string>;
    constructor(nodes: string[]) {
        this.parent = new Map<string, string>(nodes.map((node) => [node, node]));
    }
    find(node: string): string {
        const parent = this.parent.get(node)!;
        if (parent === node) return node;
        const root = this.find(parent);
        this.parent.set(node, root);
        return root;
    }
    join(a: string, b: string): void {
        a = this.find(a);
        b = this.find(b);
        if (a !== b) this.parent.set(a < b ? b : a, a < b ? a : b);
    }
}

class Circuit {
    elements: CircuitElement[] = [];
    nodes(includeGround = false): string[] {
        const names = new Set(this.elements.flatMap((element) => element.terminals));
        if (includeGround) names.add("0");
        return [...names].sort();
    }
    circuitNodes(): string[] {
        return this.nodes().filter((node) => node !== "0");
    }
    elementCheck(name: string): CircuitElement {
        const element = this.elements.find((element) => element.name === name);
        if (element === undefined) fail("unknown element " + name);
        return element;
    }
    nodeCheck(name: string): void {
        if (name !== "0" && !this.circuitNodes().includes(name)) fail("unknown node " + name);
    }
    add(words: string[]): void {
        const name = words[0],
            type = name[0];
        if (!"RVIEGFH".includes(type)) fail("unknown element type " + name);
        const expected = "EG".includes(type) ? 6 : "FH".includes(type) ? 5 : 4;
        if (words.length !== expected) fail("wrong field count for " + name);
        if (this.elements.some((element) => element.name === name))
            fail("duplicate element " + name);
        const terminals = words.slice(1, "EG".includes(type) ? 5 : 3);
        for (const node of terminals) if (!validNode(node)) fail("invalid node " + node);
        const reference = "FH".includes(type) ? words[3] : null;
        if (
            reference !== null &&
            !this.elements.some((element) => element.name === reference && element.name[0] === "V")
        )
            fail("unknown voltage source " + reference);
        const value = numberCheck(words[words.length - 1]);
        if (type === "R" && !value.positive) fail("nonpositive resistance " + name);
        this.elements.push({ name, terminals, reference, value });
    }
    floating(): string[] {
        const edges = this.elements
            .filter((element) => "RVEH".includes(element.name[0]))
            .map((element) => [element.terminals[0], element.terminals[1]]);
        const seen = reachable("0", edges);
        return this.circuitNodes().filter((node) => !seen.has(node));
    }
    loops(): string[] {
        const groups = new Groups(this.nodes(true)),
            result: string[] = [];
        for (const element of this.elements.filter(voltageType)) {
            const [a, b] = element.terminals;
            if (groups.find(a) === groups.find(b)) result.push(element.name);
            groups.join(a, b);
        }
        return result;
    }
    structure(): void {
        if (this.circuitNodes().length === 0) fail("no nodes");
        const floating = this.floating();
        if (floating.length > 0) fail("floating node " + floating[0]);
        const loops = this.loops();
        if (loops.length > 0) fail("voltage source loop at " + loops[0]);
    }
    equations(overrides = new Map<string, Rational>()): Equations {
        const nodes = this.circuitNodes(),
            sources = this.elements.filter(voltageType),
            count = nodes.length + sources.length;
        const nodeIndex = new Map<string, number>(nodes.map((node, i) => [node, i]));
        const sourceIndex = new Map<string, number>(
            sources.map((source, i) => [source.name, nodes.length + i]),
        );
        const a = matrix(count),
            b = zeros(count);
        const node = (name: string): number => (name === "0" ? -1 : nodeIndex.get(name)!);
        const source = (name: string | null): number => sourceIndex.get(name!)!;
        const stamp = (row: number, column: number, value: Rational): void => {
            if (row >= 0 && column >= 0) a[row][column] = a[row][column].add(value);
        };
        const rhs = (row: number, value: Rational): void => {
            if (row >= 0) b[row] = b[row].add(value);
        };
        for (const element of this.elements) {
            const [n1, n2, c1, c2] = element.terminals,
                type = element.name[0];
            const x = node(n1),
                y = node(n2),
                w = overrides.get(element.name) ?? element.value;
            if (type === "R") {
                const g = ONE.div(w);
                stamp(x, x, g);
                stamp(y, y, g);
                stamp(x, y, g.neg());
                stamp(y, x, g.neg());
            } else if (type === "I") {
                rhs(x, w.neg());
                rhs(y, w);
            } else if (type === "G") {
                stamp(x, node(c1), w);
                stamp(y, node(c2), w);
                stamp(x, node(c2), w.neg());
                stamp(y, node(c1), w.neg());
            } else if (type === "F") {
                stamp(x, source(element.reference), w);
                stamp(y, source(element.reference), w.neg());
            } else {
                const s = source(element.name);
                stamp(x, s, ONE);
                stamp(s, x, ONE);
                stamp(y, s, ONE.neg());
                stamp(s, y, ONE.neg());
                if (type === "V") rhs(s, w);
                else if (type === "E") {
                    stamp(s, node(c1), w.neg());
                    stamp(s, node(c2), w);
                } else stamp(s, source(element.reference), w.neg());
            }
        }
        return { nodes, sources, count, nodeIndex, sourceIndex, a, b };
    }
    potential(equations: Equations, solution: Rational[], name: string): Rational {
        return name === "0" ? ZERO : solution[equations.nodeIndex.get(name)!];
    }
    sourceCurrent(equations: Equations, solution: Rational[], name: string | null): Rational {
        return solution[equations.sourceIndex.get(name!)!];
    }
    current(equations: Equations, solution: Rational[], element: CircuitElement): Rational {
        const [n1, n2, c1, c2] = element.terminals,
            type = element.name[0];
        if (type === "R")
            return this.potential(equations, solution, n1)
                .sub(this.potential(equations, solution, n2))
                .div(element.value);
        if (type === "I") return element.value;
        if (type === "G")
            return element.value.mul(
                this.potential(equations, solution, c1).sub(
                    this.potential(equations, solution, c2),
                ),
            );
        if (type === "F")
            return element.value.mul(this.sourceCurrent(equations, solution, element.reference));
        return this.sourceCurrent(equations, solution, element.name);
    }
    injection(equations: Equations, a: string, b: string): Rational[] {
        const column = zeros(equations.count);
        if (a !== "0") {
            const i = equations.nodeIndex.get(a)!;
            column[i] = column[i].add(ONE);
        }
        if (b !== "0") {
            const i = equations.nodeIndex.get(b)!;
            column[i] = column[i].sub(ONE);
        }
        return solve(equations.a, column)!;
    }
    alone(equations: Equations, element: CircuitElement, unit: boolean): Rational[] {
        const column = zeros(equations.count),
            value = unit ? ONE : element.value;
        if (element.name[0] === "V") column[equations.sourceIndex.get(element.name)!] = value;
        else {
            const [a, b] = element.terminals;
            if (a !== "0") {
                const i = equations.nodeIndex.get(a)!;
                column[i] = column[i].sub(value);
            }
            if (b !== "0") {
                const i = equations.nodeIndex.get(b)!;
                column[i] = column[i].add(value);
            }
        }
        return solve(equations.a, column)!;
    }
    resistance(a: string, b: string): string[] {
        const groups = new Groups(this.nodes(true));
        for (const element of this.elements)
            if (element.name[0] === "V") groups.join(element.terminals[0], element.terminals[1]);
        a = groups.find(a);
        b = groups.find(b);
        if (a === b) return ["Req = " + ZERO.value()];
        const edges: ResistanceEdge[] = [];
        for (const element of this.elements)
            if (element.name[0] === "R") {
                const x = groups.find(element.terminals[0]),
                    y = groups.find(element.terminals[1]);
                if (x !== y) edges.push({ x, y, value: ONE.div(element.value) });
            }
        const seen = reachable(
            a,
            edges.map((edge) => [edge.x, edge.y]),
        );
        if (!seen.has(b)) return ["Req = INFINITE"];
        const nodes = [...seen].filter((node) => node !== b).sort(),
            indices = new Map(nodes.map((node, i) => [node, i]));
        const g = matrix(nodes.length),
            column = zeros(nodes.length);
        const stamp = (row: string, col: string, value: Rational): void => {
            if (row !== b && col !== b) {
                const i = indices.get(row)!,
                    j = indices.get(col)!;
                g[i][j] = g[i][j].add(value);
            }
        };
        for (const edge of edges)
            if (seen.has(edge.x)) {
                stamp(edge.x, edge.x, edge.value);
                stamp(edge.y, edge.y, edge.value);
                stamp(edge.x, edge.y, edge.value.neg());
                stamp(edge.y, edge.x, edge.value.neg());
            }
        column[indices.get(a)!] = ONE;
        return ["Req = " + solve(g, column)![indices.get(a)!].value()];
    }
    reduce(a: string, b: string): string[] {
        if (a === b) return ["Req = " + ZERO.value()];
        let list: Resistor[] = this.elements
            .filter((element) => element.name[0] === "R")
            .map((element) => ({
                name: element.name,
                a: element.terminals[0],
                b: element.terminals[1],
                value: element.value,
            }));
        const connected = reachable(
            a,
            list.map((element) => [element.a, element.b]),
        );
        if (!connected.has(b)) return ["Req = INFINITE"];
        list = list.filter((element) => connected.has(element.a));
        const output: string[] = [];
        let serial = 0;
        while (true) {
            let remove = list.findIndex((element) => element.a === element.b);
            if (remove >= 0) {
                output.push("remove " + list[remove].name);
                list.splice(remove, 1);
                continue;
            }
            const degree = new Map<string, number>();
            for (const element of list)
                for (const node of [element.a, element.b])
                    degree.set(node, (degree.get(node) ?? 0) + 1);
            const internal = [...degree.keys()].filter((node) => node !== a && node !== b).sort();
            const dangling = internal.find((node) => degree.get(node) === 1);
            if (dangling !== undefined) {
                remove = list.findIndex(
                    (element) => element.a === dangling || element.b === dangling,
                );
                output.push("remove " + list[remove].name);
                list.splice(remove, 1);
                continue;
            }
            let first = -1,
                second = -1,
                parallel = false;
            search: for (let i = 0; i < list.length; i++)
                for (let j = i + 1; j < list.length; j++) {
                    const x = list[i],
                        y = list[j];
                    if ((x.a === y.a && x.b === y.b) || (x.a === y.b && x.b === y.a)) {
                        first = i;
                        second = j;
                        parallel = true;
                        break search;
                    }
                }
            let center: string | null = null;
            if (!parallel) {
                center = internal.find((node) => degree.get(node) === 2) ?? null;
                if (center === null) break;
                const indices = list
                    .map((element, i) => (element.a === center || element.b === center ? i : -1))
                    .filter((i) => i >= 0);
                [first, second] = indices;
            }
            const x = list[first],
                y = list[second],
                name = "#" + ++serial;
            const value = parallel
                ? x.value.mul(y.value).div(x.value.add(y.value))
                : x.value.add(y.value);
            const left = parallel ? x.a : x.a === center ? x.b : x.a;
            const right = parallel ? x.b : y.a === center ? y.b : y.a;
            output.push(
                `${name} = ${x.name} ${parallel ? "||" : "+"} ${y.name} = ${value.value()}`,
            );
            list.splice(second, 1);
            list.splice(first, 1);
            list.push({ name, a: left, b: right, value });
        }
        output.push(
            list.length === 1
                ? "Req = " + list[0].value.value()
                : `not series-parallel: ${list.length} resistors remain`,
        );
        return output;
    }
    check(): string[] {
        const nodes = this.circuitNodes();
        if (nodes.length === 0) return ["no nodes"];
        const output: string[] = [];
        for (const node of nodes) {
            let degree = 0;
            for (const element of this.elements) {
                if (element.terminals[0] === node) degree++;
                if (element.terminals[1] === node) degree++;
            }
            if (degree < 2) output.push("dangling node " + node);
        }
        for (const node of this.floating()) output.push("floating node " + node);
        for (const name of this.loops()) output.push("voltage source loop at " + name);
        if (output.length === 0) {
            const eq = this.equations();
            if (solve(eq.a, eq.b) === null) output.push("singular matrix");
        }
        return output.length === 0 ? ["ok"] : output;
    }
    command(words: string[]): string[] {
        const command = words[0],
            args = words.slice(1);
        const counts = new Map<string, number>([
            [".OP", 0],
            [".CURRENT", 1],
            [".VOLTAGE", 2],
            [".POWER", 0],
            [".KCL", 1],
            [".THEVENIN", 2],
            [".NORTON", 2],
            [".MAXPOWER", 2],
            [".TF", 2],
            [".SENS", 1],
            [".ZPARAM", 4],
            [".SUPERPOSITION", 1],
            [".SWEEP", 5],
            [".MATRIX", 0],
            [".REQ", 2],
            [".REDUCE", 2],
            [".CHECK", 0],
            [".ALTER", 2],
            [".DELETE", 1],
            [".CLEAR", 0],
            [".NODES", 0],
            [".PRINT", 0],
        ]);
        if (!counts.has(command)) fail("unknown command " + command);
        if (args.length !== counts.get(command)) fail("wrong argument count for " + command);
        if (command === ".CLEAR") {
            const count = this.elements.length;
            this.elements = [];
            return [`cleared ${count} elements`];
        }
        if (command === ".DELETE") {
            const element = this.elementCheck(args[0]),
                user = this.elements.find((other) => other.reference === element.name);
            if (user !== undefined) fail(element.name + " is referenced by " + user.name);
            this.elements.splice(this.elements.indexOf(element), 1);
            return ["deleted " + element.name];
        }
        if (command === ".ALTER") {
            const element = this.elementCheck(args[0]),
                value = numberCheck(args[1]);
            if (element.name[0] === "R" && !value.positive)
                fail("nonpositive resistance " + element.name);
            const output = `altered ${element.name}: ${element.value} -> ${value}`;
            element.value = value;
            return [output];
        }
        if (command === ".NODES") {
            const nodes = this.nodes();
            return nodes.length === 0
                ? ["no nodes"]
                : nodes.map(
                      (node) =>
                          node +
                          ": " +
                          this.elements
                              .filter((element) => element.terminals.includes(node))
                              .map((element) => element.name)
                              .join(" "),
                  );
        }
        if (command === ".PRINT")
            return this.elements.length === 0
                ? ["empty netlist"]
                : this.elements.map((element) =>
                      [
                          element.name,
                          ...element.terminals,
                          ...(element.reference === null ? [] : [element.reference]),
                          String(element.value),
                      ].join(" "),
                  );
        if (command === ".CHECK") return this.check();
        if (command === ".SWEEP") {
            const element = this.elementCheck(args[0]);
            const from = numberCheck(args[1]),
                to = numberCheck(args[2]),
                step = numberCheck(args[3]);
            this.nodeCheck(args[4]);
            if (!step.positive) fail("invalid sweep step");
            if (from.compare(to) > 0) fail("invalid sweep range");
            const span = to.sub(from).div(step),
                count = span.n / span.d + 1n;
            if (count > 20n) fail("too many sweep points");
            if (element.name[0] === "R" && !from.positive)
                fail("nonpositive resistance " + element.name);
            this.structure();
            const output: string[] = [];
            for (let k = 0n; k < count; k++) {
                const value = from.add(step.mul(new Rational(k))),
                    eq = this.equations(new Map([[element.name, value]])),
                    solution = solve(eq.a, eq.b);
                output.push(
                    `${element.name} = ${value}: ${solution === null ? "singular matrix" : `V(${args[4]}) = ${this.potential(eq, solution, args[4]).value()}`}`,
                );
            }
            return output;
        }
        if (command === ".REQ" || command === ".REDUCE") {
            this.nodeCheck(args[0]);
            this.nodeCheck(args[1]);
            return command === ".REQ"
                ? this.resistance(args[0], args[1])
                : this.reduce(args[0], args[1]);
        }
        let selected: CircuitElement | null = null;
        if (command === ".CURRENT") selected = this.elementCheck(args[0]);
        else if (command === ".TF") {
            this.nodeCheck(args[0]);
            selected = this.elementCheck(args[1]);
            if (!independent(selected)) fail("not an independent source " + selected!.name);
        } else if (
            [
                ".VOLTAGE",
                ".KCL",
                ".THEVENIN",
                ".NORTON",
                ".MAXPOWER",
                ".SENS",
                ".ZPARAM",
                ".SUPERPOSITION",
            ].includes(command)
        ) {
            for (const node of args) this.nodeCheck(node);
        }
        this.structure();
        const eq = this.equations();
        if (command === ".MATRIX") {
            const labels = [...eq.nodes, ...eq.sources.map((element) => element.name)];
            return [
                "unknowns: " +
                    [
                        ...eq.nodes.map((node) => `V(${node})`),
                        ...eq.sources.map((element) => `I(${element.name})`),
                    ].join(" "),
                ...labels.map((label, i) => `${label}: ${eq.a[i].join(" ")} | ${eq.b[i]}`),
            ];
        }
        const solution = solve(eq.a, eq.b);
        if (solution === null) fail("singular matrix");
        const potential = (name: string, values: Rational[] = solution): Rational =>
            this.potential(eq, values, name);
        const output: string[] = [];
        if (command === ".OP") {
            for (const node of eq.nodes) output.push(`V(${node}) = ${potential(node).value()}`);
            for (const element of eq.sources)
                output.push(
                    `I(${element.name}) = ${this.sourceCurrent(eq, solution, element.name).value()}`,
                );
        } else if (command === ".CURRENT")
            output.push(`I(${selected!.name}) = ${this.current(eq, solution, selected!).value()}`);
        else if (command === ".VOLTAGE")
            output.push(
                `V(${args[0]},${args[1]}) = ${potential(args[0]).sub(potential(args[1])).value()}`,
            );
        else if (command === ".POWER") {
            let absorbed = ZERO,
                delivered = ZERO,
                total = ZERO;
            for (const element of this.elements) {
                const power = potential(element.terminals[0])
                    .sub(potential(element.terminals[1]))
                    .mul(this.current(eq, solution, element));
                output.push(`P(${element.name}) = ${power.value()}`);
                if (power.positive) absorbed = absorbed.add(power);
                else if (!power.zero) delivered = delivered.sub(power);
                total = total.add(power);
            }
            output.push(
                "absorbed = " + absorbed.value(),
                "delivered = " + delivered.value(),
                "total = " + total.value(),
            );
        } else if (command === ".KCL") {
            let sum = ZERO;
            for (const element of this.elements)
                if (element.terminals[0] === args[0] || element.terminals[1] === args[0]) {
                    const current =
                        element.terminals[0] === element.terminals[1]
                            ? ZERO
                            : element.terminals[0] === args[0]
                              ? this.current(eq, solution, element)
                              : this.current(eq, solution, element).neg();
                    output.push(`I(${element.name}) leaving ${args[0]} = ${current.value()}`);
                    sum = sum.add(current);
                }
            output.push("sum = " + sum.value());
        } else if ([".THEVENIN", ".NORTON", ".MAXPOWER"].includes(command)) {
            const voltage = potential(args[0]).sub(potential(args[1])),
                z = this.injection(eq, args[0], args[1]);
            const resistance = potential(args[0], z).sub(potential(args[1], z));
            if (command === ".THEVENIN")
                output.push("Vth = " + voltage.value(), "Rth = " + resistance.value());
            else if (command === ".NORTON") {
                if (resistance.zero) fail("zero thevenin resistance");
                output.push(
                    "In = " + voltage.div(resistance).value(),
                    "Rn = " + resistance.value(),
                );
            } else {
                if (!resistance.positive) fail("nonpositive thevenin resistance");
                output.push(
                    "RL = " + resistance.value(),
                    "Pmax = " + voltage.mul(voltage).div(new Rational(4n).mul(resistance)).value(),
                );
            }
        } else if (command === ".TF") {
            const z = this.alone(eq, selected!, true);
            output.push("gain = " + potential(args[0], z).value());
            if (selected!.name[0] === "V") {
                const current = this.sourceCurrent(eq, z, selected!.name);
                output.push(
                    "input resistance = " +
                        (current.zero ? "INFINITE" : ONE.neg().div(current).value()),
                );
            } else
                output.push(
                    "input resistance = " +
                        potential(selected!.terminals[1], z)
                            .sub(potential(selected!.terminals[0], z))
                            .value(),
                );
            output.push(
                "output resistance = " +
                    potential(args[0], this.injection(eq, args[0], "0")).value(),
            );
        } else if (command === ".SENS") {
            for (const element of this.elements) {
                const column = zeros(eq.count),
                    [a, b, c, d] = element.terminals;
                const add = (node: string, value: Rational): void => {
                    if (node !== "0") {
                        const i = eq.nodeIndex.get(node)!;
                        column[i] = column[i].add(value);
                    }
                };
                const type = element.name[0];
                if (type === "R") {
                    const t = this.current(eq, solution, element).div(element.value);
                    add(a, t);
                    add(b, t.neg());
                } else if (type === "I") {
                    add(a, ONE.neg());
                    add(b, ONE);
                } else if (type === "G" || type === "F") {
                    const t =
                        type === "G"
                            ? potential(c).sub(potential(d))
                            : this.sourceCurrent(eq, solution, element.reference);
                    add(a, t.neg());
                    add(b, t);
                } else
                    column[eq.sourceIndex.get(element.name)!] =
                        type === "V"
                            ? ONE
                            : type === "E"
                              ? potential(c).sub(potential(d))
                              : this.sourceCurrent(eq, solution, element.reference);
                output.push(
                    `dV(${args[0]})/d${element.name} = ${potential(args[0], solve(eq.a, column)!).value()}`,
                );
            }
        } else if (command === ".ZPARAM") {
            const first = this.injection(eq, args[0], args[1]),
                second = this.injection(eq, args[2], args[3]);
            output.push(
                "z11 = " + potential(args[0], first).sub(potential(args[1], first)).value(),
                "z12 = " + potential(args[0], second).sub(potential(args[1], second)).value(),
                "z21 = " + potential(args[2], first).sub(potential(args[3], first)).value(),
                "z22 = " + potential(args[2], second).sub(potential(args[3], second)).value(),
            );
        } else if (command === ".SUPERPOSITION") {
            let total = ZERO;
            for (const element of this.elements.filter(independent)) {
                const value = potential(args[0], this.alone(eq, element, false));
                output.push(`${element.name}: V(${args[0]}) = ${value.value()}`);
                total = total.add(value);
            }
            output.push(`total: V(${args[0]}) = ${total.value()}`);
        }
        return output;
    }
}

const circuit = new Circuit(),
    output: string[] = [];
let lineNumber = 0;
for (const line of fs.readFileSync(0, "utf8").split(/\r?\n/)) {
    lineNumber++;
    if (line === ".END") break;
    if (line.startsWith("*")) continue;
    const words = line.split(" ");
    try {
        if (line.startsWith(".")) output.push(...circuit.command(words));
        else circuit.add(words);
    } catch (error) {
        if (!(error instanceof Problem)) throw error;
        output.push(`error: line ${lineNumber}: ${error.message}`);
    }
}
if (output.length > 0) process.stdout.write(output.join("\n") + "\n");
