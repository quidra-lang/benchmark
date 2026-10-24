const fs = require('node:fs');

class MakeError extends Error {
    constructor(location, reason) { super(`${location}: *** ${reason}.  Stop.`); }
}
class BuildAbort extends Error {}
const limits = new Map([
    ['subst', [3, 3]], ['patsubst', [3, 3]], ['strip', [1, 1]], ['findstring', [2, 2]],
    ['filter', [2, 2]], ['filter-out', [2, 2]], ['sort', [1, 1]], ['word', [2, 2]],
    ['wordlist', [3, 3]], ['words', [1, 1]], ['firstword', [1, 1]], ['lastword', [1, 1]],
    ['dir', [1, 1]], ['notdir', [1, 1]], ['suffix', [1, 1]], ['basename', [1, 1]],
    ['addsuffix', [2, 2]], ['addprefix', [2, 2]], ['wildcard', [1, 1]], ['foreach', [3, 3]],
    ['if', [2, 3]], ['call', [1, Infinity]], ['value', [1, 1]], ['info', [1, 1]],
    ['warning', [1, 1]], ['error', [1, 1]]
]);
const output = [];
function leftTrim(text) { let i = 0; while (text[i] === ' ') i++; return text.slice(i); }
function rightTrim(text) { let i = text.length; while (i > 0 && text[i - 1] === ' ') i--; return text.slice(0, i); }
function trim(text) { return rightTrim(leftTrim(text)); }
function words(text) { return text.split(' ').filter(word => word.length > 0); }
function unique(items) { return [...new Set(items)]; }
function numeric(text) { return text.length > 0 && !/[^0-9]/.test(text); }
function substitute(text, stem) { const i = text.indexOf('%'); return i < 0 ? text : text.slice(0, i) + stem + text.slice(i + 1); }
function patternStem(pattern, word) {
    const i = pattern.indexOf('%');
    if (i < 0) return pattern === word ? '' : null;
    const before = pattern.slice(0, i), after = pattern.slice(i + 1);
    return word.length >= before.length + after.length && word.startsWith(before) && word.endsWith(after)
        ? word.slice(before.length, word.length - after.length) : null;
}
function replaceWord(word, pattern, replacement) {
    const stem = patternStem(pattern, word);
    return stem === null ? word : pattern.includes('%') ? substitute(replacement, stem) : replacement;
}
function wildcardMatch(pattern, name) {
    let previous = Array(name.length + 1).fill(false); previous[0] = true;
    for (const c of pattern) {
        const next = Array(name.length + 1).fill(false);
        for (let j = 0; j <= name.length; j++) next[j] = c === '*'
            ? previous[j] || j > 0 && name[j - 1] !== '/' && next[j - 1]
            : j > 0 && previous[j - 1] && (c === '?' ? name[j - 1] !== '/' : c === name[j - 1]);
        previous = next;
    }
    return previous[name.length];
}
class Simulator {
    files = new Map();
    clock = 0;
    loaded = false;
    variables = new Map();
    explicit = new Map();
    patterns = [];
    phony = new Set();
    goal = null;
    location = 'make';
    scopes = [];
    expanding = new Set();
    automatic = null;
    fail(reason) { throw new MakeError(this.location, reason); }
    resetMakefile() {
        this.loaded = false; this.variables.clear(); this.explicit.clear(); this.patterns = [];
        this.phony.clear(); this.goal = null;
    }
    touch(name) { this.files.set(name, ++this.clock); }
    wildcard(pattern) { return [...this.files.keys()].sort().filter(name => wildcardMatch(pattern, name)); }
    closing(text, dollar) {
        const open = text[dollar + 1], close = open === '(' ? ')' : '}';
        let depth = 0;
        for (let i = dollar + 1; i < text.length; i++) {
            if (text[i] === open) depth++;
            if (text[i] === close && --depth === 0) return i;
        }
        this.fail('unterminated variable reference');
    }
    expand(text) {
        let result = '';
        for (let i = 0; i < text.length;) {
            if (text[i] !== '$') { result += text[i++]; continue; }
            if (i + 1 === text.length) break;
            const next = text[i + 1];
            if (next === '$') { result += '$'; i += 2; }
            else if (next === '(' || next === '{') {
                const end = this.closing(text, i);
                result += this.reference(text.slice(i + 2, end), next); i = end + 1;
            } else { result += this.value(next); i += 2; }
        }
        return result;
    }
    reference(content, open) {
        const space = content.indexOf(' '), name = content.slice(0, space);
        if (space >= 0 && limits.has(name)) return this.callFunction(name, leftTrim(content.slice(space + 1)), open);
        const expanded = this.expand(content), colon = expanded.indexOf(':'), equal = expanded.indexOf('=', colon + 1);
        if (colon >= 0 && equal >= 0) {
            let pattern = expanded.slice(colon + 1, equal), replacement = expanded.slice(equal + 1);
            if (!pattern.includes('%')) { pattern = '%' + pattern; replacement = '%' + replacement; }
            return words(this.value(expanded.slice(0, colon))).map(word => replaceWord(word, pattern, replacement)).join(' ');
        }
        return this.value(expanded);
    }
    value(name) {
        for (let i = this.scopes.length - 1; i >= 0; i--) {
            const scope = this.scopes[i];
            if (scope.kind === 'foreach' && scope.name === name) return scope.word;
            if (scope.kind === 'call' && numeric(name)) return scope.values[Number(name)] ?? '';
        }
        if (this.automatic !== null && this.automatic.has(name)) return this.automatic.get(name);
        const variable = this.variables.get(name);
        if (variable === undefined) return '';
        if (variable.kind === ':=') return variable.value;
        if (this.expanding.has(name)) this.fail(`Recursive variable '${name}' references itself (eventually)`);
        this.expanding.add(name);
        try { return this.expand(variable.value); } finally { this.expanding.delete(name); }
    }
    callFunction(name, text, open) {
        const [minimum, maximum] = limits.get(name), args = [];
        const close = open === '(' ? ')' : '}';
        let depth = 0, start = 0;
        for (let i = 0; i < text.length; i++) {
            if (text[i] === open) depth++;
            else if (text[i] === close) depth--;
            else if (text[i] === ',' && depth === 0 && args.length < maximum - 1) { args.push(text.slice(start, i)); start = i + 1; }
        }
        args.push(text.slice(start));
        if (args.length < minimum) this.fail(`insufficient number of arguments (${args.length}) to function '${name}'`);
        if (name === 'foreach') {
            const variable = trim(this.expand(args[0])), list = words(this.expand(args[1])), result = [];
            for (const word of list) {
                this.scopes.push({ kind: 'foreach', name: variable, word });
                try { result.push(this.expand(args[2])); } finally { this.scopes.pop(); }
            }
            return result.join(' ');
        }
        if (name === 'if') return this.expand(args[trim(this.expand(args[0])) ? 1 : 2] ?? '');
        const expanded = args.map(argument => this.expand(argument));
        if (name === 'subst') return expanded[0] === '' ? expanded[2] : expanded[2].split(expanded[0]).join(expanded[1]);
        if (name === 'call') {
            const variableName = trim(expanded[0]), variable = this.variables.get(variableName);
            if (variable === undefined) return '';
            if (variable.kind === ':=') return variable.value;
            this.scopes.push({ kind: 'call', values: [variableName, ...expanded.slice(1)] });
            try { return this.expand(variable.value); } finally { this.scopes.pop(); }
        }
        const values = expanded.map(trim), a = values[0], b = values[1], c = values[2];
        switch (name) {
            case 'patsubst': return words(c).map(word => replaceWord(word, a, b)).join(' ');
            case 'strip': return words(a).join(' ');
            case 'findstring': return b.includes(a) ? a : '';
            case 'filter': case 'filter-out': return words(b).filter(word => words(a).some(pattern => patternStem(pattern, word) !== null) === (name === 'filter')).join(' ');
            case 'sort': return unique(words(a)).sort().join(' ');
            case 'word':
                if (!numeric(a)) this.fail(`non-numeric first argument to 'word' function: '${a}'`);
                if (Number(a) === 0) this.fail("first argument to 'word' function must be greater than 0");
                return words(b)[Number(a) - 1] ?? '';
            case 'wordlist':
                if (!numeric(a)) this.fail(`non-numeric first argument to 'wordlist' function: '${a}'`);
                if (!numeric(b)) this.fail(`non-numeric second argument to 'wordlist' function: '${b}'`);
                if (Number(a) === 0) this.fail(`invalid first argument to 'wordlist' function: '${a}'`);
                return words(c).slice(Number(a) - 1, Number(b)).join(' ');
            case 'words': return String(words(a).length);
            case 'firstword': return words(a)[0] ?? '';
            case 'lastword': return words(a).at(-1) ?? '';
            case 'dir': return words(a).map(word => word.includes('/') ? word.slice(0, word.lastIndexOf('/') + 1) : './').join(' ');
            case 'notdir': return words(a).map(word => word.slice(word.lastIndexOf('/') + 1)).join(' ');
            case 'suffix': return words(a).filter(word => word.lastIndexOf('.') > word.lastIndexOf('/')).map(word => word.slice(word.lastIndexOf('.'))).join(' ');
            case 'basename': return words(a).map(word => word.lastIndexOf('.') > word.lastIndexOf('/') ? word.slice(0, word.lastIndexOf('.')) : word).join(' ');
            case 'addsuffix': return words(b).map(word => word + a).join(' ');
            case 'addprefix': return words(b).map(word => a + word).join(' ');
            case 'wildcard': return words(a).flatMap(pattern => this.wildcard(pattern)).join(' ');
            case 'value': return this.variables.get(a)?.value ?? '';
            case 'info': output.push(a); return '';
            case 'warning': output.push(this.location + ': ' + a); return '';
            case 'error': this.fail(a);
        }
        return '';
    }
    punctuation(text) {
        const result = new Map();
        for (let i = 0; i < text.length; i++) {
            if (text[i] === '$') {
                if (text[i + 1] === '(' || text[i + 1] === '{') i = this.closing(text, i);
                else if (i + 1 < text.length) i++;
            } else if ('=:;'.includes(text[i]) && !result.has(text[i])) result.set(text[i], i);
        }
        return result;
    }
    register(name, prerequisites) {
        if (!this.explicit.has(name)) this.explicit.set(name, { name, prerequisites: [], recipe: null, stem: '' });
        const rule = this.explicit.get(name);
        rule.prerequisites = unique([...rule.prerequisites, ...prerequisites]);
        if (this.goal === null && !name.startsWith('.')) this.goal = name;
        return rule;
    }
    addRecipe(current, line, text) {
        if (!current.entries.length) return;
        if (current.recipe === null) {
            current.recipe = [];
            for (const entry of current.entries) {
                if (current.explicit && entry.recipe !== null) {
                    output.push(`Makefile:${line}: warning: overriding recipe for target '${entry.name}'`,
                        `Makefile:${entry.recipe[0].line}: warning: ignoring old recipe for target '${entry.name}'`);
                }
                entry.recipe = current.recipe;
            }
        }
        current.recipe.push({ line, text });
    }
    load(body) {
        this.resetMakefile();
        const conditions = [];
        let current = null;
        const active = () => !conditions.length || conditions.at(-1).outer && conditions.at(-1).value;
        try {
            for (let i = 0; i < body.length; i++) {
                const line = i + 1;
                this.location = 'Makefile:' + line;
                if (body[i].startsWith('>')) {
                    if (!active()) continue;
                    if (current === null) this.fail('recipe commences before first target');
                    this.addRecipe(current, line, leftTrim(body[i].slice(1))); continue;
                }
                let logical = body[i];
                while (logical.endsWith('\\') && i + 1 < body.length) logical = rightTrim(logical.slice(0, -1)) + ' ' + leftTrim(body[++i]);
                const text = trim(logical.split('#')[0]), space = text.indexOf(' '), first = space < 0 ? text : text.slice(0, space), rest = space < 0 ? '' : trim(text.slice(space + 1));
                if (['ifeq', 'ifneq', 'ifdef', 'ifndef'].includes(first)) {
                    const outer = active(); let value = false;
                    if (outer) {
                        if (first === 'ifdef' || first === 'ifndef') {
                            const variable = this.variables.get(trim(this.expand(rest)));
                            value = variable !== undefined && variable.value !== '';
                            if (first === 'ifndef') value = !value;
                        } else {
                            if (rest.length < 2 || !rest.startsWith('(') || !rest.endsWith(')')) this.fail('invalid syntax in conditional');
                            const inside = rest.slice(1, -1); let depth = 0, comma = -1;
                            for (let j = 0; j < inside.length; j++) {
                                if (inside[j] === '(') depth++;
                                else if (inside[j] === ')') depth--;
                                else if (inside[j] === ',' && depth === 0) { comma = j; break; }
                            }
                            if (comma < 0) this.fail('invalid syntax in conditional');
                            const left = trim(this.expand(inside.slice(0, comma))), right = trim(this.expand(inside.slice(comma + 1)));
                            value = left === right; if (first === 'ifneq') value = !value;
                        }
                    }
                    conditions.push({ outer, value, alternate: false, line }); continue;
                }
                if (first === 'else') {
                    if (!conditions.length) this.fail("extraneous 'else'");
                    const condition = conditions.at(-1);
                    if (condition.alternate) this.fail("only one 'else' per conditional");
                    condition.value = !condition.value; condition.alternate = true; continue;
                }
                if (first === 'endif') {
                    if (!conditions.length) this.fail("extraneous 'endif'");
                    conditions.pop(); continue;
                }
                if (text === '' || !active()) continue;
                const positions = this.punctuation(text), equal = positions.get('='), colon = positions.get(':');
                if (equal !== undefined && (colon === undefined || colon >= equal - 1)) {
                    const special = equal > 0 && ':+?'.includes(text[equal - 1]), op = special ? text[equal - 1] + '=' : '=';
                    const name = trim(text.slice(0, equal - (special ? 1 : 0))), rhs = trim(text.slice(equal + 1));
                    if (!name) this.fail('empty variable name');
                    const previous = this.variables.get(name);
                    if (op === '=' || op === '?=' && previous === undefined || op === '+=' && previous === undefined) this.variables.set(name, { kind: '=', value: rhs });
                    else if (op === ':=') this.variables.set(name, { kind: ':=', value: this.expand(rhs) });
                    else if (op === '+=') { const value = previous.kind === ':=' ? this.expand(rhs) : rhs; previous.value = previous.value === '' ? value : previous.value + ' ' + value; }
                    current = null;
                } else if (colon !== undefined) {
                    const targets = unique(words(this.expand(text.slice(0, colon))));
                    let rhs = text.slice(colon + 1), inline = null, targetPattern = null;
                    const semicolon = this.punctuation(rhs).get(';');
                    if (semicolon !== undefined) { inline = leftTrim(rhs.slice(semicolon + 1)); rhs = rhs.slice(0, semicolon); }
                    const secondColon = this.punctuation(rhs).get(':');
                    if (secondColon !== undefined) { targetPattern = trim(this.expand(rhs.slice(0, secondColon))); rhs = rhs.slice(secondColon + 1); }
                    const prerequisites = words(this.expand(rhs));
                    current = { entries: [], explicit: true, recipe: null };
                    if (targets.length === 1 && targets[0] === '.PHONY') for (const name of prerequisites) this.phony.add(name);
                    else if (targetPattern !== null) {
                        if (!targetPattern.includes('%')) this.fail("target pattern contains no '%'");
                        for (const name of targets) {
                            const stem = patternStem(targetPattern, name);
                            if (stem === null || stem === '') output.push(`Makefile:${line}: target '${name}' doesn't match the target pattern`);
                            else { const entry = this.register(name, prerequisites.map(value => substitute(value, stem))); entry.stem = stem; current.entries.push(entry); }
                        }
                    } else if (targets.some(name => name.includes('%'))) {
                        if (targets.some(name => !name.includes('%'))) this.fail('mixed implicit and normal rules');
                        current.explicit = false;
                        for (const name of targets) { const entry = { name, prerequisites: [...prerequisites], recipe: null, stem: '' }; this.patterns.push(entry); current.entries.push(entry); }
                    } else for (const name of targets) current.entries.push(this.register(name, prerequisites));
                    if (inline !== null) this.addRecipe(current, line, inline);
                } else if (trim(this.expand(text)) !== '') this.fail('missing separator');
            }
            if (conditions.length) { this.location = 'Makefile:' + conditions.at(-1).line; this.fail("missing 'endif'"); }
            this.loaded = true;
            output.push(`Makefile loaded: lines=${body.length} variables=${this.variables.size} targets=${this.explicit.size} patterns=${this.patterns.filter(rule => rule.recipe !== null).length} goal=${this.goal ?? '(none)'}`);
        } catch (error) {
            if (!(error instanceof MakeError)) throw error;
            output.push(error.message); this.resetMakefile();
        } finally { this.location = 'make'; }
    }
    determine(name) {
        const explicit = this.explicit.get(name);
        if (explicit !== undefined && explicit.recipe !== null) return { ...explicit, prerequisites: [...explicit.prerequisites], kind: 'rule' };
        if (!this.phony.has(name)) {
            const candidates = this.patterns.map((rule, index) => ({ rule, index, stem: patternStem(rule.name, name) }))
                .filter(item => item.rule.recipe !== null && item.stem !== null && item.stem !== '')
                .sort((a, b) => a.stem.length - b.stem.length || a.index - b.index);
            for (const item of candidates) {
                const prerequisites = item.rule.prerequisites.map(value => substitute(value, item.stem));
                if (prerequisites.every(value => this.files.has(value) || this.explicit.has(value))) return { name, prerequisites: unique([...prerequisites, ...(explicit?.prerequisites ?? [])]), recipe: item.rule.recipe, stem: item.stem, kind: 'rule' };
            }
        }
        if (explicit !== undefined || this.phony.has(name)) return { name, prerequisites: [...(explicit?.prerequisites ?? [])], recipe: null, stem: explicit?.stem ?? '', kind: 'rule' };
        return { name, prerequisites: [], recipe: null, stem: '', kind: this.files.has(name) ? 'source' : 'missing' };
    }
    executeRecipeCommand(command) {
        const list = words(command), args = list.slice(1);
        if (list[0] === 'echo') output.push(args.join(' '));
        else if (list[0] === 'touch') for (const name of args) this.touch(name);
        else if (list[0] === 'rm') {
            const forced = args[0] === '-f'; let status = 0;
            for (const pattern of forced ? args.slice(1) : args) {
                const matches = this.wildcard(pattern);
                for (const name of matches.length ? matches : [pattern]) {
                    if (!this.files.delete(name) && !forced) { output.push(`rm: cannot remove '${name}': No such file or directory`); status = 1; }
                }
            }
            return status;
        } else if (list[0] === 'false') return 1;
        else if (list[0] === 'exit') return Number(args[0] ?? 0);
        return 0;
    }
    make(args) {
        const flags = new Set(), goals = [];
        for (const argument of args) {
            if (argument.startsWith('-')) for (const c of argument.slice(1)) {
                if (!'nBkis'.includes(c)) { output.push(`make: invalid option -- '${c}'`); return; }
                flags.add(c);
            } else goals.push(argument);
        }
        if (!goals.length) {
            if (!this.loaded) { output.push('make: *** No targets specified and no makefile found.  Stop.'); return; }
            if (this.goal === null) { output.push('make: *** No targets.  Stop.'); return; }
            goals.push(this.goal);
        }
        const savedFiles = new Map(this.files), savedClock = this.clock, results = new Map(), beingBuilt = new Set();
        let runs = 0;
        const targetTime = name => this.phony.has(name) ? undefined : this.files.get(name);
        const build = (name, parent) => {
            if (results.has(name)) return results.get(name);
            const rule = this.determine(name);
            if (rule.kind === 'missing') {
                output.push(`make: *** No rule to make target '${name}'${parent === null ? '' : `, needed by '${parent}'`}.${flags.has('k') ? '' : '  Stop.'}`);
                if (!flags.has('k')) throw new BuildAbort();
                const result = { status: 'failure', rule }; results.set(name, result); return result;
            }
            if (rule.kind === 'source') { const result = { status: 'success', rule }; results.set(name, result); return result; }
            beingBuilt.add(name); let failed = false;
            const kept = [];
            for (const prerequisite of rule.prerequisites) {
                if (beingBuilt.has(prerequisite)) { output.push(`make: Circular ${name} <- ${prerequisite} dependency dropped.`); continue; }
                kept.push(prerequisite);
                if (build(prerequisite, name).status !== 'success') failed = true;
            }
            rule.prerequisites = kept; beingBuilt.delete(name);
            let status = 'dependency failure';
            if (!failed) {
                status = 'success';
                const time = targetTime(name), newer = kept.filter(value => flags.has('B') || time === undefined || targetTime(value) === undefined || targetTime(value) > time);
                if (rule.recipe !== null && (flags.has('B') || time === undefined || newer.length)) {
                    runs++;
                    this.automatic = new Map([['@', name], ['<', kept[0] ?? ''], ['^', kept.join(' ')], ['?', newer.join(' ')], ['*', rule.stem]]);
                    let commands;
                    try { commands = rule.recipe.map(line => { this.location = 'Makefile:' + line.line; return { line: line.line, text: this.expand(line.text) }; }); }
                    finally { this.automatic = null; this.location = 'make'; }
                    for (const line of commands) {
                        let i = 0; while (i < line.text.length && ' @-'.includes(line.text[i])) i++;
                        const prefix = line.text.slice(0, i), command = rightTrim(line.text.slice(i));
                        if (!command) continue;
                        if (flags.has('n') || !prefix.includes('@') && !flags.has('s')) output.push(command);
                        if (flags.has('n')) continue;
                        const code = this.executeRecipeCommand(command);
                        if (code !== 0) {
                            if (prefix.includes('-') || flags.has('i')) output.push(`make: [Makefile:${line.line}: ${name}] Error ${code} (ignored)`);
                            else { output.push(`make: *** [Makefile:${line.line}: ${name}] Error ${code}`); if (!flags.has('k')) throw new BuildAbort(); status = 'failure'; break; }
                        }
                    }
                    if (status === 'success' && !this.phony.has(name)) this.touch(name);
                }
            }
            const result = { status, rule }; results.set(name, result); return result;
        };
        try {
            for (const goal of goals) {
                const previous = runs, result = build(goal, null);
                if (result.status === 'dependency failure') output.push(`make: Target '${goal}' not remade because of errors.`);
                else if (result.status === 'success' && previous === runs) output.push(this.phony.has(goal) || result.rule.recipe === null ? `make: Nothing to be done for '${goal}'.` : `make: '${goal}' is up to date.`);
            }
        } catch (error) {
            if (error instanceof MakeError) output.push(error.message);
            else if (!(error instanceof BuildAbort)) throw error;
        } finally { if (flags.has('n')) { this.files = savedFiles; this.clock = savedClock; } }
    }
    other(commandLine) {
        this.location = 'make';
        const [command, ...args] = commandLine.split(' ');
        if (command === 'MAKE') this.make(args);
        else if (command === 'TOUCH') for (const name of args) this.touch(name);
        else if (command === 'RM') for (const name of args) { if (!this.files.delete(name)) output.push(`rm: cannot remove '${name}': No such file or directory`); }
        else if (command === 'FILES') { output.push('clock ' + this.clock); for (const name of [...this.files.keys()].sort()) output.push(name + ' ' + this.files.get(name)); }
        else if (command === 'EXPAND') output.push('[' + this.expand(commandLine.slice(7)) + ']');
        else if (command === 'VARS' && this.loaded) for (const name of [...this.variables.keys()].sort()) { const value = trim(this.value(name)); output.push(name + ' ' + this.variables.get(name).kind + (value ? ' ' + value : '')); }
        else if (command === 'RULES' && this.loaded) {
            const rules = [...[...this.explicit.keys()].sort().map(name => this.explicit.get(name)), ...this.patterns.filter(rule => rule.recipe !== null)];
            for (const rule of rules) { output.push(rule.name + ':' + rule.prerequisites.map(value => ' ' + value).join('')); for (const line of rule.recipe ?? []) output.push('>' + line.text); }
            if (this.phony.size) output.push('.PHONY: ' + [...this.phony].sort().join(' '));
        }
    }
}
const simulator = new Simulator(), input = fs.readFileSync(0, 'utf8').split(/\r?\n/);
let at = 1;
while (input[at] !== 'END FILES') { const [name, time] = input[at++].split(' '); simulator.files.set(name, Number(time)); simulator.clock = Math.max(simulator.clock, Number(time)); }
at++;
while (input[at] !== 'QUIT') {
    const command = input[at++]; output.push('$ ' + command);
    if (command === 'MAKEFILE') { const body = []; while (input[at] !== 'END MAKEFILE') body.push(input[at++]); at++; simulator.load(body); }
    else try { simulator.other(command); } catch (error) { if (error instanceof MakeError) output.push(error.message); else throw error; }
}
if (output.length) process.stdout.write(output.join('\n') + '\n');
