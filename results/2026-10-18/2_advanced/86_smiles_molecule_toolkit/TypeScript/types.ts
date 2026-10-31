import type {Molecule} from './molecule.ts';

export interface Element {
  symbol:string;number:number;mass:number;valences:number[];base:number;maximum:number;
}
export interface AtomChoice {symbol:string;aromatic:boolean}
export interface Matcher {kind:string;choices?:AtomChoice[]}
export interface Atom {
  element:Element;
  aromatic:boolean;
  mass:number;
  charge:number;
  hydrogens:number;
  bracket:boolean;
  column:number;
  matcher?:Matcher;
  index:number;
  neighbors:Neighbor[];
  ring:boolean;
}
export interface AtomSpec {
  element?:Element;aromatic?:boolean;mass?:number;charge?:number;
  hydrogens?:number;bracket?:boolean;column?:number;matcher?:Matcher;
}
export interface Bond {
  a:number;b:number;rawType:number|null;type:number|null;
  multiplicity:number;ring:boolean;index:number;
}
export interface Neighbor {atom:number;bond:Bond}
export interface AtomRead {atom:AtomSpec;next:number}
export interface RingCandidate {sequence:number[];mask:bigint;order:number}
export interface MolecularProperties {
  formula:string;weight:number;weightText:string;heavy:number;rings:number;
  rotatable:number;donors:number;acceptors:number;lipinski:string;charge:number;
}
export interface RingSystem {rings:number[];kind:string;atoms:number}
export interface Fingerprint {bits:Set<number>;paths:number}
export interface MoleculeRecord {text:string;line:number}
export interface MoleculeCollection {
  records:MoleculeRecord[];molecules:Molecule[];byName:Map<string,Molecule>;errors:string[];
}
export interface Ratio {p:number;q:number}
export interface Similarity extends Ratio {common:number;union:number}
export interface Embeddings {count:number;unique:number;first:number[]|null}
export interface Query {
  type:string;
  id:string;
  args:string[];
  pattern?:Molecule;
  threshold?:Ratio|null;
  count?:number;
  molecules?:Molecule[];
}
export interface QueryCollection {
  records:MoleculeRecord[];queries:Query[];errors:string[];
}
