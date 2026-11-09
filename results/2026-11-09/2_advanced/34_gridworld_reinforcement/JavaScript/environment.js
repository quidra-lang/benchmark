'use strict';

const fs = require('node:fs');

const ACTIONS = ['N', 'E', 'S', 'W'];

class World {
    constructor(height, width, rows, wind, rewards) {
        this.height = height;
        this.width = width;
        this.cells = rows.join('').split('');
        this.wind = wind;
        this.states = [];
        this.terminals = [];
        this.index = Array(this.cells.length).fill(-1);
        this.terminalAt = Array(this.cells.length).fill(null);
        this.cells.forEach((terrain, cell) => {
            if (terrain === '#') return;
            if (terrain === 'G' || terrain === 'P') {
                const number = this.terminals.length;
                const terminal = { cell, number, reward: rewards[number],
                    ending: terrain === 'G' ? 'goal' : 'pit', symbol: String.fromCharCode(97 + number) };
                this.terminals.push(terminal);
                this.terminalAt[cell] = terminal;
            } else {
                this.index[cell] = this.states.length;
                this.states.push(cell);
                if (terrain === 'S') this.start = cell;
            }
        });
        this.startIndex = this.index[this.start];
        this.moves = this.states.map(cell => ACTIONS.map((_, action) => this.move(cell, action)));
    }

    move(cell, action) {
        const offsets = [-this.width, 1, this.width, -1];
        let reached = cell + offsets[action];
        if (this.cells[reached] === '#') reached = cell;
        if (this.terminalAt[reached] !== null) return reached;
        const strength = this.wind[cell % this.width];
        for (let step = 0; step < strength; step++) {
            if (this.cells[reached - this.width] === '#') break;
            reached -= this.width;
            if (this.terminalAt[reached] !== null) break;
        }
        return reached;
    }
}

function readWorld() {
    const lines = fs.readFileSync('input/world.txt', 'ascii').slice(0, -1).split('\n');
    const height = Number(lines[0].split(' ')[1]);
    const width = Number(lines[1].split(' ')[1]);
    const wind = [...lines[height + 2].split(' ')[1]].map(Number);
    const rewards = lines[height + 3].split(' ').slice(1).map(Number);
    return new World(height, width, lines.slice(2, height + 2), wind, rewards);
}

class Minstd {
    constructor(seed) {
        this.state = seed;
    }

    draw() {
        this.state = (48271 * this.state) % 2147483647;
        return this.state;
    }
}

class TransitionModel {
    constructor(world, denominator, floorSlip, iceSlip, stepReward) {
        this.world = world;
        this.denominator = denominator;
        this.floorSlip = floorSlip;
        this.iceSlip = iceSlip;
        this.stepReward = stepReward;
        this.transitions = world.states.map((_, state) => ACTIONS.map((__, action) => {
            const slip = this.slip(state);
            const outcomes = [[action, denominator - 2 * slip], [(action + 1) % 4, slip], [(action + 3) % 4, slip]];
            return outcomes.filter(([, weight]) => weight > 0).map(([direction, weight]) => ({
                ...this.arrival(state, direction), weight,
            }));
        }));
    }

    slip(state) {
        return this.world.cells[this.world.states[state]] === '~' ? this.iceSlip : this.floorSlip;
    }

    arrival(state, direction) {
        const cell = this.world.moves[state][direction];
        const terminal = this.world.terminalAt[cell];
        return { cell, next: this.world.index[cell], reward: terminal === null ? this.stepReward : terminal.reward };
    }

    step(state, action, generator) {
        const value = generator.draw() % this.denominator;
        const slip = this.slip(state);
        const direction = value < this.denominator - 2 * slip ? action
            : value < this.denominator - slip ? (action + 1) % 4 : (action + 3) % 4;
        return this.arrival(state, direction);
    }
}

module.exports = { ACTIONS, World, readWorld, Minstd, TransitionModel };
