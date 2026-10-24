const fs = require('node:fs');

const TYPES = ['BUG', 'TASK', 'STORY'];
const PRIORITIES = ['LOW', 'MEDIUM', 'HIGH', 'CRITICAL'];
const WORKFLOWS = {
    BUG: ['OPEN', 'TRIAGED', 'IN_PROGRESS', 'REVIEW', 'RESOLVED', 'CLOSED', 'REOPENED'],
    TASK: ['OPEN', 'IN_PROGRESS', 'DONE'],
    STORY: ['BACKLOG', 'READY', 'IN_PROGRESS', 'REVIEW', 'DONE'],
};
const TRANSITIONS = {
    BUG: ['OPEN:TRIAGED', 'TRIAGED:IN_PROGRESS', 'IN_PROGRESS:REVIEW', 'REVIEW:IN_PROGRESS',
        'REVIEW:RESOLVED', 'RESOLVED:CLOSED', 'RESOLVED:REOPENED', 'CLOSED:REOPENED', 'REOPENED:IN_PROGRESS'],
    TASK: ['OPEN:IN_PROGRESS', 'IN_PROGRESS:OPEN', 'IN_PROGRESS:DONE'],
    STORY: ['BACKLOG:READY', 'READY:BACKLOG', 'READY:IN_PROGRESS', 'IN_PROGRESS:REVIEW', 'REVIEW:IN_PROGRESS', 'REVIEW:DONE'],
};
const ALL_STATES = new Set(Object.values(WORKFLOWS).flat());
const DONE_STATES = new Set(['RESOLVED', 'CLOSED', 'DONE']);
const ESTIMATES = new Set([0, 1, 2, 3, 5, 8, 13, 21]);
const EQUALITY = ['=', '!='];
const ORDERED = ['=', '!=', '<', '<=', '>', '>='];
const FIELD_OPERATORS = new Map([
    ['id', ORDERED], ['type', EQUALITY], ['status', EQUALITY], ['priority', ORDERED],
    ['assignee', EQUALITY], ['reviewer', EQUALITY], ['estimate', ORDERED], ['sprint', EQUALITY],
    ['comments', ORDERED], ['blocked', EQUALITY], ['done', EQUALITY], ['title', ['~']],
]);
const NONE_FIELDS = new Set(['assignee', 'reviewer', 'estimate', 'sprint']);

class CommandError extends Error {}

function display(value) { return value === null ? '-' : String(value); }
function yesNo(value) { return value ? 'yes' : 'no'; }
function sortedNumbers(values) { return [...values].sort((a, b) => a - b); }
function numberList(values) { return sortedNumbers(values).join(',') || '-'; }
function isNumber(value) { return /^[0-9]{1,6}$/.test(value); }

function compare(actual, operator, expected) {
    if (operator === '=') return actual === expected;
    if (operator === '!=') return actual !== expected;
    if (actual === null || expected === null) return false;
    if (operator === '<') return actual < expected;
    if (operator === '<=') return actual <= expected;
    if (operator === '>') return actual > expected;
    return actual >= expected;
}

class Issue {
    assignee = null;
    reviewer = null;
    estimate = null;
    sprint = null;
    comments = 0;
    blocks = new Set();
    blockers = new Set();
    duplicate = null;
    duplicates = new Set();
    history = [];

    constructor(number, type, priority, title) {
        this.number = number;
        this.type = type;
        this.priority = priority;
        this.title = title;
        this.state = WORKFLOWS[type][0];
    }

    done() { return DONE_STATES.has(this.state); }
    points() { return this.estimate ?? 0; }
    level() { return PRIORITIES.indexOf(this.priority); }
}

class Sprint {
    phase = 'PLANNED';
    start = null;
    end = null;
    velocity = 0;
    records = new Map();

    constructor(name) { this.name = name; }
}

