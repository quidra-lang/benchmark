'use strict';

class Round {
    constructor(variables, clauses) {
        this.variables = variables;
        this.clauses = clauses.map(clause => clause.slice());
        this.values = Array(variables + 1).fill(0);
        this.trail = [];
        this.position = 0;
        this.watches = new Map();
        this.depth = 0;
        this.statistics = { decisions: 0, propagations: 0, conflicts: 0, maxDepth: 0 };
        this.events = [];
    }

    value(literal) {
        return this.values[Math.abs(literal)] * (literal > 0 ? 1 : -1);
    }

    watch(literal) {
        if (!this.watches.has(literal)) this.watches.set(literal, []);
        return this.watches.get(literal);
    }

    assign(literal, kind) {
        this.values[Math.abs(literal)] = literal > 0 ? 1 : -1;
        this.trail.push({ literal, kind });
        this.events.push(kind + literal);
        if (kind !== 'P') this.depth++;
    }

    conflict() {
        this.statistics.conflicts++;
        this.events.push('C');
        return false;
    }

    initialize() {
        this.clauses.forEach((clause, index) => {
            if (clause.length < 2) return;
            this.watch(clause[0]).push(index);
            this.watch(clause[1]).push(index);
        });
        for (const clause of this.clauses) {
            if (clause.length === 0 || (clause.length === 1 && this.value(clause[0]) < 0)) return this.conflict();
            if (clause.length === 1 && this.value(clause[0]) === 0) {
                this.assign(clause[0], 'P');
                this.statistics.propagations++;
            }
        }
        return true;
    }

    propagate() {
        while (this.position < this.trail.length) {
            const falseLiteral = -this.trail[this.position++].literal;
            const list = this.watch(falseLiteral);
            let index = 0;
            while (index < list.length) {
                const clauseNumber = list[index];
                const clause = this.clauses[clauseNumber];
                if (clause[0] === falseLiteral) [clause[0], clause[1]] = [clause[1], clause[0]];
                if (this.value(clause[0]) > 0) {
                    index++;
                    continue;
                }
                let replacement = 2;
                while (replacement < clause.length && this.value(clause[replacement]) < 0) replacement++;
                if (replacement < clause.length) {
                    [clause[1], clause[replacement]] = [clause[replacement], clause[1]];
                    list.splice(index, 1);
                    this.watch(clause[1]).push(clauseNumber);
                    continue;
                }
                if (this.value(clause[0]) < 0) return this.conflict();
                this.assign(clause[0], 'P');
                this.statistics.propagations++;
                index++;
            }
        }
        return true;
    }

    decide() {
        const positive = Array(this.variables + 1).fill(0);
        const negative = Array(this.variables + 1).fill(0);
        for (const clause of this.clauses) {
            if (clause.some(literal => this.value(literal) > 0)) continue;
            for (const literal of clause) {
                if (this.value(literal) === 0) (literal > 0 ? positive : negative)[Math.abs(literal)]++;
            }
        }
        let chosen = 0;
        let count = 0;
        for (let variable = 1; variable <= this.variables; variable++) {
            if (positive[variable] > count) {
                count = positive[variable];
                chosen = variable;
            }
            if (negative[variable] > count) {
                count = negative[variable];
                chosen = -variable;
            }
        }
        if (chosen === 0) return false;
        this.assign(chosen, 'D');
        this.statistics.decisions++;
        this.statistics.maxDepth = Math.max(this.statistics.maxDepth, this.depth);
        return true;
    }

    removeLast() {
        const item = this.trail.pop();
        this.values[Math.abs(item.literal)] = 0;
        if (item.kind !== 'P') this.depth--;
        return item;
    }

    backtrack() {
        while (this.trail.length > 0 && this.trail.at(-1).kind !== 'D') this.removeLast();
        if (this.trail.length === 0) return false;
        const decision = this.removeLast();
        this.position = this.trail.length;
        this.assign(-decision.literal, 'F');
        return true;
    }

    finish(satisfiable) {
        return { satisfiable, model: satisfiable ? this.values.map(value => value > 0) : null,
            statistics: this.statistics, events: this.events };
    }

    run() {
        if (!this.initialize()) return this.finish(false);
        while (true) {
            if (!this.propagate()) {
                if (!this.backtrack()) return this.finish(false);
            } else if (!this.decide()) return this.finish(true);
        }
    }
}

function solveRound(variables, clauses) {
    return new Round(variables, clauses).run();
}

module.exports = { solveRound };
