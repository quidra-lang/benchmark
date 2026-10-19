'use strict';

const fs = require('node:fs');
const { Minstd } = require('./minstd');
const { generateDungeon } = require('./dungeon_gen');
const { monsterType, itemType, makeMonster, makeItem, itemSymbol, displayName, referenceName } = require('./entities');
const { parseDice, resolveAttack } = require('./combat');
const { DIRECTIONS, passable, canMove, fieldOfView, distances } = require('./fov');

function readTokens(name) {
    return fs.readFileSync('input/' + name, 'ascii').trimEnd().split('\n').map(line => line.split(' '));
}

function readInput() {
    const rows = new Map(readTokens('config.txt').map(([name, ...values]) => [name, values]));
    const integers = name => rows.get(name).map(Number);
    const [generationSeed, gameSeed] = integers('seed');
    const [width, height] = integers('map');
    const [regionSize, splitDepth] = integers('bsp');
    const [roomMin, roomMax] = integers('room');
    const [sleepProbability, wakeProbability] = integers('sleep');
    const [initialHp, regenerationInterval] = integers('player');
    const [initialFood, maxFood, hungryFood, weakFood] = integers('food');
    const config = { generationSeed, gameSeed, width, height, regionSize, splitDepth, roomMin, roomMax,
        sleepProbability, wakeProbability, initialHp, regenerationInterval, initialFood, maxFood, hungryFood, weakFood,
        levelCount: integers('levels')[0], monsterScale: integers('monsters'), itemScale: integers('items'),
        radius: integers('fov')[0], hitDie: parseDice(rows.get('hitdie')[0]), packSize: integers('pack')[0],
        startItems: rows.get('start'), xpThresholds: integers('xp'), checkpoints: new Set(integers('checkpoints')) };
    const monsterTypes = readTokens('monsters.txt').map(monsterType);
    const itemTypes = readTokens('items.txt').map(itemType);
    const commands = [];
    for (const tokens of readTokens('commands.txt')) {
        const count = tokens[0] === 'move' ? Number(tokens[2] ?? 1) : tokens[0] === 'wait' ? Number(tokens[1] ?? 1) : 1;
        for (let i = 0; i < count; i++) commands.push({ name: tokens[0], argument: tokens[1] });
    }
    return { config, monsterTypes, itemTypes, commands };
}

function dec1(numerator, denominator) {
    if (denominator === 0) return '-';
    const rounded = Math.floor((20 * numerator + denominator) / (2 * denominator));
    return `${Math.floor(rounded / 10)}.${rounded % 10}`;
}

class Game {
    constructor(input) {
        Object.assign(this, input);
        this.rng = new Minstd(this.config.gameSeed);
        this.levels = this.createLevels();
        const typesByName = new Map(this.itemTypes.map(type => [type.name, type]));
        const pack = this.config.startItems.map(name => makeItem(typesByName.get(name)));
        const arrival = this.levels[0].arrival;
        this.player = { x: arrival.x, y: arrival.y, depth: 1, hp: this.config.initialHp, maxHp: this.config.initialHp,
            level: 1, xp: 0, gold: 0, food: this.config.initialFood, poison: 0, pack,
            weapon: pack.find(item => item.type.kind === 'weapon') ?? null,
            armor: pack.find(item => item.type.kind === 'armor') ?? null };
        this.turn = 1;
        this.result = null;
        this.cause = 'commands_exhausted';
        this.messages = [];
        this.maps = [];
        this.metrics = { executed: 0, failed: 0, unused: 0, moves: 0, picked: 0, quaffed: 0, read: 0,
            eaten: 0, wielded: 0, worn: 0, poisonDamage: 0, starvationDamage: 0 };
        this.playerAttacks = { count: 0, hits: 0, criticals: 0, damage: 0 };
        this.monsterAttacks = { count: 0, hits: 0, criticals: 0, damage: 0 };
        this.kills = new Map();
    }

