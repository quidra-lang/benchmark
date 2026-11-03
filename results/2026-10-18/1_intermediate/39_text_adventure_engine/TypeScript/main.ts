import { readFileSync } from 'node:fs';

const directions = ['north', 'south', 'east', 'west', 'up', 'down'] as const;
type Direction = typeof directions[number];
const directionWords = new Map<string, Direction>();
for (const direction of directions) { directionWords.set(direction, direction); directionWords.set(direction[0], direction); }
const verbDefinitions = [
    ['go', 'go walk run'], ['look', 'look l'], ['examine', 'examine x inspect read'], ['take', 'take get grab'],
    ['drop', 'drop discard'], ['put', 'put insert place'], ['inventory', 'inventory inv i'], ['open', 'open'],
    ['close', 'close shut'], ['unlock', 'unlock'], ['lock', 'lock'], ['use', 'use apply'], ['light', 'light ignite'],
    ['extinguish', 'extinguish douse snuff'], ['wait', 'wait z'], ['score', 'score'], ['save', 'save'],
    ['restore', 'restore load'], ['verbose', 'verbose'], ['brief', 'brief'],
] as const;
type Verb = typeof verbDefinitions[number][0];
type NoObjectVerb = 'look' | 'inventory' | 'wait' | 'score' | 'save' | 'restore' | 'verbose' | 'brief';
type ItemVerb = 'examine' | 'open' | 'close' | 'light' | 'extinguish';
type Phrase = readonly string[];
type Command =
    | { readonly verb: NoObjectVerb }
    | { readonly verb: 'go'; readonly direction: Direction }
    | { readonly verb: ItemVerb | 'drop'; readonly target: Phrase }
    | { readonly verb: 'take'; readonly target: Phrase; readonly from: Phrase | null }
    | { readonly verb: 'put' | 'use'; readonly first: Phrase; readonly second: Phrase }
    | { readonly verb: 'lock' | 'unlock'; readonly target: Phrase; readonly key: Phrase | null };
const verbs = new Map<string, Verb>(verbDefinitions.flatMap(([verb, aliases]) => aliases.split(' ').map(word => [word, verb] as const)));
const noObjects: ReadonlySet<Verb> = new Set(['look', 'inventory', 'wait', 'score', 'save', 'restore', 'verbose', 'brief']);
const actions: ReadonlySet<Verb> = new Set(['go', 'take', 'drop', 'put', 'open', 'close', 'unlock', 'lock', 'use', 'light', 'extinguish', 'wait']);
const hasNoObjects = (verb: Verb): verb is NoObjectVerb => noObjects.has(verb);
const normalize = (line: string): string[] => line.toLowerCase().split(/ +/).filter(word => !['the', 'a', 'an'].includes(word));
const allItems = (phrase: Phrase): boolean => phrase.length === 1 && phrase[0] === 'all';

type Place = Readonly<{ kind: 'room' | 'inside'; id: string } | { kind: 'player' | 'nowhere' }>;
const floor = (id: string): Place => ({ kind: 'room', id });
const inside = (id: string): Place => ({ kind: 'inside', id });
const player: Place = { kind: 'player' };
const nowhere: Place = { kind: 'nowhere' };
const samePlace = (a: Place, b: Place): boolean => a.kind === b.kind && (!('id' in a) || ('id' in b && a.id === b.id));
const placeKey = (place: Place): string => `${place.kind}:${'id' in place ? place.id : ''}`;
interface Room { readonly name: string; readonly dark: boolean; readonly description: string[] }
interface Item {
    readonly id: string; readonly name: string; readonly weight: number; readonly points: number;
    readonly light: boolean; readonly capacity: number | null; readonly key: string | null; readonly fixed: boolean;
    readonly nouns: Set<string>; readonly words: ReadonlySet<string>; readonly details: string[];
}
interface ItemState { place: Place; container: 'open' | 'closed' | 'locked'; lit: boolean; fuel: number }
interface ExitLink { readonly destination: string; readonly key: string | null; locked: boolean }
interface GameState {
    room: string;
    readonly items: Map<string, ItemState>;
    readonly exits: Map<string, Map<Direction, ExitLink>>;
    readonly flags: Set<string>;
    bonus: number; moves: number; darkness: number; ended: 'none' | 'won' | 'dead';
    readonly visited: Set<string>;
}
interface Condition { readonly flag: string; readonly on: boolean }
type Effect = Readonly<
    { kind: 'message'; text: string } | { kind: 'open'; room: string; direction: Direction; destination: string } |
    { kind: 'move'; item: string; place: Place } | { kind: 'flag'; flag: string; on: boolean } | { kind: 'points'; amount: number }
