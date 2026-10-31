import {dereference} from './terms.ts';

class Trail {
  declare bindings: any;
  constructor() { this.bindings = []; }
  mark() { return this.bindings.length; }
  bind(variable, term) {
    this.bindings.push(variable);
    variable.binding = term;
  }
  undo(mark) {
    while (this.bindings.length > mark) this.bindings.pop().binding = null;
  }
  unify(first, second) {
    const pending = [[first, second]];
    while (pending.length > 0) {
      let [left, right] = pending.pop();
      left = dereference(left);
      right = dereference(right);
      if (left === right) continue;
      if (left.kind === 'variable') { this.bind(left, right); continue; }
      if (right.kind === 'variable') { this.bind(right, left); continue; }
      if (left.kind !== right.kind) return false;
      if (left.kind === 'integer') {
        if (left.value !== right.value) return false;
      } else if (left.kind === 'atom') {
        if (left.name !== right.name) return false;
      } else {
        if (left.name !== right.name || left.args.length !== right.args.length) return false;
        for (let index = left.args.length - 1; index >= 0; index--) pending.push([left.args[index], right.args[index]]);
      }
    }
    return true;
  }
}

function identical(first, second) {
  const pending = [[first, second]];
  while (pending.length > 0) {
    let [left, right] = pending.pop();
    left = dereference(left);
    right = dereference(right);
    if (left === right) continue;
    if (left.kind !== right.kind || left.kind === 'variable') return false;
    if (left.kind === 'integer') {
      if (left.value !== right.value) return false;
    } else if (left.kind === 'atom') {
      if (left.name !== right.name) return false;
    } else {
      if (left.name !== right.name || left.args.length !== right.args.length) return false;
      for (let index = left.args.length - 1; index >= 0; index--) pending.push([left.args[index], right.args[index]]);
    }
  }
  return true;
}

export {Trail, identical};