    createLevels() {
        const rng = new Minstd(this.config.generationSeed);
        const levels = [];
        for (let depth = 1; depth <= this.config.levelCount; depth++) {
            const level = generateDungeon(this.config, depth, rng);
            const targetKey = level.key(level.target.x, level.target.y);
            if (depth < this.config.levelCount) level.terrain[targetKey] = '>';
            else level.items.set(targetKey, makeItem({ kind: 'amulet', name: 'amulet' }));
            const monsters = this.monsterTypes.filter(type => type.minDepth <= depth && depth <= type.maxDepth);
            level.monstersCreated = this.config.monsterScale[0] + this.config.monsterScale[1] * (depth - 1);
            for (let id = 1; id <= level.monstersCreated; id++) {
                const type = rng.select(monsters);
                let cell;
                do { cell = level.roomCell(rng); }
                while (cell.room === level.arrival.room || level.terrain[level.key(cell.x, cell.y)] !== '.'
                    || level.monsters.some(monster => monster.x === cell.x && monster.y === cell.y));
                const hp = rng.roll(type.hp);
                const asleep = rng.rnd(100) < this.config.sleepProbability;
                level.monsters.push(makeMonster(type, id, cell, hp, asleep));
            }
            const items = this.itemTypes.filter(type => type.minDepth <= depth && depth <= type.maxDepth);
            const count = this.config.itemScale[0] + this.config.itemScale[1] * (depth - 1);
            for (let i = 0; i < count; i++) {
                const type = rng.select(items);
                let cell;
                do { cell = level.roomCell(rng); }
                while (level.terrain[level.key(cell.x, cell.y)] !== '.' || level.items.has(level.key(cell.x, cell.y)));
                const amount = type.kind === 'gold' ? rng.roll(type.dice) : 0;
                level.items.set(level.key(cell.x, cell.y), makeItem(type, amount));
            }
            level.itemsPlaced = level.items.size;
            levels.push(level);
        }
        return levels;
    }

    get level() { return this.levels[this.player.depth - 1]; }

    message(text) { this.messages.push(`${String(this.turn).padStart(4, '0')} ${text}`); }

    fail(text) { this.message(text); return false; }

    hunger() {
        const food = this.player.food;
        if (food > this.config.hungryFood) return 'normal';
        if (food > this.config.weakFood) return 'hungry';
        return food > 0 ? 'weak' : 'starving';
    }

    defense() {
        const armor = this.player.armor;
        return armor === null ? 10 : 10 + armor.type.armor + armor.bonus;
    }

    monsterAt(x, y) { return this.level.monsters.find(monster => monster.x === x && monster.y === y); }

    updateView() {
        const level = this.level;
        this.visible = fieldOfView(level, this.player.x, this.player.y, this.config.radius);
        for (const key of this.visible) level.memory[key] = level.items.has(key) ? itemSymbol(level.items.get(key)) : level.terrain[key];
        for (const monster of level.monsters) {
            const visible = this.visible.has(level.key(monster.x, monster.y));
            if (visible && !monster.wasVisible) this.message(`You see the ${monster.type.name}.`);
            monster.wasVisible = visible;
        }
    }

    gainExperience(amount) {
        const player = this.player;
        player.xp += amount;
        while (player.level <= this.config.xpThresholds.length && player.xp >= this.config.xpThresholds[player.level - 1]) {
            player.level++;
            const hp = this.rng.roll(this.config.hitDie);
            player.maxHp += hp;
            player.hp += hp;
            this.message(`Welcome to level ${player.level}.`);
        }
    }

    die(cause) {
        this.cause = cause;
        this.result = 'died';
        this.message('You die.');
    }

    countAttack(statistics, attack) {
        statistics.count++;
        if (attack.kind === 'miss') return;
        statistics.hits++;
        if (attack.kind === 'critical') statistics.criticals++;
        statistics.damage += attack.damage;
    }