>;
type Trigger = Readonly<{ kind: 'use'; first: string; second: string } | { kind: 'enter'; room: string }>;
interface Rule { readonly trigger: Trigger; readonly condition: Condition | null; readonly effect: Effect }
interface RuleResult { readonly rows: string[]; readonly executed: number }
interface Score { readonly stored: number; readonly treasures: number; readonly points: number; readonly total: number }
class Failure extends Error {
    readonly lines: readonly string[];
    constructor(lines: string | readonly string[]) { super(); this.lines = typeof lines === 'string' ? [lines] : lines.slice(); }
}
function fail(lines: string | readonly string[]): never { throw new Failure(lines); }

function readItem(words: readonly string[]): { item: Item; state: ItemState } {
    const id = words[1], weight = Number(words[3]);
    let points = 0, light = false, capacity: number | null = null, key: string | null = null, fixed = false, index = 4;
    const state: ItemState = {
        place: words[2] === 'PLAYER' ? player : words[2] === 'NOWHERE' ? nowhere : floor(words[2]),
        container: 'open', lit: false, fuel: 0,
    };
    if (words[index] === 'TREASURE') { points = Number(words[index + 1]); index += 2; }
    if (words[index] === 'LIGHT') { light = true; state.fuel = Number(words[index + 1]); index += 2; }
    if (words[index] === 'CONTAINER') {
        capacity = Number(words[index + 1]); index += 2;
        if (words[index] === 'CLOSED') { state.container = 'closed'; ++index; }
        if (words[index] === 'LOCKED') { key = words[index + 1]; state.container = 'locked'; index += 2; }
    }
    if (words[index] === 'FIXED') { fixed = true; ++index; }
    return { item: { id, weight, points, light, capacity, key, fixed, name: words.slice(index).join(' '),
        nouns: new Set([id]), words: new Set(words.slice(index)), details: [] }, state };
}
function readRule(words: readonly string[], index: number, trigger: Trigger): Rule {
    let condition: Condition | null = null;
    if (words[index] === 'IF' || words[index] === 'UNLESS') {
        condition = { flag: words[index + 1], on: words[index] === 'IF' }; index += 2;
    }
    const args = words.slice(index + 1);
    let effect: Effect;
    switch (words[index]) {
        case 'MESSAGE': effect = { kind: 'message', text: args.join(' ') }; break;
        case 'OPEN': effect = { kind: 'open', room: args[0], direction: directionWords.get(args[1])!, destination: args[2] }; break;
        case 'REMOVE': effect = { kind: 'move', item: args[0], place: nowhere }; break;
        case 'ADD': effect = { kind: 'move', item: args[0], place: floor(args[1]) }; break;
        case 'SET': case 'CLEAR': effect = { kind: 'flag', flag: args[0], on: words[index] === 'SET' }; break;
        default: effect = { kind: 'points', amount: Number(args[0]) }; break;
    }
    return { trigger, condition, effect };
}

class Adventure {
    private readonly rooms = new Map<string, Room>();
    private readonly items = new Map<string, Item>();
    private readonly rules: Rule[] = [];
    private readonly ids: readonly string[];
    private readonly vocabulary: ReadonlySet<string>;
    private trophy = '';
    private maxWeight = 0;
    private it: string | null = null;
    private previous: string | null = null;
    private verbose = false;
    private saved: GameState | null = null;
    state: GameState = { room: '', items: new Map(), exits: new Map(), flags: new Set(), bonus: 0,
        moves: 0, visited: new Set(), darkness: 0, ended: 'none' };

