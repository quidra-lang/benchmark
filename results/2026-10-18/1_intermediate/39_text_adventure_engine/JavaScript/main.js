'use strict';

const fs = require('node:fs');
const directions = ['north', 'south', 'east', 'west', 'up', 'down'];
const directionWords = new Map(directions.flatMap(direction => [[direction, direction], [direction[0], direction]]));
const verbs = new Map([
    ['go', 'go walk run'], ['look', 'look l'], ['examine', 'examine x inspect read'], ['take', 'take get grab'],
    ['drop', 'drop discard'], ['put', 'put insert place'], ['inventory', 'inventory inv i'], ['open', 'open'],
    ['close', 'close shut'], ['unlock', 'unlock'], ['lock', 'lock'], ['use', 'use apply'], ['light', 'light ignite'],
    ['extinguish', 'extinguish douse snuff'], ['wait', 'wait z'], ['score', 'score'], ['save', 'save'],
    ['restore', 'restore load'], ['verbose', 'verbose'], ['brief', 'brief'],
].flatMap(([verb, synonyms]) => synonyms.split(' ').map(word => [word, verb])));
const noObjects = new Set(['look', 'inventory', 'wait', 'score', 'save', 'restore', 'verbose', 'brief']);
const actions = new Set(['go', 'take', 'drop', 'put', 'open', 'close', 'unlock', 'lock', 'use', 'light', 'extinguish', 'wait']);
const normalize = line => line.toLowerCase().split(/ +/).filter(word => !['the', 'a', 'an'].includes(word));
const floor = id => ({ kind: 'room', id });
const inside = id => ({ kind: 'inside', id });
const player = () => ({ kind: 'player' });
const nowhere = () => ({ kind: 'nowhere' });
const samePlace = (first, second) => first.kind === second.kind && first.id === second.id;
const placeKey = place => `${place.kind}:${place.id ?? ''}`;
class Failure extends Error {
    constructor(lines) { super(); this.lines = Array.isArray(lines) ? lines : [lines]; }
}
const fail = lines => { throw new Failure(lines); };