    attackMonster(monster) {
        monster.asleep = false;
        const weapon = this.player.weapon;
        let modifier = this.player.level + (weapon === null ? 0 : weapon.type.toHit + weapon.bonus);
        if (this.hunger() === 'weak' || this.hunger() === 'starving') modifier -= 2;
        const attack = resolveAttack(this.rng, modifier, monster.type.defense,
            weapon === null ? parseDice('1d2') : weapon.type.damage, weapon === null ? 0 : weapon.bonus);
        this.countAttack(this.playerAttacks, attack);
        if (attack.kind === 'miss') this.message(`You miss the ${monster.type.name}.`);
        else {
            this.message(`You hit the ${monster.type.name}${attack.kind === 'critical' ? ' hard' : ''} for ${attack.damage}.`);
            monster.hp -= attack.damage;
            if (monster.hp <= 0) {
                this.message(`You kill the ${monster.type.name}.`);
                this.level.monsters = this.level.monsters.filter(other => other !== monster);
                this.level.killed++;
                this.kills.set(monster.type.name, (this.kills.get(monster.type.name) ?? 0) + 1);
                this.gainExperience(monster.type.xp);
            }
        }
    }

    attackPlayer(monster) {
        const attack = resolveAttack(this.rng, monster.type.toHit, this.defense(), monster.type.damage, 0);
        this.countAttack(this.monsterAttacks, attack);
        if (attack.kind === 'miss') this.message(`The ${monster.type.name} misses you.`);
        else {
            this.message(`The ${monster.type.name} hits you${attack.kind === 'critical' ? ' hard' : ''} for ${attack.damage}.`);
            this.player.hp -= attack.damage;
            if (this.player.hp <= 0) this.die('killed_by ' + monster.type.name);
            else if (monster.type.traits.includes('P')) {
                this.player.poison += 5;
                this.message('You are poisoned.');
            }
        }
    }

    movePlayer(direction) {
        const { dx, dy } = DIRECTIONS.find(item => item.name === direction);
        const player = this.player;
        const x = player.x + dx;
        const y = player.y + dy;
        if (!passable(this.level, x, y)) return this.fail('You bump into a wall.');
        if (!canMove(this.level, player.x, player.y, dx, dy)) return this.fail('You cannot move diagonally through a door.');
        const monster = this.monsterAt(x, y);
        if (monster) this.attackMonster(monster);
        else {
            player.x = x;
            player.y = y;
            this.metrics.moves++;
            const key = this.level.key(x, y);
            const item = this.level.items.get(key);
            if (item) this.message(`You see ${referenceName(item)} here.`);
            else if (this.level.terrain[key] === '>') this.message('There is a staircase down here.');
        }
        return true;
    }

    pickup() {
        const key = this.level.key(this.player.x, this.player.y);
        const item = this.level.items.get(key);
        if (!item) return this.fail('There is nothing here.');
        if (item.type.kind === 'gold') {
            this.player.gold += item.amount;
            this.message(`You pick up ${displayName(item)}.`);
        } else if (item.type.kind === 'amulet') {
            this.message('You pick up the amulet.');
            this.message('You win!');
            this.result = 'won';
            this.cause = 'amulet';
        } else {
            if (this.player.pack.length >= this.config.packSize) return this.fail('Your pack is full.');
            this.player.pack.push(item);
            this.message(`You pick up the ${displayName(item)} (${this.player.pack.length}).`);
        }
        this.level.items.delete(key);
        this.level.picked++;
        this.metrics.picked++;
        return true;
    }

    quaff(item) {
        this.metrics.quaffed++;
        this.message(`You quaff the ${displayName(item)}.`);
        if (item.type.effect === 'heal') {
            this.player.hp += this.rng.roll(item.type.dice);
            if (this.player.hp > this.player.maxHp) {
                this.player.maxHp++;
                this.player.hp = this.player.maxHp;
            }
            this.player.poison = 0;
            this.message('You feel better.');
        } else if (item.type.effect === 'poison') {
            this.player.poison += item.type.poison;
            this.message('You feel very sick.');
        } else {
            this.message('You feel more experienced.');
            if (this.player.level <= this.config.xpThresholds.length) {
                this.gainExperience(this.config.xpThresholds[this.player.level - 1] - this.player.xp);
            }
        }
    }

