'use strict';

const fs = require('node:fs');
const { readMap } = require('./grid_map');
const { DIRECTIONS, distanceField, nextCell, spawnPath } = require('./pathing');
const { MODES, parseTowerType, createTower, canAim, chooseTarget } = require('./towers');
const { parseEnemyType, parseGroup, spawnEnemy, splitEnemy, position, occupiedCell, slowedSpeed } = require('./enemies');
const { squaredDistance, advancePoint, receiveEffect, advanceEffect, armoredDamage, createProjectile, moveProjectile } = require('./combat');

function readLines(path) {
    const text = fs.readFileSync(path, 'ascii');
    return text === '' ? [] : text.slice(0, -1).split('\n').map(line => line.split(' '));
}

function readInputs() {
    const map = readMap();
    const towerTypes = new Map();
    const towerLines = readLines('input/towers.txt');
    for (let index = 0; index < towerLines.length;) {
        const count = Number(towerLines[index][4]);
        const type = parseTowerType(towerLines[index], towerLines.slice(index + 1, index + count + 1));
        towerTypes.set(type.name, type);
        index += count + 1;
    }
    const enemyTypes = new Map();
    const waves = [];
    for (const fields of readLines('input/waves.txt')) {
        if (fields[0] === 'enemy') {
            const type = parseEnemyType(fields, enemyTypes);
            enemyTypes.set(type.name, type);
        } else if (fields[0] === 'wave') waves.push({ reward: Number(fields[1]), groups: [] });
        else waves.at(-1).groups.push(parseGroup(fields, enemyTypes));
    }
    const actions = readLines('input/actions.txt').map(fields => ({
        tick: Number(fields[0]), command: fields[1], arguments: fields.slice(2),
    }));
    const parameters = new Map(readLines('input/params.txt').map(fields => [fields[0], fields.slice(1).map(Number)]));
    const settings = {
        gold: parameters.get('gold')[0], lives: parameters.get('lives')[0],
        interestRate: parameters.get('interest')[0], interestCap: parameters.get('interest')[1],
        sellRate: parameters.get('sell')[0], start: parameters.get('schedule')[0],
        interval: parameters.get('schedule')[1], early: parameters.get('early')[0],
        snapshots: new Set(parameters.get('snapshots')),
    };
    return { map, towerTypes, enemyTypes, waves, actions, settings };
}

function decimalOne(numerator, denominator) {
    if (denominator === 0) return '-';
    const rounded = Math.floor((20 * numerator + denominator) / (2 * denominator));
    return `${Math.floor(rounded / 10)}.${rounded % 10}`;
}

function digit(number) {
    return number === 0 ? '.' : number <= 9 ? String(number) : '*';
}

function appendLines(destination, source) {
    for (const line of source) destination.push(line);
}

class Game {
    constructor(data) {
        this.data = data;
        this.map = data.map;
        this.settings = data.settings;
        this.tick = 1;
        this.gold = data.settings.gold;
        this.lives = data.settings.lives;
        this.towers = [];
        this.standing = new Map();
        this.enemies = new Map();
        this.projectiles = new Map();
        this.nextEnemy = 1;
        this.nextProjectile = 1;
        this.spawnCells = new Map(this.map.spawns.map(spawn => [spawn.number, spawn.cell]));
        this.distances = distanceField(this.map, this.standing);
        this.nextStart = data.settings.start;
        this.started = 0;
        this.active = null;
        this.waveRecords = [];
        this.cleared = 0;
        this.perfect = 0;
        this.outcome = null;
        this.actionIndex = 0;
        this.succeeded = 0;
        this.refused = 0;
        this.income = { bounty: 0, reward: 0, interest: 0, early: 0, refund: 0 };
        this.spent = 0;
        this.killCounts = Array(this.map.cells.length).fill(0);
        this.events = [];
        this.snapshots = [];
    }

    event(body) {
        this.events.push(`${this.tick} ${body}`);
    }

    standingTower(number) {
        const tower = this.towers[number - 1];
        return tower !== undefined && tower.sold === null ? tower : null;
    }

