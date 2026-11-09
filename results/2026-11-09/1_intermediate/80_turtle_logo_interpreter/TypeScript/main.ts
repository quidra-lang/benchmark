import * as fs from "node:fs";

interface Token {
    kind: string;
    text: string;
    line: number;
    sign: boolean;
}
interface SourceLine {
    text: string;
    line: number;
}
interface Procedure {
    name: string;
    parameters: string[];
    token: Token;
    tokens: Token[];
    body: Command[];
}
type Expression =
    | { kind: "number"; value: number; token: Token }
    | { kind: "variable"; name: string; token: Token }
    | { kind: "unary"; value: Expression; token: Token }
    | { kind: "binary"; left: Expression; right: Expression; token: Token }
    | { kind: "function"; inputs: Expression[]; token: Token }
    | { kind: "call"; inputs: Expression[]; token: Token };
interface QuotedWord {
    kind: "quote";
    value: string;
}
interface CommandList {
    kind: "list";
    commands: Command[];
}
type PrintItem = Expression | QuotedWord;
type Input = Expression | QuotedWord | CommandList;
interface Command {
    token: Token;
    name: string;
    inputs: Input[];
}
interface Environment {
    variables: Map<string, number>;
    test: boolean | null;
}
interface Flow {
    value: number | null;
}
interface Extent {
    x1: number;
    y1: number;
    x2: number;
    y2: number;
}