    readScroll(item) {
        this.metrics.read++;
        this.message(`You read the ${displayName(item)}.`);
        const effect = item.type.effect;
        if (effect === 'mapping') {
            for (let key = 0; key < this.level.terrain.length; key++) {
                if (this.level.terrain[key] !== ' ' && this.level.memory[key] === ' ') this.level.memory[key] = this.level.terrain[key];
            }
            this.message('A map forms in your mind.');
        } else if (effect === 'teleport') {
            let cell;
            do { cell = this.level.roomCell(this.rng); }
            while ((cell.x === this.player.x && cell.y === this.player.y) || this.monsterAt(cell.x, cell.y));
            this.player.x = cell.x;
            this.player.y = cell.y;
            this.message('You are teleported.');
        } else if (effect === 'enchant_weapon') {
            if (this.player.weapon) {
                this.message(`Your ${displayName(this.player.weapon)} glows blue.`);
                this.player.weapon.bonus++;
            } else this.message('Your hands twitch.');
        } else if (this.player.armor) {
            this.message(`Your ${displayName(this.player.armor)} glows silver.`);
            this.player.armor.bonus++;
        } else this.message('Your skin tingles.');
    }

    useItem(command, number) {
        const pack = this.player.pack;
        if (number > pack.length) return this.fail('You do not have that item.');
        const item = pack[number - 1];
        const kinds = { quaff: 'potion', read: 'scroll', wield: 'weapon', wear: 'armor', eat: 'food' };
        if (item.type.kind !== kinds[command]) return this.fail(`You cannot ${command} that.`);
        if (command === 'wield') {
            if (this.player.weapon === item) return this.fail('You are already wielding that.');
            this.player.weapon = item;
            this.metrics.wielded++;
            this.message(`You are now wielding the ${displayName(item)}.`);
        } else if (command === 'wear') {
            if (this.player.armor === item) return this.fail('You are already wearing that.');
            this.player.armor = item;
            this.metrics.worn++;
            this.message(`You are now wearing the ${displayName(item)}.`);
        } else {
            pack.splice(number - 1, 1);
            if (command === 'quaff') this.quaff(item);
            else if (command === 'read') this.readScroll(item);
            else {
                this.metrics.eaten++;
                this.player.food = Math.min(this.player.food + item.type.satiation, this.config.maxFood);
                this.message(`You eat the ${displayName(item)}.`);
            }
        }
        return true;
    }

    execute(command) {
        if (command.name === 'move') return this.movePlayer(command.argument);
        if (command.name === 'wait') return true;
        if (command.name === 'pickup') return this.pickup();
        if (command.name === 'descend') {
            if (this.level.terrain[this.level.key(this.player.x, this.player.y)] !== '>') return this.fail('There are no stairs here.');
            this.player.depth++;
            this.player.x = this.level.arrival.x;
            this.player.y = this.level.arrival.y;
            this.message(`You descend to depth ${this.player.depth}.`);
            return true;
        }
        return this.useItem(command.name, Number(command.argument));
    }

    canAttack(monster) {
        const dx = this.player.x - monster.x;
        const dy = this.player.y - monster.y;
        return Math.max(Math.abs(dx), Math.abs(dy)) === 1 && canMove(this.level, monster.x, monster.y, dx, dy);
    }

    wander(monster) {
        const { dx, dy } = DIRECTIONS[this.rng.rnd(8)];
        if (!canMove(this.level, monster.x, monster.y, dx, dy)) return;
        const x = monster.x + dx;
        const y = monster.y + dy;
        if (x === this.player.x && y === this.player.y) this.attackPlayer(monster);
        else if (!this.monsterAt(x, y)) { monster.x = x; monster.y = y; }
    }

