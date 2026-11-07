const fs = require('node:fs');

const SCALE = 2 ** 37;
const SEX_INDEX = { M: 0, F: 1, X: 2 };
const ORDINALS = ['first', 'second', 'third', 'fourth', 'fifth',
    'sixth', 'seventh', 'eighth', 'ninth', 'tenth'];
const TERMS = {
    parent: ['father', 'mother', 'parent'],
    child: ['son', 'daughter', 'child'],
    sibling: ['brother', 'sister', 'sibling'],
    pibling: ['uncle', 'aunt', 'pibling'],
    nibling: ['nephew', 'niece', 'nibling'],
    spouse: ['husband', 'wife', 'spouse'],
    late: ['late husband', 'late wife', 'late spouse'],
    survivor: ['widower', 'widow', 'surviving spouse'],
    ex: ['ex-husband', 'ex-wife', 'ex-spouse'],
    stepparent: ['stepfather', 'stepmother', 'stepparent'],
    stepchild: ['stepson', 'stepdaughter', 'stepchild'],
    stepsibling: ['stepbrother', 'stepsister', 'stepsibling'],
    stepgrandparent: ['stepgrandfather', 'stepgrandmother', 'stepgrandparent'],
    stepgrandchild: ['stepgrandson', 'stepgranddaughter', 'stepgrandchild'],
    parentInLaw: ['father-in-law', 'mother-in-law', 'parent-in-law'],
    childInLaw: ['son-in-law', 'daughter-in-law', 'child-in-law'],
    siblingInLaw: ['brother-in-law', 'sister-in-law', 'sibling-in-law'],
};
const STEPS = {
    parent: ['parent', null], father: ['parent', 'M'], mother: ['parent', 'F'],
    child: ['child', null], son: ['child', 'M'], daughter: ['child', 'F'],
    sibling: ['sibling', null], brother: ['sibling', 'M'], sister: ['sibling', 'F'],
    spouse: ['spouse', null], husband: ['spouse', 'M'], wife: ['spouse', 'F'],
};
const MODIFYING = new Set(['PERSON', 'DEATH', 'REMOVE', 'PARENT', 'UNPARENT', 'SPOUSE', 'DIVORCE']);

class CommandError extends Error {}

function compareIds(a, b) {
    return a < b ? -1 : a > b ? 1 : 0;
}

function gendered(kind, sex) {
    return TERMS[kind][SEX_INDEX[sex]];
}

function generationPrefix(g) {
    return g === 1 ? '' : 'great-'.repeat(g - 2) + 'grand';
}

function term(da, db, sex) {
    if (da === 0 && db === 0) return 'self';
    if (da === 0) return generationPrefix(db) + gendered('parent', sex);
    if (db === 0) return generationPrefix(da) + gendered('child', sex);
    if (da === 1 && db === 1) return gendered('sibling', sex);
    if (da === 1) return generationPrefix(db - 1) + gendered('pibling', sex);
    if (db === 1) return generationPrefix(da - 1) + gendered('nibling', sex);
    const k = Math.min(da, db) - 1;
    const suffix = [11, 12, 13].includes(k % 100) ? 'th'
        : ({ 1: 'st', 2: 'nd', 3: 'rd' }[k % 10] ?? 'th');
    const ordinal = k <= 10 ? ORDINALS[k - 1] : `${k}${suffix}`;
    const r = Math.abs(da - db);
    const removed = r === 0 ? '' : r === 1 ? ' once removed'
        : r === 2 ? ' twice removed' : ` ${r} times removed`;
    return `${ordinal} cousin${removed}`;
}

function bloodTerm(apex, sex) {
    const prefix = apex.shares === 1 ? 'half-' : apex.shares >= 4 ? 'double ' : '';
    return prefix + term(apex.da, apex.db, sex);
}

function life(person) {
    return `${person.birth}-${person.death ?? ''}`;
}

function fraction(value) {
    let a = value;
    let b = SCALE;
    while (b !== 0) [a, b] = [b, a % b];
    return `${value / a}/${SCALE / a}`;
}

function contains(record, x) {
    return record.first === x || record.second === x;
}

function other(record, x) {
    return record.first === x ? record.second : record.first;
}

class Family {
    persons = new Map();
    marriages = [];
    distanceCache = new Map();
    coefficientCache = new Map();

    copy() {
        const family = new Family();
        family.persons = new Map([...this.persons].map(([x, p]) =>
            [x, { ...p, parents: [...p.parents] }]));
        family.marriages = this.marriages.map(m => ({ ...m }));
        return family;
    }

