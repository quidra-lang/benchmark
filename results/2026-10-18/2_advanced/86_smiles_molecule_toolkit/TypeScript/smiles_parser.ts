import {Molecule,MoleculeError} from './molecule.ts';
import type {AtomRead,Element} from './types.ts';
export const ORGANIC = new Set<string>(['B', 'C', 'N', 'O', 'P', 'S', 'F', 'Cl', 'Br', 'I']);
export const AROMATIC = new Set<string>(['b', 'c', 'n', 'o', 'p', 's']);
const digit = (character:string|undefined):boolean => character !== undefined && character >= '0' && character <= '9';
const uppercase = (character:string|undefined):boolean => character !== undefined && character >= 'A' && character <= 'Z';
const fail = (reason:string,column:number):never => { throw new MoleculeError(reason, column); };

export function organicAtom(text:string,start:number,elements:Map<string,Element>):AtomRead|null {
  const pair = text.slice(start, start + 2), symbol = pair === 'Cl' || pair === 'Br' ? pair : text[start];
  const aromatic = AROMATIC.has(symbol);
  if (!aromatic && !ORGANIC.has(symbol)) return null;
  return { atom: { element: elements.get(aromatic ? symbol.toUpperCase() : symbol)!, aromatic, mass: 0, charge: 0,
    hydrogens: 0, bracket: false, column: start + 1 }, next: start + symbol.length };
}

export function bracketAtom(text:string,start:number,elements:Map<string,Element>):AtomRead {
  const end = text.indexOf(']', start + 1);
  if (end < 0) fail('unclosed bracket', start + 1);
  const content = text.slice(start + 1, end);
  let i = 0;
  while (digit(content[i])) i++;
  if (i >= 4 || (i > 0 && content[0] === '0')) fail('bad bracket atom', start + 1);
  const mass = i === 0 ? 0 : Number(content.slice(0, i));
  let aromatic = false, symbol:string;
  if (AROMATIC.has(content[i])) { aromatic = true; symbol = content[i++].toUpperCase(); }
  else if (uppercase(content[i])) {
    const pair = content.slice(i, i + 2);
    if (pair.length === 2 && elements.has(pair)) { symbol = pair; i += 2; }
    else if (elements.has(content[i])) symbol = content[i++];
    else fail('unknown element', start + 1);
  } else fail('bad bracket atom', start + 1);
  if (content.slice(i, i + 2) === '@@') i += 2;
  else if (content[i] === '@') i++;
  let hydrogens = 0, charge = 0;
  if (content[i] === 'H') {
    i++; hydrogens = 1;
    if (digit(content[i])) hydrogens = Number(content[i++]);
  }
  if (content[i] === '+' || content[i] === '-') {
    charge = content[i++] === '+' ? 1 : -1;
    if (content[i] >= '1' && content[i] <= '9') charge *= Number(content[i++]);
  }
  if (i !== content.length) fail('bad bracket atom', start + 1);
  return { atom: { element: elements.get(symbol!)!, aromatic, mass, charge, hydrogens, bracket: true, column: start + 1 }, next: end + 1 };
}

export function parseSmiles(text:string,elements:Map<string,Element>,
  patternReader: ((text:string,start:number,elements:Map<string,Element>)=>AtomRead|null)|null = null):Molecule {
  const molecule = new Molecule();
  const stack: {atom:number;column:number}[] = [];
  const open = new Map<number,{atom:number;symbol:number|null;column:number}>();
  const types:Record<string,number> = patternReader ? { '-': 1, '=': 2, '#': 3, ':': 4, '~': 5 } : { '-': 1, '/': 1, '\\': 1, '=': 2, '#': 3, ':': 4 };
  let current:number|null = null, pending:{type:number;column:number}|null = null, i = 0;
  while (i < text.length) {
    const character = text[i], column = i + 1;
    if (Object.hasOwn(types, character)) {
      if (current === null || pending !== null) fail('misplaced bond', column);
      pending = { type: types[character], column }; i++;
    } else if (character === '(') {
      if (current === null || pending !== null || text[i - 1] === '(') fail('misplaced branch', column);
      stack.push({ atom: current, column }); i++;
    } else if (character === ')') {
      if (stack.length === 0) fail('unmatched parenthesis', column);
      if (pending !== null) fail('dangling bond', pending.column);
      if (text[i - 1] === '(') fail('empty branch', column);
      current = stack.pop()!.atom; i++;
    } else if (digit(character) || character === '%') {
      if (current === null) fail('misplaced ring closure', column);
      let number;
      if (character === '%') {
        if (!digit(text[i + 1]) || !digit(text[i + 2])) fail('bad ring number', column);
        number = Number(text.slice(i + 1, i + 3)); i += 3;
      } else { number = Number(character); i++; }
      const symbol = pending === null ? null : pending.type;
      pending = null;
      if (!open.has(number)) open.set(number, { atom: current, symbol, column });
      else {
        const opening = open.get(number)!;
        if (opening.atom === current) fail('self bond', column);
        if (opening.symbol !== null && symbol !== null && opening.symbol !== symbol) fail('ring bond mismatch', column);
        if (molecule.bond(opening.atom, current)) fail('duplicate bond', column);
        molecule.addBond(opening.atom, current, symbol === null ? opening.symbol : symbol); open.delete(number);
      }
    } else {
      const read = patternReader ? patternReader(text, i, elements) : character === '[' ? bracketAtom(text, i, elements) : organicAtom(text, i, elements);
      if (read === null) fail('unexpected character', column);
      const next = molecule.addAtom(read.atom);
      if (current !== null) molecule.addBond(current, next, pending === null ? null : pending.type);
      current = next; pending = null; i = read.next;
    }
  }
  if (pending !== null) fail('dangling bond', pending.column);
  if (stack.length) fail('unmatched parenthesis', stack[0].column);
  if (open.size) fail('unclosed ring', Math.min(...Array.from(open.values(), value => value.column)));
  return molecule.finalize();
}