    updateDistanceField() {
        const previous = this.distances;
        this.distances = distanceField(this.map, this.standing);
        for (const spawn of this.map.spawns) {
            if (previous[spawn.cell] !== this.distances[spawn.cell]) {
                this.event(`REPATH ${spawn.number} ${previous[spawn.cell]} ${this.distances[spawn.cell]}`);
            }
        }
    }

    build(name, x, y) {
        const type = this.data.towerTypes.get(name);
        const cell = this.map.cell(x, y);
        let reason = null;
        if (type === undefined) reason = 'type';
        else if (!this.map.inside(x, y)) reason = 'bounds';
        else if (!this.map.buildable(cell)) reason = 'terrain';
        else if (this.standing.has(cell)) reason = 'tower';
        else if (this.gold < type.levels[0].cost) reason = 'gold';
        if (reason === null) {
            for (const enemy of this.enemies.values()) {
                if (enemy.type.movement === 'ground' && (enemy.current === cell || enemy.next === cell)) {
                    reason = 'enemy';
                    break;
                }
            }
        }
        if (reason === null) {
            const blocked = new Set(this.standing.keys());
            blocked.add(cell);
            const trial = distanceField(this.map, blocked);
            if (this.map.spawns.some(spawn => trial[spawn.cell] < 0)) reason = 'blocked';
            for (const enemy of this.enemies.values()) {
                if (enemy.type.movement === 'ground' && trial[enemy.next] < 0) reason = 'blocked';
            }
        }
        if (reason !== null) {
            this.event(`BUILD_REFUSED ${name} ${x} ${y} ${reason}`);
            return false;
        }
        const tower = createTower(this.towers.length + 1, type, x, y, this.map, this.tick);
        this.towers.push(tower);
        this.standing.set(cell, tower);
        const cost = type.levels[0].cost;
        this.gold -= cost;
        this.spent += cost;
        this.event(`BUILD T${tower.number} ${name} ${x} ${y} cost ${cost} gold ${this.gold}`);
        this.updateDistanceField();
        return true;
    }

    upgrade(number) {
        const tower = this.standingTower(number);
        let reason = null;
        if (tower === null) reason = 'notower';
        else if (tower.level === tower.type.levels.length) reason = 'maxlevel';
        else if (this.gold < tower.type.levels[tower.level].cost) reason = 'gold';
        if (reason !== null) {
            this.event(`UPGRADE_REFUSED T${number} ${reason}`);
            return false;
        }
        const cost = tower.type.levels[tower.level].cost;
        tower.level++;
        tower.investment += cost;
        this.gold -= cost;
        this.spent += cost;
        this.event(`UPGRADE T${number} level ${tower.level} cost ${cost} gold ${this.gold}`);
        return true;
    }

    sell(number) {
        const tower = this.standingTower(number);
        if (tower === null) {
            this.event(`SELL_REFUSED T${number} notower`);
            return false;
        }
        const rate = this.tick === tower.built ? 100 : this.settings.sellRate;
        const refund = Math.floor(tower.investment * rate / 100);
        tower.sold = this.tick;
        this.standing.delete(tower.cell);
        this.gold += refund;
        this.income.refund += refund;
        this.event(`SELL T${number} refund ${refund} gold ${this.gold}`);
        this.updateDistanceField();
        return true;
    }

    target(number, mode) {
        const tower = this.standingTower(number);
        if (tower === null || !MODES.includes(mode)) {
            this.event(`TARGET_REFUSED T${number} ${tower === null ? 'notower' : 'mode'}`);
            return false;
        }
        tower.mode = mode;
        this.event(`TARGET T${number} ${mode}`);
        return true;
    }

    callWave() {
        if (this.active !== null) {
            this.event('CALL_REFUSED active');
            return false;
        }
        const bonus = (this.nextStart - this.tick) * this.settings.early;
        this.gold += bonus;
        this.income.early += bonus;
        this.nextStart = this.tick;
        this.event(`CALL ${this.started + 1} bonus ${bonus} gold ${this.gold}`);
        return true;
    }