    invalidate() {
        this.distanceCache.clear();
        this.coefficientCache.clear();
    }

    person(x) {
        const person = this.persons.get(x);
        if (!person) throw new CommandError(`UNKNOWN PERSON ${x}`);
        return person;
    }

    ageCompare(a, b) {
        return this.person(a).birth - this.person(b).birth || compareIds(a, b);
    }

    ageOrder(ids) {
        return [...ids].sort((a, b) => this.ageCompare(a, b));
    }

    personList(ids) {
        return this.ageOrder(ids).join(' ') || '-';
    }

    parents(x) {
        return this.person(x).parents;
    }

    children(x) {
        return [...this.persons.keys()].filter(y => this.parents(y).includes(x));
    }

    commonParents(a, b) {
        return this.parents(a).filter(p => this.parents(b).includes(p)).length;
    }

    areSiblings(a, b) {
        return a !== b && this.commonParents(a, b) > 0;
    }

    siblings(x) {
        return [...this.persons.keys()].filter(y => this.areSiblings(x, y));
    }

    records(x) {
        return this.marriages.filter(m => contains(m, x));
    }

    current(x) {
        return this.marriages.find(m => m.status === 'current' && contains(m, x));
    }

    spouse(x) {
        const record = this.current(x);
        return record ? other(record, x) : null;
    }

    last(a, b) {
        return this.marriages.findLast(m => contains(m, a) && contains(m, b));
    }

    partners(x) {
        const latest = new Map(this.records(x).map(m => [other(m, x), m]));
        return new Set([...latest].filter(([, m]) => m.status !== 'divorced').map(([y]) => y));
    }

    stepRelated(a, b) {
        return this.parents(a).some(p => this.parents(b).some(q => this.partners(p).has(q)));
    }

    distances(start, upward) {
        const key = `${upward}:${start}`;
        if (this.distanceCache.has(key)) return this.distanceCache.get(key);
        const distances = new Map([[start, 0]]);
        const queue = [start];
        for (let i = 0; i < queue.length; ++i) {
            const x = queue[i];
            for (const y of upward ? this.parents(x) : this.children(x)) {
                if (!distances.has(y)) {
                    distances.set(y, distances.get(x) + 1);
                    queue.push(y);
                }
            }
        }
        this.distanceCache.set(key, distances);
        return distances;
    }

    ancestor(a, b) {
        return a !== b && this.distances(b, true).has(a);
    }

    grandparents(x) {
        return [...this.distances(x, true)].filter(([, g]) => g === 2).map(([y]) => y);
    }

    apex(a, b) {
        const upA = this.distances(a, true);
        const upB = this.distances(b, true);
        if (upB.has(a)) return { person: a, da: 0, db: upB.get(a), shares: 0 };
        if (upA.has(b)) return { person: b, da: upA.get(b), db: 0, shares: 0 };
        const common = [...upA.keys()].filter(c => upB.has(c));
        common.sort((c, d) => (upA.get(c) + upB.get(c)) - (upA.get(d) + upB.get(d))
            || upA.get(c) - upA.get(d) || compareIds(c, d));
        if (common.length === 0) return null;
        const person = common[0];
        const da = upA.get(person);
        const db = upB.get(person);
        const shares = common.filter(c => upA.get(c) === da && upB.get(c) === db).length;
        return { person, da, db, shares };
    }

    relationship(a, b, sex = this.person(a).sex) {
        if (a === b) return ['self'];
        const terms = [];
        const apex = this.apex(a, b);
        if (apex) terms.push(bloodTerm(apex, sex));
        const record = this.last(a, b);
        if (!record) {
            if ([...this.persons.values()].some(p => p.parents.includes(a) && p.parents.includes(b)))
                terms.push('co-parent');
        } else if (record.status === 'current') terms.push(gendered('spouse', sex));
        else if (record.status === 'widowed')
            terms.push(gendered(record.died === a ? 'late' : 'survivor', sex));
        else terms.push(gendered('ex', sex));
        const pa = this.parents(a);
        const pb = this.parents(b);
        const qa = this.partners(a);
        const qb = this.partners(b);
        if (!pb.includes(a) && pb.some(p => qa.has(p))) terms.push(gendered('stepparent', sex));
        if (!pa.includes(b) && pa.some(p => qb.has(p))) terms.push(gendered('stepchild', sex));
        if (this.commonParents(a, b) === 0 && this.stepRelated(a, b))
            terms.push(gendered('stepsibling', sex));
        if (!this.ancestor(a, b) && this.grandparents(b).some(g => qa.has(g)))
            terms.push(gendered('stepgrandparent', sex));
        if (!this.ancestor(b, a) && this.grandparents(a).some(g => qb.has(g)))
            terms.push(gendered('stepgrandchild', sex));
        if ([...qb].some(q => this.parents(q).includes(a))) terms.push(gendered('parentInLaw', sex));
        if ([...qa].some(q => this.parents(q).includes(b))) terms.push(gendered('childInLaw', sex));
        if ([...qb].some(q => this.areSiblings(a, q)) || [...qa].some(q => this.areSiblings(q, b)))
            terms.push(gendered('siblingInLaw', sex));
        return terms;
    }

