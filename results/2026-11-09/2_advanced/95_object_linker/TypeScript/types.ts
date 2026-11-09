import type { Buffer } from 'node:buffer';
import type { Section, ObjectFile, SymbolEntry, Relocation } from './object_parser.ts';
import type { Segment, OutputSection } from './layout.ts';

export interface ComdatGroup {signature: string; sections: Section[]}
export interface ArchiveMember {object: ObjectFile; exports: string[]; loaded: boolean}
export interface Archive {name: string; members: ArchiveMember[]}

export type GlobalKind = 'weakundef'|'script'|'global'|'common'|'weak'|'undefined';
export interface GlobalSymbol {
  kind: GlobalKind;
  name: string;
  entries: SymbolEntry[];
  strong: SymbolEntry[];
  weak: SymbolEntry[];
  common: SymbolEntry[];
  references: SymbolEntry[];
  referrers: string[];
  definers: string[];
  definition: SymbolEntry | null;
  definer: string;
  size: number;
  alignment: number;
  live: boolean;
  address: number;
  value: number | null;
  commonShapes: Set<string>;
  unresolved: string[];
}

export interface Merged {
  kind: 'merged';
  size: number;
  alignment: number;
  address: number;
  data: Buffer;
  sectionCount: number;
  strings: number;
  unique: number;
  saved: number;
}
export interface Veneer {
  kind: 'veneer';
  name: string;
  size: number;
  alignment: number;
  address: number;
  data: Buffer;
}
export type Component = Section | GlobalSymbol | Merged | Veneer;

export interface Script {
  entry: string;
  gc: boolean;
  segments: Segment[];
  loads: {source: string; destination: string}[];
  keeps: Set<string>;
  sorts: Set<string>;
  wraps: Set<string>;
  defines: {name: string; expression: string}[];
  scriptNames: Set<string>;
  checksum: {segment: string; symbol: string} | null;
  inputs: {kind: string; names: string[]}[];
  outputs: OutputSection[];
  segmentNames: Map<string, Segment>;
  outputNames: Map<string, OutputSection>;
}
export interface Extraction {object: string; reason: string; referrer: string}
export interface ComdatStatus {keeper: string; discarders: string[]}
export interface RelocationRecord {
  relocation: Relocation;
  position: number;
  symbol: number | null;
  value: number | null;
  field: number | null;
  width: number;
  status: 'undefined'|'ok'|'veneer'|'overflow';
  unpaired: boolean;
}
export interface RelocationCount {
  total: number; ok: number; veneer: number; overflow: number; undefined: number;
}
export interface State {
  script: Script;
  objects: ObjectFile[];
  entries: Map<string, SymbolEntry[]>;
  comdats: Map<string, ComdatStatus>;
  extractions: Extraction[];
  archives: Map<string, Archive>;
  names: string[];
  globals: Map<string, GlobalSymbol>;
  commons: GlobalSymbol[];
  entryUndefined: boolean;
  relocations: RelocationRecord[];
  relocationCounts: Map<string, RelocationCount>;
}
export interface AddressRange {width: number; lower: number | null; upper: number | null}