    performAction(action) {
        const args = action.arguments;
        switch (action.command) {
            case 'BUILD': return this.build(args[0], Number(args[1]), Number(args[2]));
            case 'UPGRADE': return this.upgrade(Number(args[0]));
            case 'SELL': return this.sell(Number(args[0]));
            case 'TARGET': return this.target(Number(args[0]), args[1]);
            case 'CALL': return this.callWave();
        }
    }

    actions() {
        while (this.actionIndex < this.data.actions.length && this.data.actions[this.actionIndex].tick === this.tick) {
            const action = this.data.actions[this.actionIndex++];
            if (this.performAction(action)) this.succeeded++;
            else this.refused++;
        }
    }

    registerEnemy(enemy, origin) {
        this.enemies.set(enemy.number, enemy);
        enemy.type.spawned++;
        this.active.spawned++;
        this.event(`SPAWN E${enemy.number} ${enemy.type.name} ${origin} hp ${enemy.hp}`);
    }

    startAndSpawn() {
        if (this.active === null && this.tick === this.nextStart) {
            const wave = this.data.waves[this.started++];
            this.active = {
                number: this.started, wave, start: this.tick, end: null, status: 'active',
                spawned: 0, peak: 0, kills: 0, leaks: 0, livesLost: 0, bounty: 0,
                reward: 0, interest: 0, gold: 0, lives: 0, damage: new Map(),
                groups: wave.groups.map(group => ({ ...group, appeared: 0 })),
            };
            this.waveRecords.push(this.active);
            this.nextStart = null;
            let count = 0;
            for (const group of wave.groups) count += group.count;
            this.event(`WAVE_START ${this.started} enemies ${count}`);
        }
        if (this.active === null) return;
        for (const group of this.active.groups) {
            const scheduled = this.active.start + group.delay + group.appeared * group.interval;
            if (group.appeared >= group.count || scheduled !== this.tick) continue;
            const enemy = spawnEnemy(this.nextEnemy++, group.type, group.multiplier,
                this.spawnCells.get(group.spawn), this.map, this.distances);
            group.appeared++;
            this.registerEnemy(enemy, group.spawn);
        }
        this.active.peak = Math.max(this.active.peak, this.enemies.size);
    }

    creditDamage(enemy, tower, damage) {
        tower.damage += damage;
        enemy.type.damage += damage;
        this.active.damage.set(tower.number, (this.active.damage.get(tower.number) ?? 0) + damage);
    }

    kill(enemy, tower) {
        enemy.alive = false;
        this.enemies.delete(enemy.number);
        this.killCounts[occupiedCell(enemy, this.map)]++;
        tower.kills++;
        this.active.kills++;
        enemy.type.killed++;
        this.gold += enemy.type.bounty;
        this.active.bounty += enemy.type.bounty;
        this.income.bounty += enemy.type.bounty;
        this.event(`KILL E${enemy.number} ${enemy.type.name} T${tower.number} bounty ${enemy.type.bounty} gold ${this.gold}`);
        for (let index = 0; index < enemy.type.splitCount; index++) {
            const child = splitEnemy(this.nextEnemy++, enemy.type.splitInto, enemy);
            this.registerEnemy(child, `E${enemy.number}`);
        }
    }

    leak(enemy) {
        enemy.alive = false;
        this.enemies.delete(enemy.number);
        const lost = Math.min(this.lives, enemy.type.lives);
        this.lives -= lost;
        this.active.leaks++;
        this.active.livesLost += lost;
        enemy.type.leaked++;
        this.event(`LEAK E${enemy.number} ${enemy.type.name} lives ${this.lives}`);
        if (this.lives === 0) {
            this.active.status = 'lost';
            this.active.end = this.tick;
            this.active.gold = this.gold;
            this.active.lives = this.lives;
            this.outcome = 'defeat';
            this.event('DEFEAT');
        }
    }