    relationshipText(a, b) {
        return this.relationship(a, b).join(', ') || 'no relation';
    }

    coefficient(a, b) {
        const key = [a, b].sort(compareIds).join(':');
        if (this.coefficientCache.has(key)) return this.coefficientCache.get(key);
        let value;
        if (a === b) value = (SCALE + this.inbreeding(a)) / 2;
        else {
            const [x, y] = this.person(a).birth >= this.person(b).birth ? [a, b] : [b, a];
            value = this.parents(x).reduce((sum, p) => sum + this.coefficient(p, y), 0) / 2;
        }
        this.coefficientCache.set(key, value);
        return value;
    }

    inbreeding(x) {
        const parents = this.parents(x);
        return parents.length === 2 ? this.coefficient(parents[0], parents[1]) : 0;
    }

    lineageLength(x, memo) {
        if (!memo.has(x)) memo.set(x, 1 + Math.max(0, ...this.parents(x).map(p => this.lineageLength(p, memo))));
        return memo.get(x);
    }
}

class Calculator {
    family = new Family();
    history = [];

    execute(line) {
        const [command, ...args] = line.split(' ');
        const saved = MODIFYING.has(command) ? this.family.copy() : null;
        try {
            const output = this.dispatch(command, args);
            if (saved) {
                this.history.push({ line, family: saved });
                this.family.invalidate();
            }
            return output;
        } catch (error) {
            if (!(error instanceof CommandError)) throw error;
            return [`ERROR ${error.message}`];
        }
    }