function parseQuery(tokens, conditions) {
    let position = 0;
    function factor() {
        if (tokens[position] === 'NOT') {
            ++position;
            const operand = factor();
            return issue => !operand(issue);
        }
        if (tokens[position] === '(') {
            ++position;
            const node = expression();
            ++position;
            return node;
        }
        return conditions[position++];
    }
    function term() {
        let node = factor();
        while (tokens[position] === 'AND') {
            ++position;
            const left = node;
            const right = factor();
            node = issue => left(issue) && right(issue);
        }
        return node;
    }
    function expression() {
        let node = term();
        while (tokens[position] === 'OR') {
            ++position;
            const left = node;
            const right = term();
            node = issue => left(issue) || right(issue);
        }
        return node;
    }
    return expression();
}

class Tracker {
    day = 1;
    users = new Set();
    issues = new Map();
    sprints = new Map();
    output = [];

    emit(...parts) { this.output.push(parts.join(' ')); }

    issue(text) {
        const issue = this.issues.get(Number(text));
        if (!issue) throw new CommandError('unknown issue');
        return issue;
    }

    user(spec) {
        if (spec === '-') return null;
        if (!this.users.has(spec)) throw new CommandError('unknown user');
        return spec;
    }

    sprint(name) {
        const sprint = this.sprints.get(name);
        if (!sprint) throw new CommandError('unknown sprint');
        return sprint;
    }

    notDone(issue) {
        if (issue.done()) throw new CommandError('issue done');
    }

    orderedIssues() { return [...this.issues.values()].sort((a, b) => a.number - b.number); }
    unfinishedBlockers(issue) { return sortedNumbers(issue.blockers).filter(n => !this.issues.get(n).done()); }
    blocked(issue) { return !issue.done() && this.unfinishedBlockers(issue).length > 0; }
    wip(user) { return [...this.issues.values()].filter(i => i.assignee === user && i.state === 'IN_PROGRESS').length; }
    active() { return [...this.sprints.values()].find(s => s.phase === 'ACTIVE'); }
    members(sprint) { return this.orderedIssues().filter(i => i.sprint === sprint.name); }
    remaining(sprint) { return this.members(sprint).filter(i => !i.done()).reduce((n, i) => n + i.points(), 0); }

    summary(sprint) {
        const members = this.members(sprint);
        return `issues ${members.length} points ${members.reduce((n, i) => n + i.points(), 0)}`;
    }

    record(issue, content) { issue.history.push(`day ${this.day} ${content}`); }

    blockedStates(numbers) {
        return new Map([...numbers].map(n => [n, this.blocked(this.issues.get(n))]));
    }

    notify(before) {
        for (const n of sortedNumbers(before.keys())) {
            const after = this.blocked(this.issues.get(n));
            if (after !== before.get(n)) this.emit(after ? 'BLOCKED' : 'UNBLOCKED', n);
        }
    }

    changeState(issue, target) {
        const before = this.blockedStates(issue.blocks);
        this.emit('MOVE', issue.number, issue.state, target);
        this.record(issue, `MOVE ${issue.state} ${target}`);
        issue.state = target;
        this.notify(before);
    }

    reaches(start, goal) {
        const pending = [start];
        const seen = new Set();
        while (pending.length) {
            const n = pending.pop();
            if (n === goal) return true;
            if (seen.has(n)) continue;
            seen.add(n);
            pending.push(...this.issues.get(n).blocks);
        }
        return false;
    }

    fieldValue(issue, field) {
        switch (field) {
        case 'id': return issue.number;
        case 'type': return issue.type;
        case 'status': return issue.state;
        case 'priority': return issue.level();
        case 'assignee': return issue.assignee;
        case 'reviewer': return issue.reviewer;
        case 'estimate': return issue.estimate;
        case 'sprint': return issue.sprint;
        case 'comments': return issue.comments;
        case 'blocked': return yesNo(this.blocked(issue));
        case 'done': return yesNo(issue.done());
        default: return issue.title.toLowerCase();
        }
    }