    moveEnemies() {
        const moving = [...this.enemies.values()];
        for (const enemy of moving) {
            if (enemy.burn.remaining > 0) {
                const source = enemy.burn.source;
                const damage = Math.min(enemy.hp, enemy.burn.strength);
                enemy.hp -= damage;
                this.creditDamage(enemy, source, damage);
                advanceEffect(enemy.burn);
                if (enemy.hp === 0) {
                    this.kill(enemy, source);
                    continue;
                }
            }
            enemy.hp = Math.min(enemy.maximum, enemy.hp + enemy.type.regen);
            let speed = slowedSpeed(enemy);
            let arrived = false;
            if (enemy.type.movement === 'air') {
                const moved = advancePoint(enemy.point, this.map.center(this.map.exit), speed);
                enemy.point = moved.point;
                arrived = moved.arrived;
            } else {
                if (this.map.water(occupiedCell(enemy, this.map))) speed = Math.floor(speed / 2);
                while (speed > 0) {
                    const remaining = 100 - enemy.progress;
                    if (speed < remaining) {
                        enemy.progress += speed;
                        speed = 0;
                    } else {
                        speed -= remaining;
                        enemy.current = enemy.next;
                        enemy.progress = 0;
                        if (enemy.current === this.map.exit) {
                            arrived = true;
                            break;
                        }
                        enemy.next = nextCell(this.map, this.distances, enemy.current);
                    }
                }
            }
            if (arrived) {
                this.leak(enemy);
                if (this.outcome === 'defeat') return;
            }
        }
    }

    fireTowers() {
        for (const tower of this.towers) {
            if (tower.sold !== null || this.tick < tower.ready) continue;
            const enemy = chooseTarget(tower, this.enemies.values(), this.map, this.distances);
            if (enemy === null) continue;
            const projectile = createProjectile(this.nextProjectile++, tower, enemy,
                this.map.center(tower.cell), position(enemy, this.map));
            this.projectiles.set(projectile.number, projectile);
            tower.shots++;
            tower.ready = this.tick + tower.type.levels[tower.level - 1].interval;
            this.event(`SHOT T${tower.number} E${enemy.number}`);
        }
    }

    moveProjectiles() {
        for (const projectile of this.projectiles.values()) {
            const aim = projectile.target.alive ? position(projectile.target, this.map) : null;
            if (!moveProjectile(projectile, aim)) continue;
            this.projectiles.delete(projectile.number);
            const performance = projectile.performance;
            let victims;
            if (performance.splash === 0) victims = projectile.target.alive ? [projectile.target] : [];
            else victims = [...this.enemies.values()].filter(enemy => canAim(projectile.targets, enemy)
                && squaredDistance(position(enemy, this.map), projectile.aim) <= performance.splash * performance.splash);
            const tower = projectile.tower;
            if (victims.length === 0) tower.fizzles++;
            for (const enemy of victims) {
                tower.hits++;
                const damage = armoredDamage(enemy.hp, performance.power, enemy.type.armor);
                enemy.hp -= damage;
                this.creditDamage(enemy, tower, damage);
                if (enemy.hp === 0) this.kill(enemy, tower);
                else {
                    if (performance.slowRate > 0) receiveEffect(enemy.slow, performance.slowRate, performance.slowTime);
                    if (performance.burnAmount > 0) receiveEffect(enemy.burn, performance.burnAmount, performance.burnTime, tower);
                }
            }
        }
    }

    finishWave() {
        const record = this.active;
        if (record === null || this.enemies.size > 0 || record.groups.some(group => group.appeared < group.count)) return;
        record.reward = record.wave.reward;
        this.gold += record.reward;
        record.interest = Math.min(this.settings.interestCap, Math.floor(this.gold * this.settings.interestRate / 100));
        this.gold += record.interest;
        this.income.reward += record.reward;
        this.income.interest += record.interest;
        record.end = this.tick;
        record.status = 'cleared';
        record.gold = this.gold;
        record.lives = this.lives;
        this.cleared++;
        if (record.leaks === 0) this.perfect++;
        this.event(`WAVE_END ${record.number} reward ${record.reward} interest ${record.interest} gold ${this.gold}`);
        this.active = null;
        if (this.started === this.data.waves.length) {
            this.outcome = 'victory';
            this.event('VICTORY');
        } else this.nextStart = this.tick + this.settings.interval;
    }

