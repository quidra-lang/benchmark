import type { Slot } from './slots.ts';
import { WordIndex, type WordEntry } from './word_index.ts';
export interface State {
  cells: string[];
  assigned: (WordEntry | null)[];
  used: Set<string>;
}
export type Outcome = 'filled' | 'unfillable' | 'budget';
export interface Attempt {
  minimum: number;
  budget: number;
  nodes: number;
  backtracks: number;
  prunes: number;
  deadEnds: number;
  maxDepth: number;
  best: State;
  failures: number[];
  trace: string[];
  order: number[];
  outcome: Outcome;
  final: State;
}
export function copyState(state: State): State {
  return { cells: [...state.cells], assigned: [...state.assigned], used: new Set(state.used) };
}
export function slotPattern(slot: Slot, state: State): string {
  return slot.cells.map((cell) => state.cells[cell]).join('');
}
export function attempt(
  initial: State,
  slots: Slot[],
  index: WordIndex,
  minimum: number,
  budget: number,
): Attempt {
  const state = copyState(initial);
  const result: Attempt = {
    minimum,
    budget,
    nodes: 0,
    backtracks: 0,
    prunes: 0,
    deadEnds: 0,
    maxDepth: 0,
    best: copyState(initial),
    failures: slots.map(() => 0),
    trace: [],
    order: [],
    outcome: 'unfillable',
    final: copyState(initial),
  };
  const candidates = (slot: Slot) =>
    index.candidates(slotPattern(slot, state), minimum, state.used);
  function search(): 'complete' | 'fail' | 'abort' {
    let chosen: Slot | undefined;
    let words: WordEntry[] | undefined;
    for (const slot of slots) {
      if (state.assigned[slot.index] !== null) continue;
      const current = candidates(slot);
      if (!words || current.length < words.length) {
        chosen = slot;
        words = current;
      }
    }
    if (!chosen || !words) return 'complete';
    if (!words.length) {
      result.deadEnds++;
      result.failures[chosen.index]++;
      return 'fail';
    }
    for (const word of words) {
      if (result.nodes === budget) return 'abort';
      result.nodes++;
      state.assigned[chosen.index] = word;
      state.used.add(word.word);
      const changed: number[] = [];
      chosen.cells.forEach((cell, position) => {
        if (state.cells[cell] === '.') {
          changed.push(cell);
          state.cells[cell] = word.word[position];
        }
      });
      result.order.push(chosen.index);
      const wiped = chosen.crossing.find(
        (i) => state.assigned[i] === null && candidates(slots[i]).length === 0,
      );
      if (result.nodes <= 10) {
        result.trace.push(`${chosen.label}=${word.word}${wiped === undefined ? '' : '!'}`);
      }
      let outcome: 'complete' | 'fail' | 'abort';
      if (wiped !== undefined) {
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
  result.outcome = outcome === 'complete' ? 'filled' : outcome === 'fail' ? 'unfillable' : 'budget';
  result.final = outcome === 'complete' ? state : result.best;
  return result;
}