    conditionValue(token, field, operator, value) {
        if (value === '-' && NONE_FIELDS.has(field) && EQUALITY.includes(operator)) return null;
        if (['id', 'estimate', 'comments'].includes(field) && isNumber(value)) return Number(value);
        if (field === 'priority' && PRIORITIES.includes(value)) return PRIORITIES.indexOf(value);
        if (field === 'type' && TYPES.includes(value)) return value;
        if (field === 'status' && ALL_STATES.has(value)) return value;
        if (['assignee', 'reviewer'].includes(field) && this.users.has(value)) return value;
        if (field === 'sprint' && this.sprints.has(value)) return value;
        if (['blocked', 'done'].includes(field) && ['yes', 'no'].includes(value)) return value;
        if (field === 'title') return value.toLowerCase();
        throw new CommandError(`bad value ${token}`);
    }

    condition(token) {
        const match = /^([a-z]*)(>=|<=|!=|=|<|>|~)(.*)$/.exec(token);
        if (!match || !match[1] || !match[3]) throw new CommandError(`syntax near ${token}`);
        const [, field, operator, text] = match;
        const operators = FIELD_OPERATORS.get(field);
        if (!operators) throw new CommandError(`unknown field ${field}`);
        if (!operators.includes(operator)) throw new CommandError(`bad operator ${token}`);
        const expected = this.conditionValue(token, field, operator, text);
        return issue => {
            const actual = this.fieldValue(issue, field);
            return operator === '~' ? actual.includes(expected) : compare(actual, operator, expected);
        };
    }

    query(text) {
        const tokens = text.match(/[()]|[^ ()]+/g) ?? [];
        const conditions = [];
        let operand = true;
        let depth = 0;
        for (const token of tokens) {
            let condition = null;
            if (operand) {
                if (token === '(') ++depth;
                else if (['AND', 'OR', ')'].includes(token)) throw new CommandError(`syntax near ${token}`);
                else if (token !== 'NOT') { condition = this.condition(token); operand = false; }
            } else if (['AND', 'OR'].includes(token)) operand = true;
            else if (token === ')' && depth > 0) --depth;
            else throw new CommandError(`syntax near ${token}`);
            conditions.push(condition);
        }
        if (operand || depth !== 0) throw new CommandError('syntax at end');
        const matches = [...this.issues.values()].filter(parseQuery(tokens, conditions));
        matches.sort((a, b) => b.level() - a.level() || a.number - b.number);
        this.emit('QUERY', matches.length);
        for (const i of matches) this.emit(i.number, i.type, i.priority, i.state, display(i.assignee), display(i.estimate), i.title);
    }

    execute(line) {
        this.output = [];
        try {
            const [command, ...args] = line.split(' ');
            this.dispatch(command, args);
        } catch (error) {
            if (!(error instanceof CommandError)) throw error;
            this.emit('ERROR', error.message);
        }
        const active = this.active();
        if (active) active.records.set(this.day, this.remaining(active));
        return this.output;
    }