class LogoError extends Error {
    line: number;
    constructor(line: number, reason: string) {
        super(reason);
        this.line = line;
    }
}
function fail(token: Token, reason: string): never {
    throw new LogoError(token.line, reason);
}
const commandInputs = new Map(
    Object.entries({
        FD: "E",
        FORWARD: "E",
        BK: "E",
        BACK: "E",
        RT: "E",
        RIGHT: "E",
        LT: "E",
        LEFT: "E",
        SETH: "E",
        SETHEADING: "E",
        PU: "",
        PENUP: "",
        PD: "",
        PENDOWN: "",
        PE: "",
        PENERASE: "",
        SETPEN: "E",
        SETXY: "EE",
        SETX: "E",
        SETY: "E",
        HOME: "",
        CS: "",
        CLEARSCREEN: "",
        CLEAN: "",
        FILL: "",
        LABEL: "P",
        SNAPSHOT: "",
        REPEAT: "EL",
        FOR: "QEEL",
        WHILE: "EL",
        IF: "EL",
        IFELSE: "ELL",
        TEST: "E",
        IFTRUE: "L",
        IFT: "L",
        IFFALSE: "L",
        IFF: "L",
        STOP: "",
        OUTPUT: "E",
        OP: "E",
        MAKE: "QE",
        LOCAL: "Q",
        LOCALMAKE: "QE",
        TRACE: "Q",
        UNTRACE: "Q",
        SEED: "E",
        PRINT: "P",
        PR: "P",
    }),
);
const functionInputs = new Map(
    Object.entries({
        XCOR: 0,
        YCOR: 0,
        HEADING: 0,
        REPCOUNT: 0,
        RANDOM: 1,
        ABS: 1,
        NOT: 1,
        AND: 2,
        OR: 2,
        MAX: 2,
        MIN: 2,
    }),
);
const aliases = new Map(
    Object.entries({
        FORWARD: "FD",
        BACK: "BK",
        RIGHT: "RT",
        LEFT: "LT",
        SETHEADING: "SETH",
        PENUP: "PU",
        PENDOWN: "PD",
        PENERASE: "PE",
        CLEARSCREEN: "CS",
        IFT: "IFTRUE",
        IFF: "IFFALSE",
        OP: "OUTPUT",
        PR: "PRINT",
    }),
);
const primitives = new Set([...commandInputs.keys(), ...functionInputs.keys(), "TO", "END", "MOD"]);
const directions = [
    [0, 1],
    [1, 1],
    [1, 0],
    [1, -1],
    [0, -1],
    [-1, -1],
    [-1, 0],
    [-1, 1],
];
function lex(source: string, line: number): Token[] {
    const text = source.split(";")[0].toUpperCase();
    const tokens: Token[] = [];
    for (let i = 0; i < text.length;) {
        if (text[i] === " ") {
            i++;
            continue;
        }
        const start = i,
            first = text[i];
        if ("[]()+-*/=<>".includes(first)) {
            i++;
            if (
                (first === "<" && ["=", ">"].includes(text[i])) ||
                (first === ">" && text[i] === "=")
            )
                i++;
            tokens.push({
                kind: "symbol",
                text: text.slice(start, i),
                line,
                sign:
                    first === "-" &&
                    (start === 0 || " [(".includes(text[start - 1])) &&
                    i < text.length &&
                    text[i] !== " ",
            });
        } else {
            while (i < text.length && !" []()+-*/=<>".includes(text[i])) i++;
            const word = text.slice(start, i);
            let kind: string;
            if (/^[0-9]+$/.test(word)) kind = "number";
            else if (/^:[A-Z][A-Z0-9_]*$/.test(word)) kind = "variable";
            else if (/^"[A-Z][A-Z0-9_]*$/.test(word)) kind = "quote";
            else if (/^[A-Z][A-Z0-9_]*$/.test(word)) kind = "word";
            else throw new LogoError(line, `bad token '${word}'`);
            tokens.push({ kind, text: word, line, sign: false });
        }
    }
    return tokens;
}
function extract(lines: SourceLine[]): { procedures: Map<string, Procedure>; top: Token[] } {
    const procedures = new Map<string, Procedure>();
    const top: Token[] = [];
    let current: Procedure | null = null;
    for (const source of lines) {
        const tokens = lex(source.text, source.line);
        if (!tokens.length) continue;
        const first = tokens[0];
        if (first.kind === "word" && first.text === "TO") {
            if (current !== null) fail(first, "TO inside definition of " + current.name);
            if (tokens.length < 2 || tokens[1].kind !== "word") fail(first, "bad procedure header");
            const name = tokens[1].text;
            if (primitives.has(name)) fail(first, name + " is a primitive");
            if (procedures.has(name)) fail(first, name + " is already defined");
            const parameters: string[] = [];
            for (const token of tokens.slice(2)) {
                if (token.kind !== "variable") fail(first, "bad procedure header");
                if (parameters.includes(token.text.slice(1)))
                    fail(first, "duplicate input " + token.text);
                parameters.push(token.text.slice(1));
            }
            current = { name, parameters, token: first, tokens: [], body: [] };
            procedures.set(name, current);
        } else if (tokens.length === 1 && first.kind === "word" && first.text === "END") {
            if (current === null) fail(first, "END without TO");
            current = null;
        } else (current === null ? top : current.tokens).push(...tokens);
    }
    if (current !== null) fail(current.token, "missing END for " + current.name);
    return { procedures, top };
}
class Parser {
    tokens: Token[];
    procedures: Map<string, Procedure>;
    inside: boolean;
    at: number;
    constructor(tokens: Token[], procedures: Map<string, Procedure>, inside: boolean) {
        this.tokens = tokens;
        this.procedures = procedures;
        this.inside = inside;
        this.at = 0;
    }
    peek(): Token | undefined {
        return this.tokens[this.at];
    }
    unknown(token: Token): boolean {
        return (
            token.kind === "word" && !primitives.has(token.text) && !this.procedures.has(token.text)
        );
    }
    inputToken(owner: Token): Token {
        const token = this.peek();
        if (token === undefined || token.text === "]" || token.text === ")")
            fail(owner, "not enough inputs to " + owner.text);
        if (this.unknown(token)) fail(token, "I don't know how to " + token.text);
        return token;
    }
    input(kind: string, owner: Token): Input {
        const token = this.inputToken(owner);
        if (kind === "L") {
            if (token.text !== "[")
                fail(token, `${owner.text} doesn't like ${token.text} as input`);
            this.at++;
            const commands: Command[] = [];
            while (this.peek() !== undefined && this.peek()!.text !== "]")
                commands.push(this.command());
            if (this.peek() === undefined) fail(token, "missing ]");
            this.at++;
            return { kind: "list", commands };
        }
        if (kind === "Q" || (kind === "P" && token.kind === "quote")) {
            if (token.kind !== "quote")
                fail(token, `${owner.text} doesn't like ${token.text} as input`);
            this.at++;
            return { kind: "quote", value: token.text.slice(1) };
        }
        return this.expression(owner);
    }
    expression(owner: Token): Expression {
        return this.binary(owner, 0);
    }
    binary(owner: Token, level: number): Expression {
        if (level === 3) return this.term(owner);
        let left = this.binary(owner, level + 1);
        const operators =
            level === 0
                ? ["=", "<>", "<", ">", "<=", ">="]
                : level === 1
                  ? ["+", "-"]
                  : ["*", "/", "MOD"];
        while (
            this.peek() !== undefined &&
            operators.includes(this.peek()!.text) &&
            !this.peek()!.sign
        ) {
            const token = this.tokens[this.at++],
                right = this.binary(token, level + 1);
            left = { kind: "binary", token, left, right };
        }
        return left;
    }
    term(owner: Token): Expression {
        const token = this.inputToken(owner);
        this.at++;
        if (token.kind === "number") return { kind: "number", value: Number(token.text), token };
        if (token.kind === "variable")
            return { kind: "variable", name: token.text.slice(1), token };
        if (token.text === "-") return { kind: "unary", value: this.term(token), token };
        if (token.text === "(") {
            const value = this.expression(token);
            if (this.peek() === undefined || this.peek()!.text !== ")") fail(token, "missing )");
            this.at++;
            return value;
        }
        if (
            token.kind === "word" &&
            (functionInputs.has(token.text) || this.procedures.has(token.text))
        ) {
            const count =
                functionInputs.get(token.text) ??
                this.procedures.get(token.text)!.parameters.length;
            const inputs = Array.from({ length: count }, () => this.expression(token));
            if (functionInputs.has(token.text)) return { kind: "function", token, inputs };
            return { kind: "call", token, inputs };
        }
        fail(token, `${owner.text} doesn't like ${token.text} as input`);
    }
    command(): Command {
        const token = this.tokens[this.at++];
        if (token.text === "]") fail(token, "unexpected ]");
        const next = this.peek();
        if (
            token.text === "(" &&
            next !== undefined &&
            next.kind === "word" &&
            ["PRINT", "PR"].includes(next.text)
        ) {
            this.at++;
            const inputs: PrintItem[] = [];
            while (this.peek() === undefined || this.peek()!.text !== ")") {
                if (this.peek() === undefined || this.peek()!.text === "]")
                    fail(token, "missing )");
                inputs.push(this.input("P", next) as PrintItem);
            }
            this.at++;
            return { token: next, name: "MULTIPRINT", inputs };
        }
        if (token.kind === "word" && ["TO", "END"].includes(token.text))
            fail(token, "misplaced " + token.text);
        if (token.kind === "word" && commandInputs.has(token.text)) {
            if (!this.inside && ["STOP", "OUTPUT", "OP", "LOCAL", "LOCALMAKE"].includes(token.text))
                fail(token, "can only use " + token.text + " inside a procedure");
            const inputs = [...commandInputs.get(token.text)!].map((kind) =>
                this.input(kind, token),
            );
            if (
                ["TRACE", "UNTRACE"].includes(token.text) &&
                !this.procedures.has((inputs[0] as QuotedWord).value)
            )
                fail(
                    this.tokens[this.at - 1],
                    "I don't know how to " + (inputs[0] as QuotedWord).value,
                );
            return { token, name: aliases.get(token.text) ?? token.text, inputs };
        }
        if (token.kind === "word" && this.procedures.has(token.text)) {
            return {
                token,
                name: "CALL",
                inputs: Array.from(
                    { length: this.procedures.get(token.text)!.parameters.length },
                    () => this.expression(token),
                ),
            };
        }
        if (this.unknown(token)) fail(token, "I don't know how to " + token.text);
        fail(token, "you don't say what to do with " + token.text);
    }
    sequence(): Command[] {
        const commands: Command[] = [];
        while (this.peek() !== undefined) commands.push(this.command());
        return commands;
    }
}
class Turtle {
    procedures: Map<string, Procedure>;
    output: string[];
    x: number;
    y: number;
    heading: number;
    pen: string;
    character: string;
    canvas: Map<string, string>;
    environments: Environment[];
    active: string[];
    repetitions: number[];
    traced: Set<string>;
    random: number;
    constructor(procedures: Map<string, Procedure>, output: string[]) {
        this.procedures = procedures;
        this.output = output;
        this.x = 0;
        this.y = 0;
        this.heading = 0;
        this.pen = "DOWN";
        this.character = "*";
        this.canvas = new Map();
        this.environments = [{ variables: new Map(), test: null }];
        this.active = [];
        this.repetitions = [];
        this.traced = new Set();
        this.random = 1;
    }
    current(): Environment {
        return this.environments.at(-1)!;
    }
    make(name: string, value: number): void {
        for (let i = this.environments.length - 1; i > 0; i--)
            if (this.environments[i].variables.has(name)) {
                this.environments[i].variables.set(name, value);
                return;
            }
        this.environments[0].variables.set(name, value);
    }
    key(x: number, y: number): string {
        return x + "," + y;
    }
    apply(x: number, y: number): void {
        const key = this.key(x, y);
        if (this.pen === "DOWN") this.canvas.set(key, this.character);
        else if (this.pen === "ERASE") this.canvas.delete(key);
    }
    move(x: number, y: number): void {
        const x0 = this.x,
            y0 = this.y,
            dx = x - x0,
            dy = y - y0,
            steps = Math.max(Math.abs(dx), Math.abs(dy));
        if (!steps) this.apply(x0, y0);
        else
            for (let i = 0; i <= steps; i++)
                this.apply(
                    x0 + Math.floor((2 * i * dx + steps) / (2 * steps)),
                    y0 + Math.floor((2 * i * dy + steps) / (2 * steps)),
                );
        this.x = x;
        this.y = y;
    }
    extent(): Extent {
        let x1 = Infinity,
            y1 = Infinity,
            x2 = -Infinity,
            y2 = -Infinity;
        for (const key of this.canvas.keys()) {
            const [x, y] = key.split(",").map(Number);
            x1 = Math.min(x1, x);
            y1 = Math.min(y1, y);
            x2 = Math.max(x2, x);
            y2 = Math.max(y2, y);
        }
        return { x1, y1, x2, y2 };
    }
    picture(): void {
        if (!this.canvas.size) {
            this.output.push("CANVAS 0 0 0");
            return;
        }
        const { x1, y1, x2, y2 } = this.extent();
        this.output.push(`CANVAS ${x2 - x1 + 1} ${y2 - y1 + 1} ${this.canvas.size}`);
        for (let y = y2; y >= y1; y--) {
            let row = "";
            for (let x = x1; x <= x2; x++) row += this.canvas.get(this.key(x, y)) ?? " ";
            this.output.push(row.replace(/ +$/, ""));
        }
    }
    fill(): void {
        if (!this.canvas.size || this.canvas.has(this.key(this.x, this.y))) return;
        const { x1, y1, x2, y2 } = this.extent();
        if (this.x < x1 || this.x > x2 || this.y < y1 || this.y > y2) return;
        const queue = [[this.x, this.y]];
        this.canvas.set(this.key(this.x, this.y), this.character);
        for (let i = 0; i < queue.length; i++) {
            const [x, y] = queue[i];
            for (const [a, b] of [
                [x - 1, y],
                [x + 1, y],
                [x, y - 1],
                [x, y + 1],
            ])
                if (a >= x1 && a <= x2 && b >= y1 && b <= y2 && !this.canvas.has(this.key(a, b))) {
                    this.canvas.set(this.key(a, b), this.character);
                    queue.push([a, b]);
                }
        }
    }
    call(token: Token, inputs: Expression[]): number | null {
        const values = inputs.map((input) => this.evaluate(input));
        if (this.active.length >= 100) fail(token, "recursion too deep");
        const traced = this.traced.has(token.text),
            indent = " ".repeat(2 * this.active.length),
            procedure = this.procedures.get(token.text)!;
        if (traced)
            this.output.push(
                indent + "( " + token.text + (values.length ? " " + values.join(" ") : "") + " )",
            );
        this.active.push(token.text);
        this.environments.push({
            variables: new Map(procedure.parameters.map((name, i) => [name, values[i]])),
            test: null,
        });
        const result = this.sequence(procedure.body);
        this.environments.pop();
        this.active.pop();
        const value = result === null ? null : result.value;
        if (traced)
            this.output.push(
                indent + token.text + (value === null ? " stops" : " outputs " + value),
            );
        return value;
    }
    evaluate(expression: Expression): number {
        const token = expression.token;
        if (expression.kind === "number") return expression.value;
        if (expression.kind === "variable") {
            for (let i = this.environments.length - 1; i >= 0; i--)
                if (this.environments[i].variables.has(expression.name))
                    return this.environments[i].variables.get(expression.name)!;
            fail(token, expression.name + " has no value");
        }
        if (expression.kind === "unary") return -this.evaluate(expression.value);
        if (expression.kind === "binary") {
            const a = this.evaluate(expression.left),
                b = this.evaluate(expression.right);
            if ((token.text === "/" || token.text === "MOD") && b === 0)
                fail(token, token.text + " doesn't like 0 as input");
            switch (token.text) {
                case "+":
                    return a + b;
                case "-":
                    return a - b;
                case "*":
                    return a * b;
                case "/":
                    return Math.trunc(a / b);
                case "MOD":
                    return a % b;
                case "=":
                    return Number(a === b);
                case "<>":
                    return Number(a !== b);
                case "<":
                    return Number(a < b);
                case ">":
                    return Number(a > b);
                case "<=":
                    return Number(a <= b);
                default:
                    return Number(a >= b);
            }
        }
        if (expression.kind === "call") {
            const value = this.call(token, expression.inputs);
            if (value === null) fail(token, token.text + " did not output");
            return value;
        }
        const values = expression.inputs.map((input) => this.evaluate(input)),
            a = values[0],
            b = values[1];
        switch (token.text) {
            case "XCOR":
                return this.x;
            case "YCOR":
                return this.y;
            case "HEADING":
                return this.heading;
            case "REPCOUNT":
                if (!this.repetitions.length) fail(token, "REPCOUNT outside REPEAT");
                return this.repetitions.at(-1)!;
            case "RANDOM":
                if (a < 1) fail(token, `RANDOM doesn't like ${a} as input`);
                this.random = (48271 * this.random) % 2147483647;
                return this.random % a;
            case "ABS":
                return Math.abs(a);
            case "NOT":
                return Number(a === 0);
            case "AND":
                return Number(a !== 0 && b !== 0);
            case "OR":
                return Number(a !== 0 || b !== 0);
            case "MAX":
                return Math.max(a, b);
            default:
                return Math.min(a, b);
        }
    }
    item(input: PrintItem): string {
        return input.kind === "quote" ? input.value : String(this.evaluate(input));
    }
    sequence(commands: Command[]): Flow | null {
        for (const command of commands) {
            const result = this.command(command);
            if (result !== null) return result;
        }
        return null;
    }
    command(command: Command): Flow | null {
        const { name, token, inputs } = command;
        if (name === "CALL") {
            const value = this.call(token, inputs as Expression[]);
            if (value !== null) fail(token, "you don't say what to do with " + value);
            return null;
        }
        if (name === "PRINT" || name === "MULTIPRINT") {
            const values = inputs.map((input) => this.item(input as PrintItem));
            this.output.push(values.join(" "));
            return null;
        }
        if (name === "LABEL") {
            const text = this.item(inputs[0] as PrintItem),
                [dx, dy] = directions[this.heading / 45];
            for (let i = 0; i < text.length; i++)
                this.canvas.set(this.key(this.x + i * dx, this.y + i * dy), text[i]);
            return null;
        }
        if (name === "WHILE") {
            while (this.evaluate(inputs[0] as Expression) !== 0) {
                const result = this.sequence((inputs[1] as CommandList).commands);
                if (result !== null) return result;
            }
            return null;
        }
        const values = inputs.map((input) =>
            input.kind === "quote"
                ? input.value
                : input.kind === "list"
                  ? input.commands
                  : this.evaluate(input),
        );
        const a = values[0] as number,
            b = values[1] as number;
        switch (name) {
            case "FD":
            case "BK": {
                const amount = name === "BK" ? -a : a,
                    [dx, dy] = directions[this.heading / 45],
                    sign = amount < 0 ? -1 : 1;
                this.apply(this.x, this.y);
                for (let i = 0; i < Math.abs(amount); i++) {
                    this.x += sign * dx;
                    this.y += sign * dy;
                    this.apply(this.x, this.y);
                }
                break;
            }
            case "RT":
            case "LT":
            case "SETH":
                if (a % 45 !== 0) fail(token, `${token.text} doesn't like ${a} as input`);
                this.heading =
                    (((name === "SETH" ? a : this.heading + (name === "LT" ? -a : a)) % 360) +
                        360) %
                    360;
                break;
            case "PU":
                this.pen = "UP";
                break;
            case "PD":
                this.pen = "DOWN";
                break;
            case "PE":
                this.pen = "ERASE";
                break;
            case "SETPEN":
                if (a < 33 || a > 126) fail(token, `SETPEN doesn't like ${a} as input`);
                this.character = String.fromCharCode(a);
                break;
            case "SETXY":
                this.move(a, b);
                break;
            case "SETX":
                this.move(a, this.y);
                break;
            case "SETY":
                this.move(this.x, a);
                break;
            case "HOME":
                this.move(0, 0);
                this.heading = 0;
                break;
            case "CS":
                this.canvas.clear();
                this.x = 0;
                this.y = 0;
                this.heading = 0;
                break;
            case "CLEAN":
                this.canvas.clear();
                break;
            case "FILL":
                this.fill();
                break;
            case "SNAPSHOT":
                this.picture();
                break;
            case "MAKE":
                this.make(values[0] as string, b);
                break;
            case "LOCAL":
                this.current().variables.set(values[0] as string, 0);
                break;
            case "LOCALMAKE":
                this.current().variables.set(values[0] as string, b);
                break;
            case "TRACE":
                this.traced.add(values[0] as string);
                break;
            case "UNTRACE":
                this.traced.delete(values[0] as string);
                break;
            case "SEED":
                if (a < 1) fail(token, `SEED doesn't like ${a} as input`);
                this.random = a;
                break;
            case "STOP":
                return { value: null };
            case "OUTPUT":
                return { value: a };
            case "REPEAT":
                if ((values[1] as Command[]).length === 0) break;
                for (let k = 1; k <= a; k++) {
                    this.repetitions.push(k);
                    let result: Flow | null = null;
                    try {
                        result = this.sequence(values[1] as Command[]);
                    } finally {
                        this.repetitions.pop();
                    }
                    if (result !== null) return result;
                }
                break;
            case "FOR": {
                const finish = values[2] as number,
                    step = b <= finish ? 1 : -1;
                if ((values[3] as Command[]).length === 0) {
                    this.make(values[0] as string, finish);
                    break;
                }
                for (let value = b; ; value += step) {
                    this.make(values[0] as string, value);
                    const result = this.sequence(values[3] as Command[]);
                    if (result !== null) return result;
                    if (value === finish) break;
                }
                break;
            }
            case "IF":
                if (a !== 0) return this.sequence(values[1] as Command[]);
                break;
            case "IFELSE":
                return this.sequence((a !== 0 ? values[1] : values[2]) as Command[]);
            case "TEST":
                this.current().test = a !== 0;
                break;
            case "IFTRUE":
            case "IFFALSE":
                if (this.current().test === null) fail(token, token.text + " without TEST");
                if (this.current().test === (name === "IFTRUE"))
                    return this.sequence(values[0] as Command[]);
                break;
        }
        return null;
    }
}
function run(name: string, lines: SourceLine[], output: string[]): void {
    output.push("PROGRAM " + name);
    let turtle: Turtle | null = null;
    try {
        const { procedures, top } = extract(lines);
        for (const procedure of procedures.values())
            procedure.body = new Parser(procedure.tokens, procedures, true).sequence();
        const commands = new Parser(top, procedures, false).sequence();
        turtle = new Turtle(procedures, output);
        turtle.sequence(commands);
        output.push(
            `TURTLE ${turtle.x} ${turtle.y} ${turtle.heading} ${turtle.pen} ${turtle.character}`,
        );
        turtle.picture();
    } catch (error) {
        if (!(error instanceof LogoError)) throw error;
        output.push(`ERROR line ${error.line}: ${error.message}`);
        if (turtle !== null)
            for (let i = turtle.active.length - 1; i >= 0;) {
                const name = turtle.active[i];
                let count = 0;
                while (i >= 0 && turtle.active[i] === name) {
                    i--;
                    count++;
                }
                output.push("  in " + name + (count > 1 ? " x" + count : ""));
            }
    }
}
const input = fs.readFileSync(0, "utf8").split(/\r?\n/);
const output: string[] = [];
let name = "";
let source: SourceLine[] = [];
for (let i = 0; i < input.length; i++) {
    if (input[i] === "#EOF" || input[i].startsWith("#PROGRAM ")) {
        if (name !== "") run(name, source, output);
        if (input[i] === "#EOF") break;
        name = input[i].slice(9);
        source = [];
    } else source.push({ text: input[i], line: i + 1 });
}
process.stdout.write(output.join("\n") + "\n");