    chase(monster, distance) {
        if (this.canAttack(monster)) { this.attackPlayer(monster); return; }
        const current = distance[this.level.key(monster.x, monster.y)];
        let chosen = null;
        for (const { dx, dy } of DIRECTIONS) {
            if (!canMove(this.level, monster.x, monster.y, dx, dy)) continue;
            const x = monster.x + dx;
            const y = monster.y + dy;
            const value = distance[this.level.key(x, y)];
            if (value < 0 || (current >= 0 && value >= current) || this.monsterAt(x, y)
                || (x === this.player.x && y === this.player.y)) continue;
            if (chosen === null || value < chosen.distance) chosen = { x, y, distance: value };
        }
        if (chosen) { monster.x = chosen.x; monster.y = chosen.y; }
    }

    monsterAction(monster, distance) {
        const visible = this.visible.has(this.level.key(monster.x, monster.y));
        if (monster.asleep) {
            if (visible && this.rng.rnd(100) < this.config.wakeProbability) {
                monster.asleep = false;
                this.message(`The ${monster.type.name} wakes up.`);
            }
        } else if (monster.type.traits.includes('S')) {
            if (this.canAttack(monster)) this.attackPlayer(monster);
        } else if (monster.type.traits.includes('E') && this.rng.rnd(2) === 0) this.wander(monster);
        else if (visible) this.chase(monster, distance);
        else this.wander(monster);
    }

    endTurn() {
        for (const monster of this.level.monsters) {
            if (monster.type.traits.includes('R') && monster.hp < monster.maxHp) monster.hp++;
        }
        if (this.player.poison > 0) {
            this.player.hp--;
            this.metrics.poisonDamage++;
            if (this.player.hp <= 0) { this.die('poison'); return; }
            this.player.poison--;
            if (this.player.poison === 0) this.message('You feel less sick.');
        }
        if (this.player.food === 0) {
            this.player.hp--;
            this.metrics.starvationDamage++;
            if (this.player.hp <= 0) { this.die('starvation'); return; }
        } else {
            const previous = this.hunger();
            this.player.food--;
            const current = this.hunger();
            if (current !== previous) {
                const messages = { hungry: 'You are getting hungry.', weak: 'You feel weak from hunger.', starving: 'You are starving.' };
                this.message(messages[current]);
            }
        }
        if (this.turn % this.config.regenerationInterval === 0 && this.player.poison === 0
            && this.player.food > 0 && this.player.hp < this.player.maxHp) this.player.hp++;
    }

    run() {
        this.updateView();
        for (const command of this.commands) {
            if (this.result !== null) { this.metrics.unused++; continue; }
            if (!this.execute(command)) { this.metrics.failed++; continue; }
            this.metrics.executed++;
            if (this.result !== null) continue;
            this.updateView();
            const distance = distances(this.level, this.player.x, this.player.y);
            for (const monster of this.level.monsters) {
                monster.energy += monster.type.speed;
                while (monster.energy >= 2) {
                    monster.energy -= 2;
                    this.monsterAction(monster, distance);
                    if (this.result !== null) break;
                }
                if (this.result !== null) break;
            }
            if (this.result !== null) continue;
            this.endTurn();
            if (this.result !== null) continue;
            if (this.config.checkpoints.has(this.turn)) {
                this.maps.push(`CHECKPOINT turn ${this.turn} depth ${this.player.depth}`, ...this.mapLines(this.level, true), this.status());
            }
            this.turn++;
        }
        if (this.result === null) this.result = 'alive';
    }

    exploration(level) {
        let explored = 0;
        let total = 0;
        for (let key = 0; key < level.terrain.length; key++) {
            if (level.terrain[key] !== ' ') {
                total++;
                if (level.memory[key] !== ' ') explored++;
            }
        }
        return { explored, total };
    }