    dispatch(command, args) {
        const [x, y, z] = args;
        switch (command) {
        case 'DAY': {
            const day = Number(x);
            if (day < this.day) throw new CommandError('day backwards');
            this.day = day;
            this.emit('DAY', day);
            return;
        }
        case 'USER':
            if (this.users.has(x)) throw new CommandError('user exists');
            this.users.add(x);
            this.emit('USER', x);
            return;
        case 'CREATE': {
            const n = Number(x);
            if (this.issues.has(n)) throw new CommandError('issue exists');
            if (!TYPES.includes(y)) throw new CommandError('bad type');
            if (!PRIORITIES.includes(z)) throw new CommandError('bad priority');
            const issue = new Issue(n, y, z, args.slice(3).join(' '));
            this.issues.set(n, issue);
            this.record(issue, `CREATE ${y} ${z}`);
            this.emit('CREATE', n, y, z, issue.state);
            return;
        }
        case 'QUERY': this.query(args.join(' ')); return;
        case 'SPRINT': this.sprintCommand(args); return;
        case 'BOARD': {
            this.emit('BOARD');
            const issues = [...this.issues.values()];
            for (const type of TYPES) {
                const parts = [type];
                for (const state of WORKFLOWS[type]) parts.push(state, String(issues.filter(i => i.type === type && i.state === state).length));
                this.emit(...parts);
            }
            const done = issues.filter(i => i.done()).length;
            this.emit('TOTAL', issues.length, 'open', issues.length - done, 'done', done);
            return;
        }
        case 'WORKLOAD':
            this.emit('WORKLOAD', this.users.size);
            for (const user of [...this.users].sort()) {
                const issues = [...this.issues.values()];
                const assigned = issues.filter(i => i.assignee === user && !i.done());
                this.emit(user, 'assigned', assigned.length, 'in_progress', assigned.filter(i => i.state === 'IN_PROGRESS').length,
                    'review', assigned.filter(i => i.state === 'REVIEW').length,
                    'reviewing', issues.filter(i => i.reviewer === user && i.state === 'REVIEW').length,
                    'points', assigned.reduce((sum, i) => sum + i.points(), 0));
            }
            return;
        case 'SPRINTS':
            this.emit('SPRINTS', this.sprints.size);
            for (const s of this.sprints.values()) {
                if (s.phase === 'PLANNED') this.emit(s.name, s.phase, this.summary(s));
                else if (s.phase === 'ACTIVE') this.emit(s.name, s.phase, 'start', s.start, this.summary(s), 'remaining', this.remaining(s));
                else this.emit(s.name, s.phase, 'start', s.start, 'end', s.end, 'velocity', s.velocity);
            }
            return;
        case 'BURNDOWN': {
            const s = this.sprint(x);
            if (s.phase === 'PLANNED') throw new CommandError('sprint not started');
            const last = s.phase === 'ACTIVE' ? this.day : s.end;
            this.emit('BURNDOWN', x, s.phase, 'days', last - s.start + 1);
            let value = 0;
            for (let day = s.start; day <= last; ++day) {
                if (s.records.has(day)) value = s.records.get(day);
                this.emit('day', day, value);
            }
            return;
        }
        case 'LINK':
        case 'UNLINK': this.link(command, args); return;
        }
        const i = this.issue(x);
        switch (command) {
        case 'PRIORITY': {
            if (!PRIORITIES.includes(y)) throw new CommandError('bad priority');
            this.notDone(i);
            if (i.priority === y) throw new CommandError('no change');
            const before = i.priority;
            i.priority = y;
            this.record(i, `PRIORITY ${before} ${y}`);
            this.emit('PRIORITY', i.number, before, y);
            return;
        }
        case 'ASSIGN': {
            const user = this.user(y);
            this.notDone(i);
            if (i.assignee === user) throw new CommandError('no change');
            if (user === null && ['IN_PROGRESS', 'REVIEW'].includes(i.state)) throw new CommandError('assignee required');
            if (i.state === 'IN_PROGRESS' && this.wip(user) >= 3) throw new CommandError(`wip limit ${y}`);
            if (i.state === 'REVIEW' && user === i.reviewer) throw new CommandError('reviewer is assignee');
            i.assignee = user;
            this.record(i, `ASSIGN ${y}`);
            this.emit('ASSIGN', i.number, y);
            return;
        }
        case 'REVIEWER': {
            const user = this.user(y);
            this.notDone(i);
            if (i.reviewer === user) throw new CommandError('no change');
            if (user === null && i.state === 'REVIEW') throw new CommandError('reviewer required');
            if (i.state === 'REVIEW' && user === i.assignee) throw new CommandError('reviewer is assignee');
            i.reviewer = user;
            this.record(i, `REVIEWER ${y}`);
            this.emit('REVIEWER', i.number, y);
            return;
        }
        case 'ESTIMATE': {
            const points = Number(y);
            if (!ESTIMATES.has(points)) throw new CommandError('bad estimate');
            this.notDone(i);
            if (i.estimate === points) throw new CommandError('no change');
            const before = display(i.estimate);
            i.estimate = points;
            this.record(i, `ESTIMATE ${before} ${points}`);
            this.emit('ESTIMATE', i.number, before, points);
            return;
        }
        case 'COMMENT':
            this.user(y);
            ++i.comments;
            this.record(i, `COMMENT ${y} ${args.slice(2).join(' ')}`);
            this.emit('COMMENT', i.number, i.comments);
            return;
        case 'MOVE': {
            if (i.duplicate !== null) throw new CommandError(`duplicate of ${i.duplicate}`);
            if (!WORKFLOWS[i.type].includes(y)) throw new CommandError('bad state');
            if (!TRANSITIONS[i.type].includes(`${i.state}:${y}`)) throw new CommandError(`cannot move ${i.state} to ${y}`);
            if (y === 'IN_PROGRESS') {
                const active = this.active();
                if (i.type === 'STORY' && (!active || i.sprint !== active.name)) throw new CommandError('not in active sprint');
                if (i.assignee === null) throw new CommandError('no assignee');
                if (this.wip(i.assignee) >= 3) throw new CommandError(`wip limit ${i.assignee}`);
            }
            if (y === 'REVIEW') {
                if (i.reviewer === null) throw new CommandError('no reviewer');
                if (i.reviewer === i.assignee) throw new CommandError('reviewer is assignee');
            }
            if (y === 'DONE' || y === 'RESOLVED') {
                const blockers = this.unfinishedBlockers(i);
                if (blockers.length) throw new CommandError(`blocked by ${blockers[0]}`);
            }
            if (y === 'READY' && i.estimate === null) throw new CommandError('no estimate');
            this.changeState(i, y);
            return;
        }
        case 'SHOW':
            this.emit('ISSUE', i.number, i.type, i.priority, i.state, 'blocked', yesNo(this.blocked(i)));
            this.emit('TITLE', i.title);
            this.emit('PEOPLE', 'assignee', display(i.assignee), 'reviewer', display(i.reviewer));
            this.emit('PLAN', 'estimate', display(i.estimate), 'sprint', display(i.sprint), 'comments', i.comments);
            this.emit('LINKS', 'blocks', numberList(i.blocks), 'blocked_by', numberList(i.blockers),
                'duplicate_of', display(i.duplicate), 'duplicated_by', numberList(i.duplicates));
            return;
        case 'HISTORY':
            this.emit('HISTORY', i.number, i.history.length);
            for (const entry of i.history) this.emit(entry);
            return;
        }
    }

