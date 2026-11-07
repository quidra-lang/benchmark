'use strict';

const fs = require('node:fs');

class MoleculeError extends Error {
  constructor(reason, column) { super(reason); this.reason = reason; this.column = column; }
}

function dataLines(path) {
  return fs.readFileSync(path, 'ascii').split('\n').slice(0, -1).map((text, index) => ({ text, line: index + 1 }))
    .filter(record => record.text !== '' && !record.text.startsWith('#'));
}

function readElements(path) {
  const elements = new Map();
  for (const { text } of dataLines(path)) {
    const [symbol, number, mass, valences] = text.split(' '), values = valences.split(',').map(Number);
    elements.set(symbol, { symbol, number: Number(number), mass: Number(mass), valences: values, base: values[0], maximum: values[values.length - 1] });
  }
  return elements;
}

class Molecule {
  constructor() { this.atoms = []; this.bonds = []; }
  addAtom(atom) {
    const index = this.atoms.length;
    this.atoms.push({ ...atom, index, neighbors: [], ring: false }); return index;
  }
  addBond(first, second, rawType) {
    const bond = { a: Math.min(first, second), b: Math.max(first, second), rawType, type: null, multiplicity: 0, ring: false };
    this.bonds.push(bond);
    this.atoms[first].neighbors.push({ atom: second, bond }); this.atoms[second].neighbors.push({ atom: first, bond });
    return bond;
  }
  bond(first, second) { return this.atoms[first].neighbors.find(neighbor => neighbor.atom === second)?.bond; }
  finalize() {
    this.bonds.sort((a, b) => a.a - b.a || a.b - b.b);
    this.bonds.forEach((bond, index) => { bond.index = index; });
    for (const atom of this.atoms) atom.neighbors.sort((a, b) => a.atom - b.atom);
    return this;
  }
}

const baseTotal = atom => atom.neighbors.reduce((sum, neighbor) => sum + (neighbor.bond.type === 4 ? 1 : neighbor.bond.type), 0);
const multiplicityTotal = atom => atom.neighbors.reduce((sum, neighbor) => sum + neighbor.bond.multiplicity, 0);
const needsPi = (atom, hydrogens = atom.hydrogens) => atom.aromatic && atom.element.base + atom.charge >= baseTotal(atom) + hydrogens + 1;
function organicHydrogens(atom) {
  const bonds = multiplicityTotal(atom), valence = atom.element.valences.find(value => value >= bonds);
  return valence === undefined ? null : valence - bonds;
}

module.exports = { MoleculeError, dataLines, readElements, Molecule, baseTotal, multiplicityTotal, needsPi, organicHydrogens };
