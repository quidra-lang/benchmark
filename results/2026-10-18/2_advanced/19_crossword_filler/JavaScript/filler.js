'use strict';

function copyState(state) {
    return { cells: state.cells.slice(), assigned: state.assigned.slice(), used: new Set(state.used) };
}

const slotPattern = (slot, state) => slot.cells.map(cell => state.cells[cell]).join('');

function attempt(initial, slots, index, minimum, budget) {
    const state = copyState(initial);
    const result = { minimum, budget, nodes: 0, backtracks: 0, prunes: 0, deadEnds: 0,
        maxDepth: 0, best: copyState(initial), failures: slots.map(() => 0), trace: [], order: [] };
    function candidates(slot) {
        return index.candidates(slotPattern(slot, state), minimum, state.used);
    }
    function search() {
        let chosen = null;
        let words = null;
        for (const slot of slots) {
            if (state.assigned[slot.index] !== null) continue;
            const current = candidates(slot);
            if (words === null || current.length < words.length) {
                chosen = slot;
                words = current;
            }
        }
        if (chosen === null) return 'complete';
        if (words.length === 0) {
            result.deadEnds++;
            result.failures[chosen.index]++;
            return 'fail';
        }
        for (const word of words) {
            if (result.nodes === budget) return 'abort';
            result.nodes++;
            state.assigned[chosen.index] = word;
            state.used.add(word.word);
            const changed = [];
            for (let position = 0; position < chosen.length; position++) {
                const cell = chosen.cells[position];
                if (state.cells[cell] !== '.') continue;
                changed.push(cell);
                state.cells[cell] = word.word[position];
            }
            result.order.push(chosen.index);
            let wiped = null;
            for (const crossing of chosen.crossing) {
                if (state.assigned[crossing] === null && candidates(slots[crossing]).length === 0) {
                    wiped = crossing;
                    break;
                }
            }
            if (result.nodes <= 10) result.trace.push(chosen.label + '=' + word.word + (wiped === null ? '' : '!'));
            let outcome;
            if (wiped !== null) {
                result.prunes++;
                result.failures[wiped]++;
                outcome = 'fail';
            } else {
                if (result.order.length > result.maxDepth) {
                    result.maxDepth = result.order.length;
                    result.best = copyState(state);
                }
                outcome = search();
            }
            if (outcome !== 'fail') return outcome;
            state.assigned[chosen.index] = null;
            state.used.delete(word.word);
            for (const cell of changed) state.cells[cell] = '.';
            result.order.pop();
            result.backtracks++;
        }
        return 'fail';
    }
    const outcome = search();
    result.outcome = { complete: 'filled', fail: 'unfillable', abort: 'budget' }[outcome];
    result.final = outcome === 'complete' ? state : result.best;
    return result;
}

module.exports = { copyState, slotPattern, attempt };