    link(command, args) {
        const relation = args[1];
        if (command === 'UNLINK' ? relation !== 'BLOCKS' : !['BLOCKS', 'DUPLICATES'].includes(relation))
            throw new CommandError('bad link');
        const a = this.issue(args[0]);
        const b = this.issue(args[2]);
        if (command === 'UNLINK') {
            if (!a.blocks.has(b.number)) throw new CommandError('no link');
            const before = this.blockedStates([b.number]);
            a.blocks.delete(b.number);
            b.blockers.delete(a.number);
            this.record(a, `UNLINK BLOCKS ${b.number}`);
            this.record(b, `UNLINK BLOCKED_BY ${a.number}`);
            this.emit('UNLINK', a.number, 'BLOCKS', b.number);
            this.notify(before);
        } else {
            if (a === b) throw new CommandError('self link');
            if (relation === 'BLOCKS') {
                if (a.blocks.has(b.number)) throw new CommandError('link exists');
                if (this.reaches(b.number, a.number)) throw new CommandError('cycle');
                this.notDone(b);
                const before = this.blockedStates([b.number]);
                a.blocks.add(b.number);
                b.blockers.add(a.number);
                this.record(a, `LINK BLOCKS ${b.number}`);
                this.record(b, `LINK BLOCKED_BY ${a.number}`);
                this.emit('LINK', a.number, 'BLOCKS', b.number);
                this.notify(before);
            } else {
                if (a.type !== b.type) throw new CommandError('type mismatch');
                this.notDone(a);
                if (b.duplicate !== null) throw new CommandError('target is duplicate');
                a.duplicate = b.number;
                b.duplicates.add(a.number);
                this.record(a, `LINK DUPLICATES ${b.number}`);
                this.record(b, `LINK DUPLICATED_BY ${a.number}`);
                this.emit('LINK', a.number, 'DUPLICATES', b.number);
                this.changeState(a, a.type === 'BUG' ? 'CLOSED' : 'DONE');
                if (a.sprint !== null && this.sprints.get(a.sprint).phase !== 'ENDED') {
                    this.record(a, `SPRINT REMOVE ${a.sprint}`);
                    a.sprint = null;
                }
            }
        }
    }

