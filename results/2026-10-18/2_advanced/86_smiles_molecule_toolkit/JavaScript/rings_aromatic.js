'use strict';

const { MoleculeError } = require('./molecule');

function compareSequence(a, b) {
  for (let i = 0; i < Math.min(a.length, b.length); i++) if (a[i] !== b[i]) return a[i] - b[i];
  return a.length - b.length;
}

function normalizeRing(sequence) {
  const minimum = Math.min(...sequence), index = sequence.indexOf(minimum), ring = sequence.slice(index).concat(sequence.slice(0, index));
  return ring[1] < ring[ring.length - 1] ? ring : [ring[0], ...ring.slice(1).reverse()];
}

function findRings(molecule) {
  const candidates = [], seen = new Set(), size = molecule.atoms.length;
  for (let root = 0; root < size; root++) {
    const parent = Array(size).fill(-1), visited = Array(size).fill(false), queue = [root];
    visited[root] = true;
    for (let front = 0; front < queue.length; front++) {
      const atom = queue[front];
      for (const neighbor of molecule.atoms[atom].neighbors) if (!visited[neighbor.atom]) {
        visited[neighbor.atom] = true; parent[neighbor.atom] = atom; queue.push(neighbor.atom);
      }
    }
    const paths = Array.from({ length: size }, (_, atom) => {
      const path = [atom];
      while (path[path.length - 1] !== root) path.push(parent[path[path.length - 1]]);
      return path;
    });
    for (const bond of molecule.bonds) {
      if (parent[bond.a] === bond.b || parent[bond.b] === bond.a) continue;
      const left = paths[bond.a], right = paths[bond.b], shared = new Set(left.slice(0, -1));
      if (right.slice(0, -1).some(atom => shared.has(atom))) continue;
      const sequence = left.slice().reverse().concat(right.slice(0, -1));
      let mask = 0n;
      for (let i = 0; i < sequence.length; i++) mask ^= 1n << BigInt(molecule.bond(sequence[i], sequence[(i + 1) % sequence.length]).index);
      const key = mask.toString();
      if (!seen.has(key)) { seen.add(key); candidates.push({ sequence, mask, order: candidates.length }); }
    }
  }
  candidates.sort((a, b) => a.sequence.length - b.sequence.length || a.order - b.order);
  const basis = new Map(), selected = [];
  for (const candidate of candidates) {
    let reduced = candidate.mask;
    while (reduced !== 0n) {
      const pivot = reduced.toString(2).length - 1;
      if (!basis.has(pivot)) { basis.set(pivot, reduced); selected.push(normalizeRing(candidate.sequence)); break; }
      reduced ^= basis.get(pivot);
    }
  }
  selected.sort((a, b) => a.length - b.length || compareSequence(a, b));
  for (const ring of selected) for (let i = 0; i < ring.length; i++) {
    molecule.atoms[ring[i]].ring = true; molecule.bond(ring[i], ring[(i + 1) % ring.length]).ring = true;
  }
  molecule.rings = selected;
  return selected;
}

function kekulize(molecule, needed) {
  const visited = new Set(), paired = new Set(), doubleBonds = new Set();
  for (const start of needed) {
    if (visited.has(start)) continue;
    const queue = [start]; visited.add(start);
    for (let front = 0; front < queue.length; front++) {
      for (const neighbor of molecule.atoms[queue[front]].neighbors) {
        if (neighbor.bond.type === 4 && needed.has(neighbor.atom) && !visited.has(neighbor.atom)) {
          visited.add(neighbor.atom); queue.push(neighbor.atom);
        }
      }
    }
    const system = queue.sort((a, b) => a - b), members = new Set(system);
    const search = () => {
      const first = system.find(atom => !paired.has(atom));
      if (first === undefined) return true;
      for (const neighbor of molecule.atoms[first].neighbors) {
        if (neighbor.bond.type !== 4 || !members.has(neighbor.atom) || paired.has(neighbor.atom)) continue;
        paired.add(first); paired.add(neighbor.atom); doubleBonds.add(neighbor.bond.index);
        if (search()) return true;
        paired.delete(first); paired.delete(neighbor.atom); doubleBonds.delete(neighbor.bond.index);
      }
      return false;
    };
    if (!search()) throw new MoleculeError('kekulization failed', molecule.atoms[system[0]].column);
  }
  for (const bond of molecule.bonds) bond.multiplicity = bond.type === 4 ? doubleBonds.has(bond.index) ? 2 : 1 : bond.type;
}

module.exports = { compareSequence, normalizeRing, findRings, kekulize };