    dispatch(command, args) {
        const f = this.family;
        const [x, y] = args;
        const year = Number(args[2]);
        switch (command) {
        case 'PERSON': {
            if (f.persons.has(x)) throw new CommandError(`DUPLICATE PERSON ${x}`);
            f.persons.set(x, { sex: y, birth: year, name: args[3], death: null, parents: [] });
            return [`ADDED ${x} ${args[3]} ${y} ${year}`];
        }
        case 'DEATH': {
            const p = f.person(x);
            const death = Number(y);
            if (p.death !== null) throw new CommandError(`ALREADY DECEASED ${x}`);
            if (death < p.birth || f.records(x).some(m => death < m.start || (m.end !== null && death < m.end)))
                throw new CommandError(`BAD YEAR ${x}`);
            const late = f.children(x).filter(c => f.person(c).birth > death + 1).sort(compareIds);
            if (late.length) throw new CommandError(`AFTER DEATH ${late[0]} ${x}`);
            p.death = death;
            const record = f.current(x);
            if (!record) return [`DIED ${x} ${death}`];
            record.end = death;
            record.status = 'widowed';
            record.died = x;
            return [`DIED ${x} ${death} spouse=${other(record, x)}`];
        }
        case 'REMOVE':
            f.person(x);
            for (const p of f.persons.values()) p.parents = p.parents.filter(p => p !== x);
            f.marriages = f.marriages.filter(m => !contains(m, x));
            f.persons.delete(x);
            return [`REMOVED ${x}`];
        case 'PARENT': {
            const child = f.person(x);
            const parent = f.person(y);
            if (x === y) throw new CommandError(`SAME PERSON ${x}`);
            if (child.parents.includes(y)) throw new CommandError(`ALREADY PARENT ${x} ${y}`);
            if (child.parents.length === 2) throw new CommandError(`TOO MANY PARENTS ${x}`);
            if (f.ancestor(x, y)) throw new CommandError(`CYCLE ${x} ${y}`);
            if (parent.birth + 12 > child.birth) throw new CommandError(`AGE GAP ${x} ${y}`);
            if (parent.death !== null && parent.death + 1 < child.birth)
                throw new CommandError(`AFTER DEATH ${x} ${y}`);
            child.parents.push(y);
            return [`LINKED ${x} ${y} ${gendered('parent', parent.sex)}`];
        }
        case 'UNPARENT': {
            const child = f.person(x);
            f.person(y);
            if (!child.parents.includes(y)) throw new CommandError(`NOT PARENT ${x} ${y}`);
            child.parents = child.parents.filter(p => p !== y);
            return [`UNLINKED ${x} ${y}`];
        }
        case 'SPOUSE': {
            f.person(x);
            f.person(y);
            if (x === y) throw new CommandError(`SAME PERSON ${x}`);
            for (const a of [x, y]) if (f.person(a).death !== null) throw new CommandError(`DECEASED ${a}`);
            for (const a of [x, y]) if (f.spouse(a) !== null) throw new CommandError(`ALREADY MARRIED ${a}`);
            if (f.ancestor(x, y) || f.ancestor(y, x) || f.areSiblings(x, y))
                throw new CommandError(`CLOSE KIN ${x} ${y}`);
            for (const a of [x, y]) if (year < f.person(a).birth + 16) throw new CommandError(`TOO YOUNG ${a}`);
            for (const a of [x, y])
                if (f.records(a).some(m => m.end !== null && m.end >= year)) throw new CommandError(`BAD YEAR ${a}`);
            f.marriages.push({ first: x, second: y, start: year, end: null, status: 'current', died: null });
            return [`MARRIED ${x} ${y} ${year}`];
        }
        case 'DIVORCE': {
            f.person(x);
            f.person(y);
            if (f.spouse(x) !== y) throw new CommandError(`NOT MARRIED ${x} ${y}`);
            const record = f.current(x);
            if (year <= record.start) throw new CommandError(`BAD YEAR ${x}`);
            record.end = year;
            record.status = 'divorced';
            return [`DIVORCED ${x} ${y} ${year}`];
        }
        case 'UNDO': {
            const saved = this.history.pop();
            if (!saved) throw new CommandError('NOTHING TO UNDO');
            this.family = saved.family;
            return [`UNDONE ${saved.line}`];
        }
        case 'TERM':
            return [`TERM ${x} ${y} ${args[2]} ${term(Number(x), Number(y), args[2])}`];
        case 'STATS': {
            const people = [...f.persons.values()];
            const memo = new Map();
            return [`STATS persons=${people.length} living=${people.filter(p => p.death === null).length}`
                + ` links=${people.reduce((sum, p) => sum + p.parents.length, 0)}`
                + ` couples=${f.marriages.filter(m => m.status === 'current').length}`
                + ` founders=${people.filter(p => p.parents.length === 0).length}`
                + ` generations=${Math.max(0, ...[...f.persons.keys()].map(a => f.lineageLength(a, memo)))}`];
        }
        case 'AUDIT': {
            const lines = [];
            for (const m of f.marriages) {
                const apex = f.apex(m.first, m.second);
                if (apex) lines.push(`  marriage ${m.first} ${m.second} ${bloodTerm(apex, f.person(m.first).sex)}`);
            }
            for (const a of [...f.persons.keys()].sort(compareIds))
                if (f.inbreeding(a) !== 0) lines.push(`  inbred ${a} ${fraction(f.inbreeding(a))}`);
            return [`AUDIT ${lines.length}`, ...lines];
        }
        case 'CENSUS': {
            const censusYear = Number(x);
            const residents = f.ageOrder([...f.persons.keys()].filter(a => {
                const p = f.person(a);
                return p.birth <= censusYear && (p.death === null || p.death > censusYear);
            }));
            const lines = residents.map(a => {
                const m = f.records(a).findLast(m => m.start <= censusYear);
                const status = !m ? 'single' : m.end === null || m.end > censusYear
                    ? `married ${other(m, a)}` : m.status;
                return `  ${a} ${censusYear - f.person(a).birth} ${status}`;
            });
            return [`CENSUS ${censusYear} ${lines.length}`, ...lines];
        }
        }
        const person = f.person(x);
        if (['RELATION', 'PATH', 'COMMON', 'KINSHIP'].includes(command)) f.person(y);
        const ids = [...f.persons.keys()].sort(compareIds);
        switch (command) {
        case 'INFO':
            return [`INFO ${x} ${person.name} ${person.sex} ${life(person)}`,
                `  parents: ${f.personList(person.parents)}`,
                ...f.records(x).map(m => `  marriage: ${other(m, x)} ${m.start}-${m.end ?? ''} ${m.status}`),
                `  children: ${f.personList(f.children(x))}`,
                `  siblings: ${f.personList(f.siblings(x))}`,
                `  inbreeding: ${fraction(f.inbreeding(x))}`];
        case 'RELATION':
            return [`RELATION ${x} ${y}: ${f.relationshipText(x, y)}`];
        case 'KINSHIP':
            return [`KINSHIP ${x} ${y} ${fraction(f.coefficient(x, y))}`];
        case 'RELATIVES': {
            const lines = [];
            for (const a of ids) {
                if (a === x) continue;
                const terms = f.relationship(a, x);
                if (terms.length) lines.push(`  ${a}: ${terms.join(', ')}`);
            }
            return [`RELATIVES ${x} ${lines.length}`, ...lines];
        }
        case 'WHO': {
            const query = args.slice(1).join(' ');
            const lines = [];
            for (const a of ids) {
                if (a === x) continue;
                const terms = f.relationship(a, x);
                const neutral = f.relationship(a, x, 'X');
                const i = terms.findIndex((t, i) => t === query || neutral[i] === query);
                if (i >= 0) lines.push(`  ${a}: ${terms[i]}`);
            }
            return [`WHO ${x} ${query} ${lines.length}`, ...lines];
        }
        case 'PATH': {
            const apex = f.apex(x, y);
            if (!apex) return [`PATH ${x} ${y} none`];
            const apexPerson = apex.person;
            const depths = f.distances(apexPerson, false);
            function upward(start) {
                const path = [start];
                while (path.at(-1) !== apexPerson) {
                    const current = path.at(-1);
                    path.push(f.parents(current).filter(p => depths.get(p) === depths.get(current) - 1).sort(compareIds)[0]);
                }
                return path;
            }
            const route = [...upward(x), ...upward(y).slice(0, -1).reverse()];
            return [`PATH ${x} ${y} ${apex.da + apex.db}: ${route.join(' ')}`];
        }
        case 'COMMON': {
            const a = f.distances(x, true);
            const b = f.distances(y, true);
            const common = new Set([...a.keys()].filter(c => b.has(c)));
            const nearest = [...common].filter(c => !f.children(c).some(child => common.has(child)));
            nearest.sort((c, d) => (a.get(c) + b.get(c)) - (a.get(d) + b.get(d)) || compareIds(c, d));
            return [`COMMON ${x} ${y} ${nearest.length}`, ...nearest.map(c => `  ${c} ${a.get(c)} ${b.get(c)}`)];
        }
        case 'ANCESTORS':
        case 'DESCENDANTS': {
            const upward = command === 'ANCESTORS';
            const entries = [...f.distances(x, upward)].filter(([a]) => a !== x);
            entries.sort(([a, g], [b, h]) => g - h || compareIds(a, b));
            return [`${command} ${x} ${entries.length}`, ...entries.map(([a, g]) =>
                `  ${g} ${a} ${term(upward ? 0 : g, upward ? g : 0, f.person(a).sex)}`)];
        }
        case 'COUSINS': {
            const matches = [];
            for (const a of ids) {
                if (a === x) continue;
                const apex = f.apex(a, x);
                if (apex && apex.da >= 2 && apex.db >= 2 && Math.min(apex.da, apex.db) - 1 === Number(y))
                    matches.push({ id: a, apex });
            }
            matches.sort((a, b) => Math.abs(a.apex.da - a.apex.db) - Math.abs(b.apex.da - b.apex.db) || compareIds(a.id, b.id));
            return [`COUSINS ${x} ${y} ${matches.length}`, ...matches.map(a =>
                `  ${a.id} ${bloodTerm(a.apex, f.person(a.id).sex)}`)];
        }
        case 'SIBLINGS': {
            const lines = [];
            let earlier = 0;
            for (const a of f.ageOrder(ids)) {
                if (a === x) continue;
                const common = f.commonParents(x, a);
                const kind = common === 2 ? 'full' : common === 1 ? 'half' : f.stepRelated(x, a) ? 'step' : null;
                if (!kind) continue;
                if (common > 0 && f.ageCompare(a, x) < 0) ++earlier;
                lines.push(`  ${a} ${kind} ${f.person(a).birth}`);
            }
            return [`SIBLINGS ${x} ${lines.length} order=${earlier + 1}`, ...lines];
        }
        case 'GENERATIONS': {
            const groups = new Map();
            for (const [a, g] of f.distances(x, false)) {
                if (a === x) continue;
                if (!groups.has(g)) groups.set(g, []);
                groups.get(g).push(f.person(a));
            }
            const lines = [...groups].sort(([g], [h]) => g - h).map(([g, people]) => {
                const births = people.map(p => p.birth);
                return `  ${g} ${people.length} ${people.filter(p => p.death === null).length} ${Math.min(...births)}-${Math.max(...births)}`;
            });
            return [`GENERATIONS ${x} ${groups.size}`, ...lines];
        }
        case 'TREE': {
            const lines = [];
            const visited = new Set();
            function visit(a, depth) {
                const indent = ' '.repeat(2 * (depth + 1));
                if (visited.has(a)) { lines.push(`${indent}${a} (see above)`); return; }
                visited.add(a);
                const p = f.person(a);
                const spouse = f.spouse(a);
                lines.push(`${indent}${a} ${p.name} ${life(p)}${spouse === null ? '' : ` = ${spouse}`}`);
                for (const child of f.ageOrder(f.children(a))) visit(child, depth + 1);
            }
            visit(x, 0);
            return [`TREE ${x} ${f.distances(x, false).size - 1}`, ...lines];
        }
        case 'PEDIGREE': {
            const depth = Number(y);
            const lines = [];
            const entered = new Set();
            function enter(a, number, generation) {
                const p = f.person(a);
                lines.push(`${' '.repeat(2 * (generation + 1))}${number} ${a} ${p.name} ${life(p)}`);
                entered.add(a);
                if (generation >= depth) return;
                const parents = [...p.parents].sort((a, b) => SEX_INDEX[f.person(a).sex] - SEX_INDEX[f.person(b).sex] || compareIds(a, b));
                parents.forEach((parent, i) => enter(parent, 2 * number + i, generation + 1));
            }
            enter(x, 1, 0);
            return [`PEDIGREE ${x} ${y} entries=${lines.length} distinct=${entered.size}`, ...lines];
        }
        case 'TIMELINE': {
            const events = [{ year: person.birth, rank: 0, counterpart: '', text: 'born' }];
            for (const m of f.records(x)) {
                const a = other(m, x);
                events.push({ year: m.start, rank: 1, counterpart: a, text: `married ${a}` });
                if (m.status === 'divorced') events.push({ year: m.end, rank: 3, counterpart: a, text: `divorced ${a}` });
                else if (m.status === 'widowed' && m.died === a)
                    events.push({ year: m.end, rank: 4, counterpart: a, text: `widowed ${a}` });
            }
            for (const a of f.children(x)) events.push({ year: f.person(a).birth, rank: 2, counterpart: a, text: `child ${a}` });
            for (const [label, relatives] of [['parent', person.parents], ['child', f.children(x)]]) {
                for (const a of relatives) {
                    const death = f.person(a).death;
                    if (death !== null && death >= person.birth && (person.death === null || death <= person.death))
                        events.push({ year: death, rank: 5, counterpart: a, text: `lost ${label} ${a}` });
                }
            }
            if (person.death !== null) events.push({ year: person.death, rank: 6, counterpart: '', text: 'died' });
            events.sort((a, b) => a.year - b.year || a.rank - b.rank || compareIds(a.counterpart, b.counterpart));
            return [`TIMELINE ${x} ${events.length}`, ...events.map(e => `  ${e.year} ${e.text}`)];
        }
        case 'FIND': {
            let current = new Set([x]);
            for (const step of y.split('.')) {
                const [kind, sex] = STEPS[step];
                const next = new Set();
                for (const a of current) {
                    const targets = kind === 'parent' ? f.parents(a) : kind === 'child' ? f.children(a)
                        : kind === 'sibling' ? f.siblings(a) : f.spouse(a) === null ? [] : [f.spouse(a)];
                    for (const b of targets) if (sex === null || f.person(b).sex === sex) next.add(b);
                }
                current = next;
            }
            current.delete(x);
            return [`FIND ${x} ${y} ${current.size}`, ...[...current].sort(compareIds).map(a => `  ${a}: ${f.relationshipText(a, x)}`)];
        }
        }
    }
}

const lines = fs.readFileSync(0, 'utf8').split(/\r?\n/);
const calculator = new Calculator();
const output = [];
for (let i = 1; i <= Number(lines[0]); ++i) output.push(...calculator.execute(lines[i]));
process.stdout.write(output.join('\n') + '\n');