    sprintCommand(args) {
        const [operation, name, issueNumber] = args;
        if (operation === 'NEW') {
            if (this.sprints.has(name)) throw new CommandError('sprint exists');
            this.sprints.set(name, new Sprint(name));
            this.emit('SPRINT', 'NEW', name);
            return;
        }
        const s = this.sprint(name);
        if (operation === 'ADD' || operation === 'REMOVE') {
            const i = this.issue(issueNumber);
            if (s.phase === 'ENDED') throw new CommandError('sprint ended');
            if (operation === 'ADD') {
                this.notDone(i);
                if (i.sprint !== null && this.sprints.get(i.sprint).phase !== 'ENDED') throw new CommandError(`in sprint ${i.sprint}`);
                if (i.state === 'BACKLOG') throw new CommandError('not ready');
                i.sprint = name;
            } else {
                if (i.sprint !== name) throw new CommandError('not in sprint');
                this.notDone(i);
                i.sprint = null;
            }
            this.record(i, `SPRINT ${operation} ${name}`);
            this.emit('SPRINT', operation, name, i.number, this.summary(s));
        } else if (operation === 'START') {
            if (s.phase !== 'PLANNED') throw new CommandError('sprint not planned');
            const active = this.active();
            if (active) throw new CommandError(`sprint active ${active.name}`);
            if (this.members(s).length === 0) throw new CommandError('sprint empty');
            s.phase = 'ACTIVE';
            s.start = this.day;
            const remaining = this.remaining(s);
            s.records.set(this.day, remaining);
            this.emit('SPRINT', 'START', name, 'day', this.day, this.summary(s), 'remaining', remaining);
        } else {
            if (s.phase !== 'ACTIVE') throw new CommandError('sprint not active');
            s.records.set(this.day, this.remaining(s));
            const members = this.members(s);
            const done = members.filter(i => i.done());
            const returned = members.filter(i => !i.done());
            s.velocity = done.reduce((sum, i) => sum + i.points(), 0);
            s.phase = 'ENDED';
            s.end = this.day;
            this.emit('SPRINT', 'END', name, 'day', this.day, 'velocity', s.velocity, 'done', done.length, 'returned', returned.length);
            for (const i of returned) {
                i.sprint = null;
                this.record(i, `SPRINT RETURN ${name}`);
                this.emit('RETURNED', i.number);
            }
        }
    }
}

const lines = fs.readFileSync(0, 'utf8').split(/\r?\n/);
const tracker = new Tracker();
const output = [];
for (let i = 1; i <= Number(lines[0]); ++i) output.push(...tracker.execute(lines[i]));
process.stdout.write(output.join('\n') + '\n');