    gridLines(cells) {
        const lines = ['  ' + Array.from({ length: this.map.width }, (_, x) => x % 10).join('')];
        for (let y = 0; y < this.map.height; y++) {
            lines.push(`${y % 10} ${cells.slice(y * this.map.width, (y + 1) * this.map.width).join('')}`);
        }
        return lines;
    }

    mapPicture() {
        const cells = this.map.cells.slice();
        for (const spawn of this.map.spawns) {
            for (const cell of spawnPath(this.map, this.distances, spawn.cell)) {
                if (this.map.cells[cell] === '.' || this.map.cells[cell] === '~') cells[cell] = '+';
            }
        }
        for (const tower of this.standing.values()) cells[tower.cell] = tower.type.symbol;
        const occupied = new Map();
        for (const enemy of this.enemies.values()) {
            const cell = occupiedCell(enemy, this.map);
            if (occupied.has(cell)) occupied.set(cell, '*');
            else occupied.set(cell, enemy.type.symbol);
        }
        for (const [cell, symbol] of occupied) cells[cell] = symbol;
        return cells;
    }

    flowPicture() {
        return this.map.cells.map((terrain, cell) => {
            if (terrain === '#') return '#';
            if (cell === this.map.exit) return 'E';
            if (this.standing.has(cell)) return this.standing.get(cell).type.symbol;
            if (this.distances[cell] < 0) return '?';
            const current = this.map.coordinates(cell);
            const next = this.map.coordinates(nextCell(this.map, this.distances, cell));
            return DIRECTIONS.find(direction => current.x + direction.x === next.x && current.y + direction.y === next.y).symbol;
        });
    }

    coveragePicture() {
        return this.map.cells.map((terrain, cell) => {
            if (terrain === '#') return '#';
            if (this.standing.has(cell)) return this.standing.get(cell).type.symbol;
            let count = 0;
            for (const tower of this.standing.values()) {
                const range = tower.type.levels[tower.level - 1].range;
                if (squaredDistance(this.map.center(cell), this.map.center(tower.cell)) <= range * range) count++;
            }
            return digit(count);
        });
    }

    killsPicture() {
        return this.map.cells.map((terrain, cell) => this.killCounts[cell] > 0
            ? digit(this.killCounts[cell]) : terrain === '#' ? '#' : '.');
    }

    snapshot(final) {
        const next = this.active === null && this.outcome === null ? this.nextStart : '-';
        const lines = [`${final ? 'FINAL' : 'SNAPSHOT'} ${this.tick} wave ${this.started} next ${next} gold ${this.gold} lives ${this.lives}`];
        appendLines(lines, this.gridLines(this.mapPicture()));
        for (const spawn of this.map.spawns) lines.push(`PATH ${spawn.number} length ${this.distances[spawn.cell]}`);
        for (const tower of this.towers) {
            if (tower.sold === null) lines.push(`T${tower.number} ${tower.type.name} ${tower.x} ${tower.y} level ${tower.level} mode ${tower.mode} ready ${tower.ready}`);
        }
        for (const enemy of this.enemies.values()) {
            const point = position(enemy, this.map);
            lines.push(`E${enemy.number} ${enemy.type.name} ${point.x} ${point.y} hp ${enemy.hp}/${enemy.maximum} slow ${enemy.slow.strength} ${enemy.slow.remaining} burn ${enemy.burn.strength} ${enemy.burn.remaining}`);
        }
        for (const projectile of this.projectiles.values()) {
            lines.push(`P${projectile.number} T${projectile.tower.number} E${projectile.target.number} ${projectile.point.x} ${projectile.point.y}`);
        }
        if (final) {
            lines.push('FLOW');
            appendLines(lines, this.gridLines(this.flowPicture()));
            lines.push('COVERAGE');
            appendLines(lines, this.gridLines(this.coveragePicture()));
            lines.push('KILLS');
            appendLines(lines, this.gridLines(this.killsPicture()));
        }
        return lines;
    }

