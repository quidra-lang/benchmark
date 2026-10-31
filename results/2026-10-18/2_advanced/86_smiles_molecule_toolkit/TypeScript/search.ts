import {MoleculeError,Molecule} from './molecule.ts';
import {organicAtom} from './smiles_parser.ts';
import type {Atom,AtomRead,Element,Bond,Fingerprint,Embeddings,Similarity} from './types.ts';

const choice = (atom:Atom): {symbol:string;aromatic:boolean} => ({ symbol: atom.element.symbol, aromatic: atom.aromatic });

export function readPatternAtom(text:string,start:number,elements:Map<string,Element>):AtomRead|null {
  const character = text[start];
  if (character === '*' || character === 'A' || character === 'a') {
    return { atom: { matcher: { kind: character }, column: start + 1 }, next: start + 1 };
  }
  if (character === '[') {
    const end = text.indexOf(']', start + 1);
    if (end < 0) throw new MoleculeError('unclosed bracket', start + 1);
    const choices: {symbol:string;aromatic:boolean}[] = [];
    for (const word of text.slice(start + 1, end).split(',')) {
      const parsed = organicAtom(word, 0, elements);
      if (parsed === null || parsed.next !== word.length) throw new MoleculeError('bad bracket atom', start + 1);
      choices.push(choice(parsed.atom as Atom));
    }
    return { atom: { matcher: { kind: 'list', choices }, column: start + 1 }, next: end + 1 };
  }
  const parsed = organicAtom(text, start, elements);
  if (parsed === null) return null;
  return { atom: { matcher: { kind: 'list', choices: [choice(parsed.atom as Atom)] }, column: start + 1 }, next: parsed.next };
}

export function matchesAtom(pattern:Atom,atom:Atom):boolean {
  const matcher = pattern.matcher!;
  if (matcher.kind === '*') return true;
  if (matcher.kind === 'A') return !atom.aromatic;
  if (matcher.kind === 'a') return atom.aromatic;
  return matcher.choices!.some(item => item.symbol === atom.element.symbol && item.aromatic === atom.aromatic);
}

export const matchesBond = (pattern:Bond,bond:Bond):boolean => pattern.rawType === null ? bond.type === 1 || bond.type === 4 : pattern.rawType === 5 || pattern.rawType === bond.type;

export function moleculePattern(molecule:Molecule):Molecule {
  const pattern = new Molecule();
  for (const atom of molecule.atoms) pattern.addAtom({ matcher: { kind: 'list', choices: [choice(atom)] } });
  for (const bond of molecule.bonds) pattern.addBond(bond.a, bond.b, bond.type);
  return pattern.finalize();
}

export function embeddings(pattern:Molecule,molecule:Molecule):Embeddings {
  let count = 0, first: number[] | null = null;
  const unique = new Set<string>(), assignment:number[] = [], used = new Set<number>();
  if (pattern.atoms.length > molecule.atoms.length) return { count, unique: 0, first };
  const candidates = pattern.atoms.map(atom => molecule.atoms.filter(candidate =>
    candidate.neighbors.length >= atom.neighbors.length && matchesAtom(atom, candidate)).map(candidate => candidate.index));
  const visit = (index:number):void => {
    if (index === pattern.atoms.length) {
      count++;
      if (first === null) first = assignment.map(atom => atom + 1);
      unique.add(assignment.slice().sort((a, b) => a - b).join(',')); return;
    }
    for (const atom of candidates[index]) {
      if (used.has(atom)) continue;
      let valid = true;
      for (const neighbor of pattern.atoms[index].neighbors) if (neighbor.atom < index) {
        const bond = molecule.bond(atom, assignment[neighbor.atom]);
        if (!bond || !matchesBond(neighbor.bond, bond)) { valid = false; break; }
      }
      if (!valid) continue;
      assignment.push(atom); used.add(atom); visit(index + 1); used.delete(atom); assignment.pop();
    }
  };
  visit(0);
  return { count, unique: unique.size, first };
}

export function fingerprint(molecule:Molecule):Fingerprint {
  const codes = molecule.atoms.map(atom => 16 * atom.element.number + (atom.aromatic ? 8 : 0) + atom.neighbors.length);
  const bits = new Set<number>(), used = new Set<number>();
  let paths = 0;
  const visit = (atom:number,length:number,hash:number):void => {
    paths++; bits.add(hash % 1024);
    if (length === 5) return;
    for (const neighbor of molecule.atoms[atom].neighbors) if (!used.has(neighbor.atom)) {
      let next = (hash * 31 + neighbor.bond.type!) % 1000003;
      next = (next * 31 + codes[neighbor.atom]) % 1000003;
      used.add(neighbor.atom); visit(neighbor.atom, length + 1, next); used.delete(neighbor.atom);
    }
  };
  for (let atom = 0; atom < molecule.atoms.length; atom++) { used.add(atom); visit(atom, 0, codes[atom]); used.delete(atom); }
  return { bits, paths };
}

export function similarity(first:Fingerprint,second:Fingerprint):Similarity {
  let common = 0;
  for (const bit of first.bits) if (second.bits.has(bit)) common++;
  const union = first.bits.size + second.bits.size - common;
  return { p: common, q: union, common, union };
}