class Adventure {
    constructor(lines) {
        this.rooms = new Map(); this.items = new Map(); this.rules = []; this.enterRules = [];
        this.state = { room: null, items: new Map(), exits: new Map(), flags: new Set(), bonus: 0, moves: 0,
            visited: new Set(), darkness: 0, ended: 'none' };
        this.it = null; this.previous = null; this.verbose = false; this.saved = null;
        for (const line of lines) this.define(line);
        this.state.visited.add(this.state.room);
        this.ids = [...this.items.keys()].sort();
        this.vocabulary = new Set([...this.items.values()].flatMap(item => [...item.nouns, ...item.words]));
    }
    define(line) {
        const words = line.split(' '), [kind, id] = words;
        switch (kind) {
            case 'ROOM': {
                const dark = words[2] === 'DARK';
                this.rooms.set(id, { dark, name: words.slice(dark ? 3 : 2).join(' '), description: [] });
                break;
            }
            case 'DESC': this.rooms.get(id).description.push(words.slice(2).join(' ')); break;
            case 'EXIT': this.setExit(id, words[2], words[3], words[4] === 'LOCKED' ? words[5] : null); break;
            case 'ITEM': {
                const item = { id, weight: Number(words[3]), points: 0, light: false, capacity: null, key: null,
                    fixed: false, nouns: new Set([id]), details: [] };
                const state = { place: words[2] === 'PLAYER' ? player() : words[2] === 'NOWHERE' ? nowhere() : floor(words[2]),
                    container: 'open', lit: false, fuel: 0 };
                let index = 4;
                if (words[index] === 'TREASURE') { item.points = Number(words[index + 1]); index += 2; }
                if (words[index] === 'LIGHT') { item.light = true; state.fuel = Number(words[index + 1]); index += 2; }
                if (words[index] === 'CONTAINER') {
                    item.capacity = Number(words[index + 1]); index += 2;
                    if (words[index] === 'CLOSED') { state.container = 'closed'; ++index; }
                    if (words[index] === 'LOCKED') { item.key = words[index + 1]; state.container = 'locked'; index += 2; }
                }
                if (words[index] === 'FIXED') { item.fixed = true; ++index; }
                item.name = words.slice(index).join(' '); item.words = new Set(words.slice(index));
                this.items.set(id, item); this.state.items.set(id, state);
                break;
            }
            case 'INSIDE': this.state.items.get(id).place = inside(words[2]); break;
            case 'ALIAS': this.items.get(id).nouns.add(words[2]); break;
            case 'DETAIL': this.items.get(id).details.push(words.slice(2).join(' ')); break;
            case 'RULE': case 'ENTER': {
                let index = kind === 'RULE' ? 3 : 2, condition = null;
                if (words[index] === 'IF' || words[index] === 'UNLESS') {
                    condition = { flag: words[index + 1], on: words[index] === 'IF' }; index += 2;
                }
                const rule = { first: id, second: kind === 'RULE' ? words[2] : null, condition, effect: words.slice(index) };
                (kind === 'RULE' ? this.rules : this.enterRules).push(rule);
                break;
            }
            case 'TROPHY': this.trophy = id; break;
            case 'START': this.state.room = id; break;
            case 'MAXWEIGHT': this.maxWeight = Number(id); break;
        }
    }
    setExit(room, direction, destination, key = null) {
        if (!this.state.exits.has(room)) this.state.exits.set(room, new Map());
        this.state.exits.get(room).set(direction, { destination, key, locked: key !== null });
    }
    contents(place) { return this.ids.filter(id => samePlace(this.state.items.get(id).place, place)); }
    children() {
        const result = new Map();
        for (const id of this.ids) {
            const key = placeKey(this.state.items.get(id).place);
            if (!result.has(key)) result.set(key, []);
            result.get(key).push(id);
        }
        return result;
    }
    isOpen(id) { return this.items.get(id).capacity !== null && this.state.items.get(id).container === 'open'; }
    reachable(place) {
        const result = new Set(), children = this.children();
        const visit = place => {
            for (const id of children.get(placeKey(place)) ?? []) {
                result.add(id);
                if (this.isOpen(id)) visit(inside(id));
            }
        };
        visit(place);
        return result;
    }
    carried() { return this.reachable(player()); }
    roomItems() { return this.reachable(floor(this.state.room)); }
    isLit() {
        return !this.rooms.get(this.state.room).dark || [...this.carried(), ...this.roomItems()].some(id => this.state.items.get(id).lit);
    }
    visible() { return this.isLit() ? new Set([...this.carried(), ...this.roomItems()]) : this.carried(); }
    weights() {
        const result = new Map(), children = this.children();
        const total = id => {
            if (!result.has(id)) result.set(id, this.items.get(id).weight +
                (children.get(placeKey(inside(id))) ?? []).reduce((weight, child) => weight + total(child), 0));
            return result.get(id);
        };
        for (const id of this.ids) total(id);
        return result;
    }
    totalWeight(id) { return this.weights().get(id); }
    contentWeight(id) { return this.totalWeight(id) - this.items.get(id).weight; }
    carriedWeight() { const weights = this.weights(); return this.contents(player()).reduce((weight, id) => weight + weights.get(id), 0); }
    nestedIn(id, ancestor) {
        let place = this.state.items.get(id).place;
        while (place.kind === 'inside') {
            if (place.id === ancestor) return true;
            place = this.state.items.get(place.id).place;
        }
        return false;
    }
    score() {
        let stored = 0, treasures = 0, points = 0;
        for (const id of this.ids) if (this.items.get(id).points > 0) {
            ++treasures;
            let place = this.state.items.get(id).place;
            while (place.kind === 'inside') place = this.state.items.get(place.id).place;
            if (samePlace(place, floor(this.trophy))) { ++stored; points += this.items.get(id).points; }
        }
        return { stored, treasures, points, total: points + this.state.bonus };
    }
    display(id) {
        const item = this.items.get(id), state = this.state.items.get(id), annotations = [];
        if (item.capacity !== null) annotations.push(state.container);
        if (item.light && state.lit) annotations.push('lit');
        return item.name + (annotations.length ? ` (${annotations.join(', ')})` : '');
    }
    tree(place, depth = 1, children = this.children()) {
        const rows = [];
        for (const id of children.get(placeKey(place)) ?? []) {
            rows.push('  '.repeat(depth) + this.display(id));
            if (this.isOpen(id)) rows.push(...this.tree(inside(id), depth + 1, children));
        }
        return rows;
    }
    describe(full = true) {
        if (!this.isLit()) return ['It is pitch dark.'];
        const room = this.rooms.get(this.state.room), exits = this.state.exits.get(this.state.room), names = [];
        for (const direction of directions) if (exits?.has(direction)) names.push(direction + (exits.get(direction).locked ? ' (locked)' : ''));
        const rows = [room.name, ...(full ? room.description : []), 'Exits: ' + (names.length ? names.join(', ') : 'none')];
        if (this.contents(floor(this.state.room)).length) rows.push('You see:', ...this.tree(floor(this.state.room)));
        return rows;
    }
    resolve(phrase) {
        const visible = this.visible();
        if (phrase.length === 1 && phrase[0] === 'it') {
            if (this.it === null) fail('I don\'t know what "it" refers to.');
            if (!visible.has(this.it)) fail("You can't see any such thing.");
            return this.it;
        }
        for (const word of phrase) if (!this.vocabulary.has(word)) fail(`I don't know the word "${word}".`);
        const matches = this.ids.filter(id => visible.has(id) && this.items.get(id).nouns.has(phrase.at(-1)) &&
            phrase.slice(0, -1).every(word => this.items.get(id).words.has(word)));
        if (!matches.length) fail("You can't see any such thing.");
        if (matches.length > 1) fail(`Which do you mean: ${matches.map(id => this.items.get(id).name).join(', ')}?`);
        this.it = matches[0];
        return matches[0];
    }
    runRules(rules) {
        const rows = [];
        let executed = 0;
        for (const rule of rules) {
            if (rule.condition && this.state.flags.has(rule.condition.flag) !== rule.condition.on) continue;
            ++executed;
            const [effect, first, second, third] = rule.effect;
            switch (effect) {
                case 'MESSAGE': rows.push(rule.effect.slice(1).join(' ')); break;
                case 'OPEN': this.setExit(first, second, third); break;
                case 'REMOVE': this.state.items.get(first).place = nowhere(); break;
                case 'ADD': this.state.items.get(first).place = floor(second); break;
                case 'SET': this.state.flags.add(first); break;
                case 'CLEAR': this.state.flags.delete(first); break;
                case 'POINTS': this.state.bonus += Number(first); break;
            }
        }
        return { rows, executed };
    }
    requireContainer(id) {
        const name = this.items.get(id).name;
        if (this.items.get(id).capacity === null) fail(`The ${name} is not a container.`);
        if (!this.isOpen(id)) fail(`The ${name} is closed.`);
    }
    take(first, second) {
        if (!this.isLit()) fail('It is pitch dark.');
        let container = null, source = floor(this.state.room);
        if (second !== null) { container = this.resolve(second); this.requireContainer(container); source = inside(container); }
        if (first.length === 1 && first[0] === 'all') {
            const candidates = this.contents(source).filter(id => !this.items.get(id).fixed), rows = [];
            if (!candidates.length) fail(container === null ? 'There is nothing here to take.' : `There is nothing in the ${this.items.get(container).name} to take.`);
            let taken = false;
            for (const id of candidates) {
                let outcome = "You can't carry any more.";
                if (this.carried().has(id) || this.carriedWeight() + this.totalWeight(id) <= this.maxWeight) {
                    this.state.items.get(id).place = player(); outcome = 'Taken.'; taken = true;
                }
                rows.push(`${this.items.get(id).name}: ${outcome}`);
            }
            if (!taken) fail(rows);
            return rows;
        }
        const id = this.resolve(first), item = this.items.get(id), state = this.state.items.get(id);
        if (container !== null && !samePlace(state.place, source)) fail(`The ${item.name} is not in the ${this.items.get(container).name}.`);
        if (state.place.kind === 'player') fail(`You already have the ${item.name}.`);
        if (item.fixed) fail(`The ${item.name} is fixed in place.`);
        if (!this.carried().has(id) && this.carriedWeight() + this.totalWeight(id) > this.maxWeight) fail("You can't carry any more.");
        state.place = player();
        return ['Taken.'];
    }
    drop(first) {
        if (first.length === 1 && first[0] === 'all') {
            const candidates = this.contents(player());
            if (!candidates.length) fail('You are empty-handed.');
            return candidates.map(id => { this.state.items.get(id).place = floor(this.state.room); return `${this.items.get(id).name}: Dropped.`; });
        }
        const id = this.resolve(first);
        if (!this.carried().has(id)) fail(`You aren't carrying the ${this.items.get(id).name}.`);
        this.state.items.get(id).place = floor(this.state.room);
        return ['Dropped.'];
    }
    putItem(id, container) {
        const item = this.items.get(id), target = this.items.get(container), state = this.state.items.get(id);
        if (this.nestedIn(container, id)) return `The ${target.name} is inside the ${item.name}.`;
        if (samePlace(state.place, inside(container))) return `The ${item.name} is already in the ${target.name}.`;
        const weight = this.contentWeight(container) + (this.nestedIn(id, container) ? 0 : this.totalWeight(id));
        if (weight > target.capacity) return `The ${item.name} doesn't fit in the ${target.name}.`;
        state.place = inside(container);
        return null;
    }
    put(first, second) {
        if (first.length === 1 && first[0] === 'all') {
            const target = this.resolve(second); this.requireContainer(target);
            const candidates = this.contents(player()).filter(id => id !== target), rows = [];
            if (!candidates.length) fail(`You have nothing to put in the ${this.items.get(target).name}.`);
            let succeeded = false;
            for (const id of candidates) {
                const reason = this.putItem(id, target);
                if (reason === null) succeeded = true;
                rows.push(`${this.items.get(id).name}: ${reason ?? 'Done.'}`);
            }
            if (!succeeded) fail(rows);
            return rows;
        }
        const id = this.resolve(first), target = this.resolve(second), item = this.items.get(id);
        if (!this.carried().has(id)) fail(`You aren't carrying the ${item.name}.`);
        if (id === target) fail(`You can't put the ${item.name} inside itself.`);
        this.requireContainer(target);
        const reason = this.putItem(id, target);
        if (reason !== null) fail(reason);
        return [`You put the ${item.name} in the ${this.items.get(target).name}.`];
    }
    keyCheck(key, phrase) {
        if (phrase !== null) {
            const id = this.resolve(phrase), name = this.items.get(id).name;
            if (!this.carried().has(id)) fail(`You aren't carrying the ${name}.`);
            if (id !== key) fail(`The ${name} doesn't fit.`);
            return [];
        }
        if (!this.carried().has(key)) fail("You don't have the right key.");
        return [`(with the ${this.items.get(key).name})`];
    }
    lock(first, second, locking) {
        const direction = first.length === 1 ? directionWords.get(first[0]) : undefined;
        if (direction !== undefined) {
            const exit = this.state.exits.get(this.state.room)?.get(direction);
            if (exit === undefined) fail(`There is no exit ${direction}.`);
            if (exit.key === null) fail(`The way ${direction} has no lock.`);
            if (exit.locked === locking) fail(`The way ${direction} is ${locking ? 'already locked' : 'not locked'}.`);
            const rows = this.keyCheck(exit.key, second);
            exit.locked = locking;
            const opposite = directions[directions.indexOf(direction) ^ 1], back = this.state.exits.get(exit.destination)?.get(opposite);
            if (back?.destination === this.state.room && back.key === exit.key) back.locked = locking;
            return [...rows, locking ? 'Locked.' : 'Unlocked.'];
        }
        const id = this.resolve(first), item = this.items.get(id), state = this.state.items.get(id);
        if (item.capacity === null || item.key === null) fail(`The ${item.name} has no lock.`);
        if ((state.container === 'locked') === locking) fail(`The ${item.name} is ${locking ? 'already locked' : 'not locked'}.`);
        if (locking && state.container === 'open') fail(`You must close the ${item.name} first.`);
        const rows = this.keyCheck(item.key, second);
        state.container = locking ? 'locked' : 'closed';
        return [...rows, locking ? 'Locked.' : 'Unlocked.'];
    }
    execute(verb, first, second) {
        switch (verb) {
            case 'look': return this.describe();
            case 'inventory':
                return this.contents(player()).length ? ['You are carrying:', ...this.tree(player()), `Total weight: ${this.carriedWeight()}/${this.maxWeight}`] : ['You are empty-handed.'];
            case 'wait': return ['Time passes.'];
            case 'score': {
                const score = this.score();
                return [`You have scored ${score.total} points (treasure ${score.points}, bonus ${this.state.bonus}) in ${this.state.moves} moves.`,
                    `Treasures stored: ${score.stored} of ${score.treasures}.`];
            }
            case 'save': this.saved = structuredClone(this.state); return ['Game saved.'];
            case 'restore':
                if (this.saved === null) fail('There is no saved game.');
                this.state = structuredClone(this.saved);
                return ['Game restored.', ...this.describe()];
            case 'verbose': this.verbose = true; return ['Verbose mode.'];
            case 'brief': this.verbose = false; return ['Brief mode.'];
            case 'take': return this.take(first, second);
            case 'drop': return this.drop(first);
            case 'put': return this.put(first, second);
            case 'unlock': case 'lock': return this.lock(first, second, verb === 'lock');
            case 'use': {
                const id = this.resolve(first), target = this.resolve(second);
                if (!this.carried().has(id)) fail(`You aren't carrying the ${this.items.get(id).name}.`);
                const result = this.runRules(this.rules.filter(rule => rule.first === id && rule.second === target));
                if (!result.executed) fail('Nothing happens.');
                return result.rows.length ? result.rows : ['Done.'];
            }
        }
        const id = this.resolve(first), item = this.items.get(id), state = this.state.items.get(id);
        switch (verb) {
            case 'examine': {
                const rows = item.details.length ? item.details.slice() : [`You see nothing special about the ${item.name}.`];
                if (item.light) rows.push(`It is ${state.lit ? 'lit' : 'unlit'} (fuel ${state.fuel}).`);
                if (item.capacity !== null) {
                    if (state.container !== 'open') rows.push(`It is ${state.container}.`);
                    else if (this.contents(inside(id)).length) rows.push('It contains:', ...this.tree(inside(id)));
                    else rows.push('It is empty.');
                }
                if (item.points > 0) rows.push(`It is a treasure worth ${item.points} points.`);
                rows.push(`It weighs ${this.totalWeight(id)}.`);
                return rows;
            }
            case 'open': {
                if (item.capacity === null) fail(`You can't open the ${item.name}.`);
                if (state.container === 'open') fail(`The ${item.name} is already open.`);
                if (state.container === 'locked') fail(`The ${item.name} is locked.`);
                state.container = 'open';
                const contents = this.contents(inside(id));
                return contents.length ? [`Opening the ${item.name} reveals ${contents.map(child => this.items.get(child).name).join(', ')}.`] : ['Opened.'];
            }
            case 'close':
                if (item.capacity === null) fail(`You can't close the ${item.name}.`);
                if (state.container !== 'open') fail(`The ${item.name} is already closed.`);
                state.container = 'closed';
                return ['Closed.'];
            case 'light':
                if (!item.light) fail(`You can't light the ${item.name}.`);
                if (state.lit) fail(`The ${item.name} is already lit.`);
                if (state.fuel === 0) fail(`The ${item.name} has no fuel.`);
                state.lit = true;
                return [`The ${item.name} is now lit.`];
            case 'extinguish':
                if (!item.light) fail(`You can't extinguish the ${item.name}.`);
                if (!state.lit) fail(`The ${item.name} is not lit.`);
                state.lit = false;
                return [`The ${item.name} is now out.`];
        }
    }
    endTurn(baseline) {
        const rows = [], nearby = new Set([...this.carried(), ...this.roomItems()]);
        ++this.state.moves;
        for (const id of this.ids) {
            const state = this.state.items.get(id);
            if (state.lit && --state.fuel === 0) {
                state.lit = false;
                if (nearby.has(id)) rows.push(`The ${this.items.get(id).name} goes out.`);
            }
        }
        const lit = this.isLit();
        if (baseline && !lit) rows.push('It is now pitch dark.');
        else if (!baseline && lit) rows.push(...this.describe());
        this.state.darkness = lit ? 0 : this.state.darkness + 1;
        if (this.state.darkness === 2) rows.push('You hear something moving in the dark.');
        if (this.state.darkness === 3) this.state.ended = 'dead';
        const score = this.score();
        if (this.state.ended === 'none' && score.treasures > 0 && score.stored === score.treasures) this.state.ended = 'won';
        if (this.state.ended !== 'none') {
            rows.push(this.state.ended === 'dead' ? '*** You have died ***' : '*** You have won ***');
            rows.push(`You scored ${score.total} points in ${this.state.moves} moves.`);
        }
        return rows;
    }
    interpret(line) {
        let words = normalize(line);
        if (!words.length) fail('I beg your pardon?');
        if (directionWords.has(words[0])) words = ['go', ...words];
        let verb = verbs.get(words[0]), rest = words.slice(1);
        if (verb === undefined) fail(`I don't know the verb "${words[0]}".`);
        if (this.state.ended !== 'none' && verb !== 'restore') fail('The game is over.');
        if (verb === 'look' && rest.length) {
            if (rest[0] !== 'at') fail("I don't understand that.");
            verb = 'examine'; rest = rest.slice(1);
        }
        let first = rest, second = null;
        if (noObjects.has(verb)) {
            if (rest.length) fail("I don't understand that.");
        } else {
            if (!rest.length) fail(verb === 'go' ? 'Which way do you want to go?' : `What do you want to ${verb}?`);
            if (verb === 'go') {
                if (rest.length !== 1 || !directionWords.has(rest[0])) fail("I don't understand that.");
            } else {
                let prepositions = [];
                if (verb === 'put') prepositions = ['in', 'into'];
                else if (verb === 'use') prepositions = ['on', 'with'];
                else if ((verb === 'unlock' || verb === 'lock') && rest.includes('with')) prepositions = ['with'];
                else if (verb === 'take' && rest.includes('from')) prepositions = ['from'];
                if (prepositions.length) {
                    const index = rest.findIndex(word => prepositions.includes(word));
                    if (index <= 0 || index === rest.length - 1) fail("I don't understand that.");
                    first = rest.slice(0, index); second = rest.slice(index + 1);
                }
            }
        }
        let baseline = this.isLit(), rows;
        if (verb === 'go') {
            const direction = directionWords.get(rest[0]), exit = this.state.exits.get(this.state.room)?.get(direction);
            if (exit === undefined) fail("You can't go that way.");
            if (exit.locked) fail(`The way ${direction} is locked.`);
            this.state.room = exit.destination;
            baseline = this.isLit();
            rows = this.describe(this.verbose || !this.state.visited.has(this.state.room));
            this.state.visited.add(this.state.room);
            rows.push(...this.runRules(this.enterRules.filter(rule => rule.first === this.state.room)).rows);
        } else rows = this.execute(verb, first, second);
        if (actions.has(verb)) rows.push(...this.endTurn(baseline));
        return rows;
    }
    command(line) {
        try {
            const words = normalize(line);
            if (words[0] === 'again' || words[0] === 'g') {
                if (words.length !== 1) fail("I don't understand that.");
                if (this.previous === null) fail('There is nothing to repeat.');
                return this.interpret(this.previous);
            }
            this.previous = line;
            return this.interpret(line);
        } catch (error) {
            if (!(error instanceof Failure)) throw error;
            return error.lines;
        }
    }
}

const input = fs.readFileSync(0, 'utf8').trimEnd().split(/\r?\n/), start = input.indexOf('BEGIN');
const adventure = new Adventure(input.slice(0, start));
const write = rows => process.stdout.write(rows.join('\n') + '\n');
write(adventure.describe());
for (const line of input.slice(start + 1)) {
    if (line === 'QUIT') {
        write([`Final score: ${adventure.score().total} points in ${adventure.state.moves} moves.`]);
        break;
    }
    write(['> ' + line, ...adventure.command(line)]);
}