    wavesReport() {
        const header = 'wave,start,end,status,spawned,peak,kills,leaks,lives_lost,bounty,reward,interest,gold,lives';
        const columns = this.towers.map(tower => `T${tower.number}`);
        const lines = [[header, ...columns].join(',')];
        for (const record of this.waveRecords) {
            const values = [record.number, record.start, record.end, record.status, record.spawned, record.peak,
                record.kills, record.leaks, record.livesLost, record.bounty, record.reward, record.interest, record.gold, record.lives];
            for (const tower of this.towers) values.push(record.damage.get(tower.number) ?? 0);
            lines.push(values.join(','));
        }
        return lines;
    }

    summaryReport() {
        let spawned = 0;
        let killed = 0;
        let leaked = 0;
        for (const type of this.data.enemyTypes.values()) {
            spawned += type.spawned;
            killed += type.killed;
            leaked += type.leaked;
        }
        let damage = 0;
        let mvp = null;
        for (const tower of this.towers) {
            damage += tower.damage;
            if (mvp === null || tower.damage > mvp.damage) mvp = tower;
        }
        const income = this.income;
        const score = 10 * killed + 100 * this.lives + 50 * this.perfect + this.gold;
        const lines = [
            `outcome ${this.outcome}`, `ticks ${this.tick}`,
            `waves ${this.cleared}/${this.data.waves.length} perfect ${this.perfect}`,
            `lives ${this.lives}/${this.settings.lives}`, `gold ${this.gold}`,
            `enemies spawned ${spawned} killed ${killed} leaked ${leaked}`,
            `income bounty ${income.bounty} reward ${income.reward} interest ${income.interest} early ${income.early} refund ${income.refund}`,
            `spent ${this.spent}`, `damage ${damage}`,
            `actions total ${this.data.actions.length} done ${this.succeeded} refused ${this.refused} unused ${this.data.actions.length - this.actionIndex}`,
            `score ${score}`, mvp === null ? 'mvp -' : `mvp T${mvp.number} damage ${mvp.damage}`,
        ];
        for (const type of this.data.enemyTypes.values()) {
            lines.push(`ENEMY ${type.name} spawned ${type.spawned} killed ${type.killed} leaked ${type.leaked} damage ${type.damage}`);
        }
        for (const tower of this.towers) {
            const state = tower.sold === null ? 'active' : `sold ${tower.sold}`;
            lines.push(`TOWER T${tower.number} ${tower.type.name} ${tower.x} ${tower.y} level ${tower.level} mode ${tower.mode} ${state} shots ${tower.shots} hits ${tower.hits} fizzles ${tower.fizzles} kills ${tower.kills} damage ${tower.damage} per_shot ${decimalOne(tower.damage, tower.shots)} share ${decimalOne(100 * tower.damage, damage)} invested ${tower.investment}`);
        }
        return lines;
    }

    run() {
        while (this.outcome === null) {
            this.actions();
            this.startAndSpawn();
            this.moveEnemies();
            if (this.outcome === 'defeat') break;
            this.fireTowers();
            this.moveProjectiles();
            this.finishWave();
            if (this.settings.snapshots.has(this.tick)) appendLines(this.snapshots, this.snapshot(false));
            if (this.outcome !== null) break;
            this.tick++;
        }
        appendLines(this.snapshots, this.snapshot(true));
    }

    writeReports() {
        const reports = {
            'events.txt': this.events, 'waves.csv': this.wavesReport(),
            'snapshots.txt': this.snapshots, 'summary.txt': this.summaryReport(),
        };
        fs.mkdirSync('output', { recursive: true });
        for (const [name, lines] of Object.entries(reports)) {
            fs.writeFileSync(`output/${name}`, lines.length === 0 ? '' : lines.join('\n') + '\n', 'ascii');
        }
    }
}

function main() {
    const game = new Game(readInputs());
    game.run();
    game.writeReports();
}

if (require.main === module) main();
