import {readFileSync} from 'node:fs';
import type {Element,Atom,AtomSpec,Bond,MolecularProperties,RingSystem,Fingerprint,MoleculeRecord} from './types.ts';

export class MoleculeError extends Error {
  reason:string;
  column:number;
  constructor(reason:string,column:number) { super(reason); this.reason = reason; this.column = column; }
}

export function dataLines(path:string): MoleculeRecord[] {
  return readFileSync(path, 'ascii').split('\n').slice(0, -1).map((text, index) => ({ text, line: index + 1 }))
    .filter(record => record.text !== '' && !record.text.startsWith('#'));
}

export function readElements(path:string): Map<string,Element> {
  const elements = new Map<string,Element>();
  for (const { text } of dataLines(path)) {
    const [symbol, number, mass, valences] = text.split(' '), values = valences.split(',').map(Number);
    elements.set(symbol, { symbol, number: Number(number), mass: Number(mass), valences: values, base: values[0], maximum: values[values.length - 1] });
  }
  return elements;
}

export class Molecule {
  atoms:Atom[];
  bonds:Bond[];
  rings:number[][];
  name!:string;
  index!:number;
  properties!:MolecularProperties;
  canonical!:string;
  classes!:number;
  scaffold!:string|null;
  systems!:RingSystem[];
  fingerprint!:Fingerprint;
  constructor() {this.atoms=[];this.bonds=[];this.rings=[];}
  addAtom(atom:AtomSpec):number {
    const index = this.atoms.length;
    this.atoms.push({ ...atom, index, neighbors: [], ring: false } as Atom); return index;
  }
  addBond(first:number,second:number,rawType:number|null):Bond {
    const bond:Bond = { a: Math.min(first, second), b: Math.max(first, second), rawType, type: null, multiplicity: 0, ring: false, index:-1 };
    this.bonds.push(bond);
    this.atoms[first].neighbors.push({ atom: second, bond }); this.atoms[second].neighbors.push({ atom: first, bond });
    return bond;
  }
  bond(first:number,second:number):Bond|undefined { return this.atoms[first].neighbors.find(neighbor => neighbor.atom === second)?.bond; }
  finalize():Molecule {
    this.bonds.sort((a, b) => a.a - b.a || a.b - b.b);
    this.bonds.forEach((bond, index) => { bond.index = index; });
    for (const atom of this.atoms) atom.neighbors.sort((a, b) => a.atom - b.atom);
    return this;
  }
}

export const baseTotal = (atom:Atom):number => atom.neighbors.reduce((sum, neighbor) => sum + (neighbor.bond.type === 4 ? 1 : neighbor.bond.type!), 0);
export const multiplicityTotal = (atom:Atom):number => atom.neighbors.reduce((sum, neighbor) => sum + neighbor.bond.multiplicity, 0);
export const needsPi = (atom:Atom, hydrogens:number = atom.hydrogens):boolean => atom.aromatic && atom.element.base + atom.charge >= baseTotal(atom) + hydrogens + 1;
export function organicHydrogens(atom:Atom):number|null {
  const bonds = multiplicityTotal(atom), valence = atom.element.valences.find(value => value >= bonds);
  return valence === undefined ? null : valence - bonds;
}