    constructor(lines: readonly string[]) {
        for (const line of lines) this.define(line.split(' '));
        this.state.visited.add(this.state.room);
        this.ids = [...this.items.keys()].sort();
        this.vocabulary = new Set([...this.items.values()].flatMap(item => [...item.nouns, ...item.words]));
    }
    private item(id: string): Item { return this.items.get(id)!; }
    private itemState(id: string): ItemState { return this.state.items.get(id)!; }
    private define(words: readonly string[]): void {
        const [kind, id] = words;
        switch (kind) {
            case 'ROOM': {
                const dark = words[2] === 'DARK';
                this.rooms.set(id, { dark, name: words.slice(dark ? 3 : 2).join(' '), description: [] }); break;
            }
            case 'DESC': this.rooms.get(id)!.description.push(words.slice(2).join(' ')); break;
            case 'EXIT': this.setExit(id, directionWords.get(words[2])!, words[3], words.length > 4 ? words[5] : null); break;
            case 'ITEM': {
                const { item, state } = readItem(words);
                this.items.set(id, item); this.state.items.set(id, state); break;
            }
            case 'INSIDE': this.itemState(id).place = inside(words[2]); break;
            case 'ALIAS': this.item(id).nouns.add(words[2]); break;
            case 'DETAIL': this.item(id).details.push(words.slice(2).join(' ')); break;
            case 'RULE': this.rules.push(readRule(words, 3, { kind: 'use', first: id, second: words[2] })); break;
            case 'ENTER': this.rules.push(readRule(words, 2, { kind: 'enter', room: id })); break;
            case 'TROPHY': this.trophy = id; break;
            case 'START': this.state.room = id; break;
            case 'MAXWEIGHT': this.maxWeight = Number(id); break;
        }
    }
    private setExit(room: string, direction: Direction, destination: string, key: string | null = null): void {
        let exits = this.state.exits.get(room);
        if (exits === undefined) { exits = new Map(); this.state.exits.set(room, exits); }
        exits.set(direction, { destination, key, locked: key !== null });
    }
    private contents(place: Place): string[] { return this.ids.filter(id => samePlace(this.itemState(id).place, place)); }
    private children(): Map<string, string[]> {
        const result = new Map<string, string[]>();
        for (const id of this.ids) {
            const key = placeKey(this.itemState(id).place);
            let children = result.get(key);
            if (children === undefined) { children = []; result.set(key, children); }
            children.push(id);
        }
        return result;
    }
    private isOpen(id: string): boolean { return this.item(id).capacity !== null && this.itemState(id).container === 'open'; }
    private reachable(place: Place): Set<string> {
        const result = new Set<string>(), children = this.children();
        const visit = (place: Place): void => {
            for (const id of children.get(placeKey(place)) ?? []) {
                result.add(id);
                if (this.isOpen(id)) visit(inside(id));
            }
        };
        visit(place);
        return result;
    }
    private carried(): Set<string> { return this.reachable(player); }
    private roomItems(): Set<string> { return this.reachable(floor(this.state.room)); }
    private isLit(): boolean {
        return !this.rooms.get(this.state.room)!.dark || [...this.carried(), ...this.roomItems()].some(id => this.itemState(id).lit);
    }
    private visible(): Set<string> { return this.isLit() ? new Set([...this.carried(), ...this.roomItems()]) : this.carried(); }
    private weights(): Map<string, number> {
        const result = new Map<string, number>(), children = this.children();
        const total = (id: string): number => {
            const cached = result.get(id);
            if (cached !== undefined) return cached;
            const weight = this.item(id).weight + (children.get(placeKey(inside(id))) ?? []).reduce((sum, child) => sum + total(child), 0);
            result.set(id, weight);
            return weight;
        };
        for (const id of this.ids) total(id);
        return result;
    }
    private totalWeight(id: string): number { return this.weights().get(id)!; }
    private contentWeight(id: string): number { return this.totalWeight(id) - this.item(id).weight; }
    private carriedWeight(): number {
        const weights = this.weights();
        return this.contents(player).reduce((sum, id) => sum + weights.get(id)!, 0);
    }
    private nestedIn(id: string, ancestor: string): boolean {
        let place = this.itemState(id).place;
        while (place.kind === 'inside') {
            if (place.id === ancestor) return true;
            place = this.itemState(place.id).place;
        }
        return false;
    }
    score(): Score {
        let stored = 0, treasures = 0, points = 0;
        for (const id of this.ids) if (this.item(id).points > 0) {
            ++treasures;
            let place = this.itemState(id).place;
            while (place.kind === 'inside') place = this.itemState(place.id).place;
            if (samePlace(place, floor(this.trophy))) { ++stored; points += this.item(id).points; }
        }
        return { stored, treasures, points, total: points + this.state.bonus };
    }
    private display(id: string): string {
        const item = this.item(id), state = this.itemState(id), annotations: string[] = [];
        if (item.capacity !== null) annotations.push(state.container);
        if (item.light && state.lit) annotations.push('lit');
        return item.name + (annotations.length ? ` (${annotations.join(', ')})` : '');
    }
    private tree(place: Place, depth = 1, children: ReadonlyMap<string, readonly string[]> = this.children()): string[] {
        const rows: string[] = [];
        for (const id of children.get(placeKey(place)) ?? []) {
            rows.push('  '.repeat(depth) + this.display(id));
            if (this.isOpen(id)) rows.push(...this.tree(inside(id), depth + 1, children));
        }
        return rows;
    }
    describe(full = true): string[] {
        if (!this.isLit()) return ['It is pitch dark.'];
        const room = this.rooms.get(this.state.room)!, exits = this.state.exits.get(this.state.room), names: string[] = [];
        for (const direction of directions) {
            const exit = exits?.get(direction);
            if (exit !== undefined) names.push(direction + (exit.locked ? ' (locked)' : ''));
        }
        const rows = [room.name, ...(full ? room.description : []), 'Exits: ' + (names.length ? names.join(', ') : 'none')];
        if (this.contents(floor(this.state.room)).length) rows.push('You see:', ...this.tree(floor(this.state.room)));
        return rows;
    }
    private resolve(phrase: Phrase): string {
        const visible = this.visible();
        if (phrase.length === 1 && phrase[0] === 'it') {
            if (this.it === null) fail('I don\'t know what "it" refers to.');
            if (!visible.has(this.it)) fail("You can't see any such thing.");
            return this.it;
        }
        for (const word of phrase) if (!this.vocabulary.has(word)) fail(`I don't know the word "${word}".`);
        const matches = this.ids.filter(id => visible.has(id) && this.item(id).nouns.has(phrase[phrase.length - 1]) &&
            phrase.slice(0, -1).every(word => this.item(id).words.has(word)));
        if (!matches.length) fail("You can't see any such thing.");
        if (matches.length > 1) fail(`Which do you mean: ${matches.map(id => this.item(id).name).join(', ')}?`);
        this.it = matches[0];
        return matches[0];
    }
    private runRules(trigger: Trigger): RuleResult {
        const rows: string[] = [];
        let executed = 0;
        for (const rule of this.rules) {
            const target = rule.trigger;
            if (trigger.kind === 'enter') {
                if (target.kind !== 'enter' || target.room !== trigger.room) continue;
            } else if (target.kind !== 'use' || target.first !== trigger.first || target.second !== trigger.second) continue;
            if (rule.condition !== null && this.state.flags.has(rule.condition.flag) !== rule.condition.on) continue;
            ++executed;
            const effect = rule.effect;
            switch (effect.kind) {
                case 'message': rows.push(effect.text); break;
                case 'open': this.setExit(effect.room, effect.direction, effect.destination); break;
                case 'move': this.itemState(effect.item).place = effect.place; break;
                case 'flag': if (effect.on) this.state.flags.add(effect.flag); else this.state.flags.delete(effect.flag); break;
                case 'points': this.state.bonus += effect.amount; break;
            }
        }
        return { rows, executed };
    }
    private requireContainer(id: string): number {
        const item = this.item(id);
        if (item.capacity === null) fail(`The ${item.name} is not a container.`);
        if (!this.isOpen(id)) fail(`The ${item.name} is closed.`);
        return item.capacity;
    }
    private take(first: Phrase, second: Phrase | null): string[] {
        if (!this.isLit()) fail('It is pitch dark.');
        let container: string | null = null, source = floor(this.state.room);
        if (second !== null) { container = this.resolve(second); this.requireContainer(container); source = inside(container); }
        if (allItems(first)) {
            const candidates = this.contents(source).filter(id => !this.item(id).fixed), rows: string[] = [];
            if (!candidates.length) fail(container === null ? 'There is nothing here to take.' : `There is nothing in the ${this.item(container).name} to take.`);
            let taken = false;
            for (const id of candidates) {
                let outcome = "You can't carry any more.";
                if (this.carried().has(id) || this.carriedWeight() + this.totalWeight(id) <= this.maxWeight) {
                    this.itemState(id).place = player; outcome = 'Taken.'; taken = true;
                }
                rows.push(`${this.item(id).name}: ${outcome}`);
            }
            if (!taken) fail(rows);
            return rows;
        }
        const id = this.resolve(first), item = this.item(id), state = this.itemState(id);
        if (container !== null && !samePlace(state.place, source)) fail(`The ${item.name} is not in the ${this.item(container).name}.`);
        if (state.place.kind === 'player') fail(`You already have the ${item.name}.`);
        if (item.fixed) fail(`The ${item.name} is fixed in place.`);
        if (!this.carried().has(id) && this.carriedWeight() + this.totalWeight(id) > this.maxWeight) fail("You can't carry any more.");
        state.place = player;
        return ['Taken.'];
    }
    private drop(target: Phrase): string[] {
        if (allItems(target)) {
            const candidates = this.contents(player);
            if (!candidates.length) fail('You are empty-handed.');
            return candidates.map(id => { this.itemState(id).place = floor(this.state.room); return `${this.item(id).name}: Dropped.`; });
        }
        const id = this.resolve(target);
        if (!this.carried().has(id)) fail(`You aren't carrying the ${this.item(id).name}.`);
        this.itemState(id).place = floor(this.state.room);
        return ['Dropped.'];
    }
    private putItem(id: string, container: string, capacity: number): string | null {
        const item = this.item(id), target = this.item(container), state = this.itemState(id);
        if (this.nestedIn(container, id)) return `The ${target.name} is inside the ${item.name}.`;
        if (samePlace(state.place, inside(container))) return `The ${item.name} is already in the ${target.name}.`;
        const weight = this.contentWeight(container) + (this.nestedIn(id, container) ? 0 : this.totalWeight(id));
        if (weight > capacity) return `The ${item.name} doesn't fit in the ${target.name}.`;
        state.place = inside(container);
        return null;
    }
    private put(first: Phrase, second: Phrase): string[] {
        if (allItems(first)) {
            const target = this.resolve(second), capacity = this.requireContainer(target);
            const candidates = this.contents(player).filter(id => id !== target), rows: string[] = [];
            if (!candidates.length) fail(`You have nothing to put in the ${this.item(target).name}.`);
            let succeeded = false;
            for (const id of candidates) {
                const reason = this.putItem(id, target, capacity);
                if (reason === null) succeeded = true;
                rows.push(`${this.item(id).name}: ${reason ?? 'Done.'}`);
            }
            if (!succeeded) fail(rows);
            return rows;
        }
        const id = this.resolve(first), target = this.resolve(second), item = this.item(id);
        if (!this.carried().has(id)) fail(`You aren't carrying the ${item.name}.`);
        if (id === target) fail(`You can't put the ${item.name} inside itself.`);
        const capacity = this.requireContainer(target), reason = this.putItem(id, target, capacity);
        if (reason !== null) fail(reason);
        return [`You put the ${item.name} in the ${this.item(target).name}.`];
    }
    private keyCheck(key: string, phrase: Phrase | null): string[] {
        if (phrase !== null) {
            const id = this.resolve(phrase), name = this.item(id).name;
            if (!this.carried().has(id)) fail(`You aren't carrying the ${name}.`);
            if (id !== key) fail(`The ${name} doesn't fit.`);
            return [];
        }
        if (!this.carried().has(key)) fail("You don't have the right key.");
        return [`(with the ${this.item(key).name})`];
    }
    private changeLock(first: Phrase, second: Phrase | null, locking: boolean): string[] {
        const direction = first.length === 1 ? directionWords.get(first[0]) : undefined;
        if (direction !== undefined) {
            const exit = this.state.exits.get(this.state.room)?.get(direction);
            if (exit === undefined) fail(`There is no exit ${direction}.`);
            if (exit.key === null) fail(`The way ${direction} has no lock.`);
            if (exit.locked === locking) fail(`The way ${direction} is ${locking ? 'already locked' : 'not locked'}.`);
            const rows = this.keyCheck(exit.key, second);
            exit.locked = locking;
            const opposite = directions[directions.indexOf(direction) ^ 1], back = this.state.exits.get(exit.destination)?.get(opposite);
            if (back !== undefined && back.destination === this.state.room && back.key === exit.key) back.locked = locking;
            return [...rows, locking ? 'Locked.' : 'Unlocked.'];
        }
        const id = this.resolve(first), item = this.item(id), state = this.itemState(id);
        if (item.capacity === null || item.key === null) fail(`The ${item.name} has no lock.`);
        if ((state.container === 'locked') === locking) fail(`The ${item.name} is ${locking ? 'already locked' : 'not locked'}.`);
        if (locking && state.container === 'open') fail(`You must close the ${item.name} first.`);
        const rows = this.keyCheck(item.key, second);
        state.container = locking ? 'locked' : 'closed';
        return [...rows, locking ? 'Locked.' : 'Unlocked.'];
    }
    private itemAction(verb: ItemVerb, target: Phrase): string[] {
        const id = this.resolve(target), item = this.item(id), state = this.itemState(id);
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
                return contents.length ? [`Opening the ${item.name} reveals ${contents.map(child => this.item(child).name).join(', ')}.`] : ['Opened.'];
            }
            case 'close':
                if (item.capacity === null) fail(`You can't close the ${item.name}.`);
                if (state.container !== 'open') fail(`The ${item.name} is already closed.`);
                state.container = 'closed'; return ['Closed.'];
            case 'light':
                if (!item.light) fail(`You can't light the ${item.name}.`);
                if (state.lit) fail(`The ${item.name} is already lit.`);
                if (state.fuel === 0) fail(`The ${item.name} has no fuel.`);
                state.lit = true; return [`The ${item.name} is now lit.`];
            case 'extinguish':
                if (!item.light) fail(`You can't extinguish the ${item.name}.`);
                if (!state.lit) fail(`The ${item.name} is not lit.`);
                state.lit = false; return [`The ${item.name} is now out.`];
        }
    }
    private execute(command: Exclude<Command, { verb: 'go' }>): string[] {
        switch (command.verb) {
            case 'look': return this.describe();
            case 'inventory':
                return this.contents(player).length ? ['You are carrying:', ...this.tree(player), `Total weight: ${this.carriedWeight()}/${this.maxWeight}`] : ['You are empty-handed.'];
            case 'wait': return ['Time passes.'];
            case 'score': {
                const score = this.score();
                return [`You have scored ${score.total} points (treasure ${score.points}, bonus ${this.state.bonus}) in ${this.state.moves} moves.`,
                    `Treasures stored: ${score.stored} of ${score.treasures}.`];
            }
            case 'save': this.saved = structuredClone(this.state); return ['Game saved.'];
            case 'restore':
                if (this.saved === null) fail('There is no saved game.');
                this.state = structuredClone(this.saved); return ['Game restored.', ...this.describe()];
            case 'verbose': this.verbose = true; return ['Verbose mode.'];
            case 'brief': this.verbose = false; return ['Brief mode.'];
            case 'take': return this.take(command.target, command.from);
            case 'drop': return this.drop(command.target);
            case 'put': return this.put(command.first, command.second);
            case 'unlock': case 'lock': return this.changeLock(command.target, command.key, command.verb === 'lock');
            case 'use': {
                const first = this.resolve(command.first), second = this.resolve(command.second);
                if (!this.carried().has(first)) fail(`You aren't carrying the ${this.item(first).name}.`);
                const result = this.runRules({ kind: 'use', first, second });
                if (result.executed === 0) fail('Nothing happens.');
                return result.rows.length ? result.rows : ['Done.'];
            }
            case 'examine': case 'open': case 'close': case 'light': case 'extinguish': return this.itemAction(command.verb, command.target);
        }
    }
    private endTurn(baseline: boolean): string[] {
        const rows: string[] = [];
        ++this.state.moves;
        const nearby = new Set([...this.carried(), ...this.roomItems()]);
        for (const id of this.ids) {
            const state = this.itemState(id);
            if (state.lit && --state.fuel === 0) {
                state.lit = false;
                if (nearby.has(id)) rows.push(`The ${this.item(id).name} goes out.`);
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
    private parse(line: string): Command {
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
        if (hasNoObjects(verb)) {
            if (rest.length) fail("I don't understand that.");
            return { verb };
        }
        if (!rest.length) fail(verb === 'go' ? 'Which way do you want to go?' : `What do you want to ${verb}?`);
        if (verb === 'go') {
            const direction = rest.length === 1 ? directionWords.get(rest[0]) : undefined;
            if (direction === undefined) fail("I don't understand that.");
            return { verb, direction };
        }
        let first = rest, second: string[] | null = null;
        const prepositions = verb === 'put' ? ['in', 'into'] : verb === 'use' ? ['on', 'with'] :
            verb === 'lock' || verb === 'unlock' ? ['with'] : verb === 'take' ? ['from'] : [];
        const index = rest.findIndex(word => prepositions.includes(word));
        if (index >= 0) {
            if (index === 0 || index === rest.length - 1) fail("I don't understand that.");
            first = rest.slice(0, index); second = rest.slice(index + 1);
        }
        if (verb === 'put' || verb === 'use') {
            if (second === null) fail("I don't understand that.");
            return { verb, first, second };
        }
        if (verb === 'take') return { verb, target: first, from: second };
        if (verb === 'lock' || verb === 'unlock') return { verb, target: first, key: second };
        return { verb, target: first };
    }
    private interpret(line: string): string[] {
        const command = this.parse(line);
        let baseline = this.isLit(), rows: string[];
        if (command.verb === 'go') {
            const exit = this.state.exits.get(this.state.room)?.get(command.direction);
            if (exit === undefined) fail("You can't go that way.");
            if (exit.locked) fail(`The way ${command.direction} is locked.`);
            this.state.room = exit.destination;
            baseline = this.isLit();
            rows = this.describe(this.verbose || !this.state.visited.has(this.state.room));
            this.state.visited.add(this.state.room);
            rows.push(...this.runRules({ kind: 'enter', room: this.state.room }).rows);
        } else rows = this.execute(command);
        if (actions.has(command.verb)) rows.push(...this.endTurn(baseline));
        return rows;
    }
    command(line: string): readonly string[] {
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

const input = readFileSync(0, 'utf8').trimEnd().split(/\r?\n/), begin = input.indexOf('BEGIN');
const adventure = new Adventure(input.slice(0, begin));
const write = (rows: readonly string[]): void => { process.stdout.write(rows.join('\n') + '\n'); };
write(adventure.describe());
for (const line of input.slice(begin + 1)) {
    if (line === 'QUIT') {
        write([`Final score: ${adventure.score().total} points in ${adventure.state.moves} moves.`]);
        break;
    }
    write(['> ' + line, ...adventure.command(line)]);
}
