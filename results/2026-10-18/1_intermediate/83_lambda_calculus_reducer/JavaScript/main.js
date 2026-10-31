const fs = require("node:fs");

class Problem extends Error {}
class TypeFailure extends Error {}
function fail(reason) {
    throw new Problem(reason);
}
function variable(name) {
    return { kind: "variable", name };
}
function abstraction(name, body) {
    return { kind: "abstraction", name, body };
}
function application(left, right) {
    return { kind: "application", left, right };
}
function constant(name) {
    return { kind: "constant", name };
}
function lex(argument, start, end) {
    const result = [];
    for (let i = 0; i < argument.length;) {
        const c = argument[i],
            column = start + i;
        if (c === " ") {
            i++;
            continue;
        }
        if ("\\.()=;".includes(c)) {
            result.push({ kind: c, text: c, column });
            i++;
            continue;
        }
        const begin = i;
        let kind;
        if (c >= "a" && c <= "z") {
            kind = "variable";
            while (i < argument.length && /[a-z0-9]/.test(argument[i])) i++;
        } else if (c >= "A" && c <= "Z") {
            kind = "macro";
            while (i < argument.length && /[A-Z0-9_]/.test(argument[i])) i++;
        } else if (c === "#" && i + 1 < argument.length && /[0-9]/.test(argument[i + 1])) {
            kind = "numeral";
            i += 2;
            while (i < argument.length && /[0-9]/.test(argument[i])) i++;
        } else fail(`column ${column}: unexpected character '${c}'`);
        result.push({ kind, text: argument.slice(begin, i), column });
    }
    result.push({ kind: "end", text: "", column: end });
    return result;
}
class Parser {
    constructor(tokens) {
        this.tokens = tokens;
        this.at = 0;
    }
    peek() {
        return this.tokens[this.at];
    }
    expect(kind) {
        const token = this.peek();
        if (token.kind !== kind)
            fail(
                `column ${token.column}: expected ${kind === "variable" ? "variable" : kind === "macro" ? "macro name" : "'" + kind + "'"}`,
            );
        this.at++;
        return token;
    }
    term() {
        const elements = [];
        while (["variable", "macro", "numeral", "("].includes(this.peek().kind))
            elements.push(this.atom());
        if (this.peek().kind === "\\") {
            this.at++;
            const names = [this.expect("variable").text];
            while (this.peek().kind === "variable") names.push(this.tokens[this.at++].text);
            this.expect(".");
            let body = this.term();
            for (let i = names.length - 1; i >= 0; i--) body = abstraction(names[i], body);
            elements.push(body);
        }
        if (!elements.length) fail(`column ${this.peek().column}: expected term`);
        return elements.slice(1).reduce(application, elements[0]);
    }
    atom() {
        const token = this.tokens[this.at++];
        if (token.kind === "variable") return variable(token.text);
        if (token.kind === "macro") return { kind: "macro", name: token.text };
        if (token.kind === "numeral")
            return { kind: "numeral", value: Number(token.text.slice(1)) };
        const term = this.term();
        this.expect(")");
        return term;
    }
    end() {
        const token = this.peek();
        if (token.kind !== "end") fail(`column ${token.column}: unexpected '${token.text}'`);
    }
}
const freeCache = new WeakMap();
function free(term) {
    if (freeCache.has(term)) return freeCache.get(term);
    let result;
    if (term.kind === "variable") result = new Set([term.name]);
    else if (term.kind === "abstraction") {
        result = new Set(free(term.body));
        result.delete(term.name);
    } else if (term.kind === "application")
        result = new Set([...free(term.left), ...free(term.right)]);
    else result = new Set();
    freeCache.set(term, result);
    return result;
}
function print(term, end = true) {
    if (term.kind === "variable" || term.kind === "macro" || term.kind === "constant")
        return term.name;
    if (term.kind === "numeral") return "#" + term.value;
    if (term.kind === "abstraction") {
        const names = [];
        let body = term;
        while (body.kind === "abstraction") {
            names.push(body.name);
            body = body.body;
        }
        const text = "\\" + names.join(" ") + ". " + print(body);
        return end ? text : "(" + text + ")";
    }
    const left =
        term.left.kind === "abstraction" ? "(" + print(term.left) + ")" : print(term.left, false);
    const right =
        term.right.kind === "application" ? "(" + print(term.right) + ")" : print(term.right, end);
    return left + " " + right;
}
function references(term) {
    return term.kind === "macro"
        ? [term.name]
        : term.kind === "abstraction"
          ? references(term.body)
          : term.kind === "application"
            ? [...references(term.left), ...references(term.right)]
            : [];
}
function substitute(term, name, replacement) {
    if (term.kind === "variable") return term.name === name ? replacement : term;
    if (term.kind === "application")
        return application(
            substitute(term.left, name, replacement),
            substitute(term.right, name, replacement),
        );
    if (term.name === name || !free(term.body).has(name)) return term;
    if (!free(replacement).has(term.name))
        return abstraction(term.name, substitute(term.body, name, replacement));
    const base = term.name.replace(/[0-9]+$/, "");
    let next,
        i = 1;
    do {
        next = base + i++;
    } while (free(replacement).has(next) || free(term.body).has(next));
    return abstraction(
        next,
        substitute(substitute(term.body, term.name, variable(next)), name, replacement),
    );
}
function toDB(term, environment = []) {
    if (term.kind === "variable") {
        const index = environment.indexOf(term.name);
        return index < 0 ? { kind: "free", name: term.name } : { kind: "index", value: index };
    }
    if (term.kind === "abstraction")
        return { kind: "abstraction", body: toDB(term.body, [term.name, ...environment]) };
    return {
        kind: "application",
        left: toDB(term.left, environment),
        right: toDB(term.right, environment),
    };
}
function printDB(term, end = true) {
    if (term.kind === "free") return term.name;
    if (term.kind === "index") return String(term.value);
    if (term.kind === "abstraction") {
        let body = term,
            prefix = "";
        while (body.kind === "abstraction") {
            prefix += "\\";
            body = body.body;
        }
        const text = prefix + printDB(body);
        return end ? text : "(" + text + ")";
    }
    const left =
        term.left.kind === "abstraction"
            ? "(" + printDB(term.left) + ")"
            : printDB(term.left, false);
    const right =
        term.right.kind === "application"
            ? "(" + printDB(term.right) + ")"
            : printDB(term.right, end);
    return left + " " + right;
}
function generatedName(index) {
    return String.fromCharCode(97 + (index % 26)) + (index >= 26 ? Math.floor(index / 26) : "");
}
function fromDB(term) {
    const names = new Set();
    function collect(node) {
        if (node.kind === "free") names.add(node.name);
        else if (node.kind === "abstraction") collect(node.body);
        else if (node.kind === "application") {
            collect(node.left);
            collect(node.right);
        }
    }
    collect(term);
    let counter = 0;
    function walk(node, environment) {
        if (node.kind === "free") return variable(node.name);
        if (node.kind === "index") return variable(environment[node.value]);
        if (node.kind === "abstraction") {
            let name;
            do {
                name = generatedName(counter++);
            } while (names.has(name));
            return abstraction(name, walk(node.body, [name, ...environment]));
        }
        return application(walk(node.left, environment), walk(node.right, environment));
    }
    return walk(term, []);
}
function canonical(term) {
    return print(fromDB(toDB(term)));
}
function etaBody(term) {
    const body = term.body;
    return body.kind === "application" &&
        body.right.kind === "variable" &&
        body.right.name === term.name &&
        !free(body.left).has(term.name)
        ? body.left
        : null;
}
function oneStep(term, strategy, eta) {
    if (term.kind === "variable") return null;
    if (term.kind === "abstraction") {
        if (strategy === "CBN" || strategy === "CBV") return null;
        const candidate = eta ? etaBody(term) : null;
        if (strategy === "NORMAL" && candidate !== null) return { term: candidate, kind: "eta" };
        const step = oneStep(term.body, strategy, eta);
        if (step !== null) return { term: abstraction(term.name, step.term), kind: step.kind };
        return candidate === null ? null : { term: candidate, kind: "eta" };
    }
    const early = strategy === "NORMAL" || strategy === "CBN";
    if (early && term.left.kind === "abstraction")
        return { term: substitute(term.left.body, term.left.name, term.right), kind: "beta" };
    const left = oneStep(term.left, strategy, eta);
    if (left !== null) return { term: application(left.term, term.right), kind: left.kind };
    if (strategy !== "CBN") {
        const right = oneStep(term.right, strategy, eta);
        if (right !== null) return { term: application(term.left, right.term), kind: right.kind };
    }
    if (
        !early &&
        term.left.kind === "abstraction" &&
        (strategy !== "CBV" || term.right.kind === "variable" || term.right.kind === "abstraction")
    )
        return { term: substitute(term.left.body, term.left.name, term.right), kind: "beta" };
    return null;
}
function abstractSki(name, term) {
    if (!free(term).has(name)) return application(constant("K"), term);
    if (term.kind === "variable") return constant("I");
    if (term.right.kind === "variable" && term.right.name === name && !free(term.left).has(name))
        return term.left;
    return application(
        application(constant("S"), abstractSki(name, term.left)),
        abstractSki(name, term.right),
    );
}
function toSki(term) {
    return term.kind === "variable"
        ? term
        : term.kind === "abstraction"
          ? abstractSki(term.name, toSki(term.body))
          : application(toSki(term.left), toSki(term.right));
}
function skiStep(term) {
    let head = term;
    const args = [];
    while (head.kind === "application") {
        args.unshift(head.right);
        head = head.left;
    }
    let result = null,
        used = 0;
    if (head.kind === "constant") {
        if (head.name === "I" && args.length >= 1) {
            result = args[0];
            used = 1;
        } else if (head.name === "K" && args.length >= 2) {
            result = args[0];
            used = 2;
        } else if (head.name === "S" && args.length >= 3) {
            result = application(application(args[0], args[2]), application(args[1], args[2]));
            used = 3;
        }
    }
    if (result !== null)
        return { term: args.slice(used).reduce(application, result), kind: head.name };
    for (let i = 0; i < args.length; i++) {
        const step = skiStep(args[i]);
        if (step !== null) {
            args[i] = step.term;
            return { term: args.reduce(application, head), kind: step.kind };
        }
    }
    return null;
}
function principalType(term) {
    const freeTypes = new Map();
    let next = 0;
    function fresh() {
        return { kind: "variable", id: next++, link: null };
    }
    function arrow(left, right) {
        return { kind: "arrow", left, right };
    }
    function prune(type) {
        if (type.kind === "variable" && type.link !== null) {
            type.link = prune(type.link);
            return type.link;
        }
        return type;
    }
    function occurs(variable, type) {
        type = prune(type);
        return (
            type === variable ||
            (type.kind === "arrow" && (occurs(variable, type.left) || occurs(variable, type.right)))
        );
    }
    function unify(a, b) {
        a = prune(a);
        b = prune(b);
        if (a === b) return;
        if (a.kind === "variable") {
            if (occurs(a, b)) throw new TypeFailure();
            a.link = b;
        } else if (b.kind === "variable") unify(b, a);
        else {
            unify(a.left, b.left);
            unify(a.right, b.right);
        }
    }
    function infer(node, bound) {
        if (node.kind === "variable") {
            if (bound.has(node.name)) return bound.get(node.name);
            if (!freeTypes.has(node.name)) freeTypes.set(node.name, fresh());
            return freeTypes.get(node.name);
        }
        if (node.kind === "abstraction") {
            const type = fresh(),
                environment = new Map(bound);
            environment.set(node.name, type);
            return arrow(type, infer(node.body, environment));
        }
        const left = infer(node.left, bound),
            right = infer(node.right, bound),
            result = fresh();
        unify(left, arrow(right, result));
        return result;
    }
    try {
        const type = infer(term, new Map()),
            names = new Map();
        function show(type) {
            type = prune(type);
            if (type.kind === "variable") {
                if (!names.has(type)) names.set(type, generatedName(names.size));
                return names.get(type);
            }
            const left = show(type.left);
            return (
                (prune(type.left).kind === "arrow" ? "(" + left + ")" : left) +
                " -> " +
                show(type.right)
            );
        }
        return show(type);
    } catch (error) {
        if (!(error instanceof TypeFailure)) throw error;
        return "not typable";
    }
}
function readChurch(term) {
    if (term.kind === "abstraction" && term.body.kind === "abstraction") {
        const outer = term.name,
            inner = term.body.name;
        let body = term.body.body,
            count = 0;
        while (
            body.kind === "application" &&
            body.left.kind === "variable" &&
            body.left.name === outer
        ) {
            count++;
            body = body.right;
        }
        if (body.kind === "variable" && body.name === inner) return String(count);
        if (term.body.body.kind === "variable" && term.body.body.name === outer) return "true";
    }
    if (
        term.kind === "abstraction" &&
        term.body.kind === "application" &&
        term.body.left.kind === "application" &&
        term.body.left.left.kind === "variable" &&
        term.body.left.left.name === term.name
    ) {
        const left = term.body.left.right,
            right = term.body.right;
        if (!free(left).has(term.name) && !free(right).has(term.name))
            return "(" + readChurch(left) + ", " + readChurch(right) + ")";
    }
    return canonical(term);
}
class Workbench {
    constructor() {
        this.macros = new Map();
        this.display = false;
        this.eta = false;
        this.limit = 10000;
        this.output = [];
        for (const [name, text] of [
            ["S", "\\x y z. x z (y z)"],
            ["K", "\\x y. x"],
            ["I", "\\x. x"],
        ])
            this.macros.set(name, new Parser(lex(text, 1, text.length + 1)).term());
    }
    userNames() {
        return [...this.macros.keys()].filter((name) => !["S", "K", "I"].includes(name)).sort();
    }
    expand(term) {
        if (term.kind === "macro") {
            if (!this.macros.has(term.name)) fail("unbound macro " + term.name);
            return this.expand(this.macros.get(term.name));
        }
        if (term.kind === "numeral") {
            let body = variable("x");
            for (let i = 0; i < term.value; i++) body = application(variable("f"), body);
            return abstraction("f", abstraction("x", body));
        }
        if (term.kind === "variable") return term;
        if (term.kind === "abstraction") return abstraction(term.name, this.expand(term.body));
        return application(this.expand(term.left), this.expand(term.right));
    }
    depends(name, target, seen = new Set()) {
        if (["S", "K", "I"].includes(name) || !this.macros.has(name) || seen.has(name))
            return false;
        seen.add(name);
        return references(this.macros.get(name)).some(
            (other) => other === target || this.depends(other, target, seen),
        );
    }
    reduction(term, strategy, eta, show = false, ski = false) {
        let count = 0;
        while (true) {
            const step = ski ? skiStep(term) : oneStep(term, strategy, eta);
            if (step === null) return { term, count, success: true };
            if (count === this.limit) return { term, count, success: false };
            term = step.term;
            count++;
            if (show && this.display)
                this.output.push(`step ${count} (${step.kind}): ${print(term)}`);
        }
    }
    kam(term) {
        let code = toDB(term),
            environment = [],
            stack = [],
            count = 0;
        while (true) {
            let kind = null;
            if (code.kind === "application") kind = "push";
            else if (code.kind === "abstraction" && stack.length) kind = "grab";
            else if (code.kind === "index") kind = "access";
            if (kind === null) break;
            if (count === this.limit) {
                this.output.push(`no result within ${this.limit} transitions`);
                return;
            }
            if (kind === "push") {
                stack.push({ code: code.right, environment });
                code = code.left;
            } else if (kind === "grab") {
                environment = [stack.pop(), ...environment];
                code = code.body;
            } else {
                const closure = environment[code.value];
                code = closure.code;
                environment = closure.environment;
            }
            count++;
            if (this.display)
                this.output.push(
                    `step ${count} (${kind}): ${printDB(code)} [env ${environment.length}, stack ${stack.length}]`,
                );
        }
        function restore(code, environment, depth = 0) {
            while (code.kind === "index" && code.value >= depth) {
                const closure = environment[code.value - depth];
                code = closure.code;
                environment = closure.environment;
                depth = 0;
            }
            if (code.kind === "abstraction")
                return { kind: "abstraction", body: restore(code.body, environment, depth + 1) };
            if (code.kind === "application")
                return {
                    kind: "application",
                    left: restore(code.left, environment, depth),
                    right: restore(code.right, environment, depth),
                };
            return code;
        }
        let result = restore(code, environment);
        for (const closure of stack.reverse())
            result = {
                kind: "application",
                left: result,
                right: restore(closure.code, closure.environment),
            };
        this.output.push(`result: ${print(fromDB(result))} (transitions: ${count})`);
    }
    command(line) {
        const position = line.indexOf(" "),
            command = position < 0 ? line : line.slice(0, position),
            argument = position < 0 ? "" : line.slice(position + 1);
        const commands = [
            "let",
            "unlet",
            "macros",
            "steps",
            "eta",
            "limit",
            "expand",
            "subst",
            "reduce",
            "equal",
            "alpha",
            "debruijn",
            "fv",
            "size",
            "depth",
            "type",
            "church",
            "ski",
            "skireduce",
            "kam",
        ];
        if (!commands.includes(command)) fail("unknown command " + command);
        const reserved = ["S", "K", "I", "NORMAL", "APPLICATIVE", "CBN", "CBV"];
        if (["unlet", "macros", "steps", "eta", "limit"].includes(command)) {
            const words = argument.split(" ").filter(Boolean);
            if (command === "macros") {
                if (words.length) fail("bad argument");
                const names = this.userNames();
                if (!names.length) this.output.push("(none)");
                for (const name of names)
                    this.output.push(name + " = " + print(this.macros.get(name)));
            } else if (command === "steps" || command === "eta") {
                if (words.length !== 1 || !["on", "off"].includes(words[0])) fail("bad argument");
                if (command === "steps") this.display = words[0] === "on";
                else this.eta = words[0] === "on";
            } else if (command === "limit") {
                if (
                    words.length !== 1 ||
                    !/^[0-9]{1,5}$/.test(words[0]) ||
                    Number(words[0]) < 1 ||
                    Number(words[0]) > 10000
                )
                    fail("bad argument");
                this.limit = Number(words[0]);
            } else {
                if (words.length !== 1 || !/^[A-Z][A-Z0-9_]*$/.test(words[0])) fail("bad argument");
                const name = words[0];
                if (reserved.includes(name)) fail("reserved name " + name);
                if (!this.macros.has(name)) fail("unbound macro " + name);
                const user = this.userNames().find((other) =>
                    references(this.macros.get(other)).includes(name),
                );
                if (user !== undefined) fail(name + " is used by " + user);
                this.macros.delete(name);
                this.output.push("removed " + name);
            }
            return;
        }
        const parser = new Parser(
            lex(argument, position < 0 ? line.length + 1 : position + 2, line.length + 1),
        );
        let name = "",
            strategy = "NORMAL",
            terms;
        if (command === "let" || command === "subst") {
            name = parser.expect(command === "let" ? "macro" : "variable").text;
            parser.expect("=");
            terms = [parser.term()];
            if (command === "subst") {
                parser.expect(";");
                terms.push(parser.term());
            }
        } else if (command === "equal" || command === "alpha") {
            terms = [parser.term()];
            parser.expect(";");
            terms.push(parser.term());
        } else {
            if (
                command === "reduce" &&
                parser.peek().kind === "macro" &&
                ["NORMAL", "APPLICATIVE", "CBN", "CBV"].includes(parser.peek().text)
            )
                strategy = parser.tokens[parser.at++].text;
            terms = [parser.term()];
        }
        parser.end();
        if (command === "let") {
            const term = terms[0];
            if (reserved.includes(name)) fail("reserved name " + name);
            for (const reference of references(term)) {
                if (reference === name || this.depends(reference, name))
                    fail("recursive definition of " + name);
                if (!this.macros.has(reference)) fail("unbound macro " + reference);
            }
            const variables = [...free(term)].sort();
            if (variables.length)
                fail("free variable " + variables[0] + " in definition of " + name);
            this.output.push((this.macros.has(name) ? "redefined " : "defined ") + name);
            this.macros.set(name, term);
            return;
        }
        terms = terms.map((term) => this.expand(term));
        const term = terms[0];
        if (command === "expand") this.output.push(print(term));
        else if (command === "subst") this.output.push(print(substitute(terms[1], name, term)));
        else if (command === "fv") this.output.push([...free(term)].sort().join(" ") || "(none)");
        else if (command === "debruijn") this.output.push(printDB(toDB(term)));
        else if (command === "alpha")
            this.output.push(printDB(toDB(term)) === printDB(toDB(terms[1])) ? "yes" : "no");
        else if (command === "size" || command === "depth") {
            function measure(term) {
                return term.kind === "variable"
                    ? 1
                    : term.kind === "abstraction"
                      ? 1 + measure(term.body)
                      : 1 +
                        (command === "size"
                            ? measure(term.left) + measure(term.right)
                            : Math.max(measure(term.left), measure(term.right)));
            }
            this.output.push(String(measure(term)));
        } else if (command === "type") this.output.push(principalType(term));
        else if (command === "ski") this.output.push(print(toSki(term)));
        else if (command === "kam") this.kam(term);
        else if (command === "equal") {
            const a = this.reduction(term, "NORMAL", this.eta),
                b = this.reduction(terms[1], "NORMAL", this.eta);
            this.output.push(
                !a.success || !b.success
                    ? "unknown"
                    : printDB(toDB(a.term)) === printDB(toDB(b.term))
                      ? "yes"
                      : "no",
            );
        } else {
            const ski = command === "skireduce",
                result = this.reduction(
                    ski ? toSki(term) : term,
                    strategy,
                    command === "church" ? false : this.eta,
                    command === "reduce" || ski,
                    ski,
                );
            this.output.push(
                !result.success
                    ? `no normal form within ${this.limit} steps`
                    : command === "church"
                      ? readChurch(fromDB(toDB(result.term)))
                      : `result: ${ski ? print(result.term) : canonical(result.term)} (steps: ${result.count})`,
            );
        }
    }
}
const workbench = new Workbench();
for (const line of fs.readFileSync(0, "utf8").split(/\r?\n/)) {
    if (line === "quit") break;
    if (line === "" || line.startsWith("--")) continue;
    try {
        workbench.command(line);
    } catch (error) {
        if (!(error instanceof Problem)) throw error;
        workbench.output.push("error: " + error.message);
    }
}
if (workbench.output.length) process.stdout.write(workbench.output.join("\n") + "\n");