    mapLines(level, current) {
        const frame = '+' + '-'.repeat(level.width) + '+';
        const lines = [frame];
        const monsters = new Map(level.monsters.map(monster => [level.key(monster.x, monster.y), monster]));
        for (let y = 0; y < level.height; y++) {
            let row = '|';
            for (let x = 0; x < level.width; x++) {
                const key = level.key(x, y);
                let symbol = level.memory[key];
                if (current && this.visible.has(key)) {
                    if (x === this.player.x && y === this.player.y) symbol = '@';
                    else if (monsters.has(key)) symbol = monsters.get(key).type.symbol;
                    else if (level.items.has(key)) symbol = itemSymbol(level.items.get(key));
                    else symbol = level.terrain[key];
                }
                row += symbol;
            }
            lines.push(row + '|');
        }
        lines.push(frame);
        return lines;
    }

    status() {
        const p = this.player;
        return `STATUS hp ${p.hp}/${p.maxHp} level ${p.level} xp ${p.xp} defense ${this.defense()}`
            + ` gold ${p.gold} food ${p.food} ${this.hunger()} poison ${p.poison}`;
    }

    statistics() {
        const p = this.player;
        const m = this.metrics;
        const lines = [`result ${this.result}`, `cause ${this.cause}`, `turns ${m.executed}`, `depth ${p.depth}`,
            `level ${p.level}`, `xp ${p.xp}`, `hp ${p.hp}/${p.maxHp}`, `defense ${this.defense()}`, `gold ${p.gold}`,
            `food ${p.food} ${this.hunger()}`, `poison ${p.poison}`, `weapon ${p.weapon ? displayName(p.weapon) : '-'}`,
            `armor ${p.armor ? displayName(p.armor) : '-'}`,
            `commands ${this.commands.length} executed ${m.executed} failed ${m.failed} unused ${m.unused}`, `moves ${m.moves}`];
        for (const [name, attacks] of [['player', this.playerAttacks], ['monster', this.monsterAttacks]]) {
            lines.push(`${name}_attacks ${attacks.count} hits ${attacks.hits} criticals ${attacks.criticals}`
                + ` damage ${attacks.damage} accuracy ${dec1(100 * attacks.hits, attacks.count)}`);
        }
        lines.push(`poison_damage ${m.poisonDamage} starvation_damage ${m.starvationDamage}`,
            `picked ${m.picked} quaffed ${m.quaffed} read ${m.read} eaten ${m.eaten} wielded ${m.wielded} worn ${m.worn}`);
        let totalKills = 0;
        for (const count of this.kills.values()) totalKills += count;
        lines.push(`kills ${totalKills}`);
        for (const type of this.monsterTypes) {
            if (this.kills.has(type.name)) lines.push(`KILL ${type.name} ${this.kills.get(type.name)}`);
        }
        for (const level of this.levels) {
            const { explored, total } = this.exploration(level);
            lines.push(`LEVEL ${level.depth} rooms ${level.rooms.length} explored ${explored}/${total} ${dec1(100 * explored, total)}`
                + ` monsters ${level.killed}/${level.monstersCreated} items ${level.picked}/${level.itemsPlaced}`);
        }
        for (let index = 0; index < p.pack.length; index++) {
            const item = p.pack[index];
            lines.push(`INVENTORY ${index + 1} ${displayName(item)}`
                + (item === p.weapon ? ' (wielded)' : '') + (item === p.armor ? ' (worn)' : ''));
        }
        return lines;
    }

    writeOutput() {
        this.maps.push(`FINAL turn ${this.metrics.executed} depth ${this.player.depth}`);
        for (let depth = 1; depth <= this.player.depth; depth++) {
            const level = this.levels[depth - 1];
            const { explored, total } = this.exploration(level);
            this.maps.push(`LEVEL ${depth} explored ${explored}/${total}`, ...this.mapLines(level, depth === this.player.depth));
        }
        this.maps.push(this.status());
        fs.mkdirSync('output', { recursive: true });
        for (const [name, lines] of [['messages.txt', this.messages], ['maps.txt', this.maps], ['stats.txt', this.statistics()]]) {
            fs.writeFileSync('output/' + name, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
        }
    }
}

function main() {
    const game = new Game(readInput());
    game.run();
    game.writeOutput();
}

if (require.main === module) main();
