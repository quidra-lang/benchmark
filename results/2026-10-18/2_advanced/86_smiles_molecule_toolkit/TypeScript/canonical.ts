import {ORGANIC,AROMATIC} from './smiles_parser.ts';
import {needsPi,organicHydrogens} from './molecule.ts';
import type {Molecule} from './molecule.ts';
import type {Atom,Bond,Neighbor} from './types.ts';

type RankValue = number | RankValue[];

export function compareValues(first:RankValue,second:RankValue):number {
  if (!Array.isArray(first)) return (first as number) - (second as number);
  for (let i = 0; i < Math.min(first.length, (second as RankValue[]).length); i++) {
    const difference = compareValues(first[i], (second as RankValue[])[i]);
    if (difference !== 0) return difference;
  }
  return first.length - (second as RankValue[]).length;
}

export function denseRanks(values:RankValue[]):number[] {
  const indices = values.map((value, i) => i).sort((a, b) => compareValues(values[a], values[b]));
  const ranks:number[] = Array(values.length);
  let rank = 0, previous:RankValue|null = null;
  for (const index of indices) {
    if (previous === null || compareValues(values[index], previous) !== 0) rank++;
    ranks[index] = rank; previous = values[index];
  }
  return ranks;
}

export function refine(molecule:Molecule,initial:number[]):number[] {
  let ranks = initial;
  while (true) {
    const values = molecule.atoms.map((atom, i) => [ranks[i], atom.neighbors
      .map(neighbor => [ranks[neighbor.atom], neighbor.bond.type!]).sort(compareValues)]);
    const next = denseRanks(values), unchanged = new Set(next).size === new Set(ranks).size;
    ranks = next;
    if (unchanged) return ranks;
  }
}

export function canonicalRanks(molecule:Molecule):{ranks:number[];classes:number} {
  const invariants = molecule.atoms.map(atom => [atom.neighbors.length, atom.element.number, atom.mass,
    atom.charge, atom.hydrogens, atom.aromatic ? 1 : 0]);
  let ranks = refine(molecule, denseRanks(invariants));
  const classes = new Set(ranks).size;
  while (new Set(ranks).size < molecule.atoms.length) {
    const counts = new Map<number,number>();
    for (const rank of ranks) counts.set(rank, (counts.get(rank) || 0) + 1);
    const tied = Math.min(...Array.from(counts.keys()).filter(rank => counts.get(rank)! > 1)), atom = ranks.indexOf(tied);
    ranks = refine(molecule, denseRanks(ranks.map((rank, i) => 2 * rank - (i === atom ? 1 : 0))));
  }
  return { ranks, classes };
}

export function atomText(atom:Atom):string {
  const symbol = atom.aromatic ? atom.element.symbol.toLowerCase() : atom.element.symbol;
  const organic = ORGANIC.has(atom.element.symbol) && (!atom.aromatic || AROMATIC.has(symbol));
  if (organic && atom.mass === 0 && atom.charge === 0 && (!atom.aromatic || needsPi(atom) === needsPi(atom, 0))
      && organicHydrogens(atom) === atom.hydrogens) return symbol;
  const mass = atom.mass === 0 ? '' : String(atom.mass);
  const hydrogen = atom.hydrogens === 0 ? '' : atom.hydrogens === 1 ? 'H' : 'H' + atom.hydrogens;
  const charge = atom.charge === 0 ? '' : (atom.charge > 0 ? '+' : '-') + (Math.abs(atom.charge) === 1 ? '' : Math.abs(atom.charge));
  return '[' + mass + symbol + hydrogen + charge + ']';
}

export function bondText(molecule:Molecule,bond:Bond):string {
  const inRingAromatic = molecule.atoms[bond.a].aromatic && molecule.atoms[bond.b].aromatic && bond.ring;
  if (bond.type === 1) return inRingAromatic ? '-' : '';
  if (bond.type === 2) return '=';
  if (bond.type === 3) return '#';
  return inRingAromatic ? '' : ':';
}

export function canonicalize(molecule:Molecule):{smiles:string;ranks:number[];classes:number} {
  const { ranks, classes } = canonicalRanks(molecule), start = ranks.indexOf(1), visited = new Set<number>();
  const children:Neighbor[][] = molecule.atoms.map(() => []), order:number[] = Array(molecule.atoms.length), closures = new Set<number>();
  const visit = (atom:number, incoming:Bond|null):void => {
    visited.add(atom); order[atom] = visited.size;
    const neighbors = molecule.atoms[atom].neighbors.slice().sort((a, b) => ranks[a.atom] - ranks[b.atom]);
    for (const neighbor of neighbors) {
      if (neighbor.bond === incoming || closures.has(neighbor.bond.index)) continue;
      if (!visited.has(neighbor.atom)) { children[atom].push(neighbor); visit(neighbor.atom, neighbor.bond); }
      else closures.add(neighbor.bond.index);
    }
  };
  visit(start, null);
  const assignments = new Map<number,number>(), occupied = new Set<number>();
  const ringNumber = (number:number):string => number < 10 ? String(number) : '%' + String(number).padStart(2, '0');
  const write = (atom:number):string => {
    let text = atomText(molecule.atoms[atom]);
    const ends = molecule.atoms[atom].neighbors.filter(neighbor => closures.has(neighbor.bond.index)).sort((a, b) => order[a.atom] - order[b.atom]);
    for (const neighbor of ends) {
      const index = neighbor.bond.index;
      if (assignments.has(index)) {
        const number = assignments.get(index)!; text += ringNumber(number); assignments.delete(index); occupied.delete(number);
      } else {
        let number = 1;
        while (occupied.has(number)) number++;
        assignments.set(index, number); occupied.add(number); text += bondText(molecule, neighbor.bond) + ringNumber(number);
      }
    }
    children[atom].forEach((child, i) => {
      const branch = bondText(molecule, child.bond) + write(child.atom);
      text += i + 1 === children[atom].length ? branch : '(' + branch + ')';
    });
    return text;
  };
  return { smiles: write(start), ranks, classes };
}

