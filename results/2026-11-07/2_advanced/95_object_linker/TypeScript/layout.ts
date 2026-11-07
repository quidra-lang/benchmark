import {belongs, isNobits} from './object_parser.ts';
import type {Section} from './object_parser.ts';
import type {Component, Veneer} from './types.ts';
import type {Buffer} from 'node:buffer';

export function align(value: number, alignment: number): number {
  return Math.ceil(value / alignment) * alignment;
}

export class OutputSection {
  segment: Segment;
  name: string;
  nobits: boolean;
  sections: Section[];
  components: Component[];
  veneerNames: Set<string>;
  veneers: Map<string,Veneer>;
  address: number;
  size: number;
  alignment: number;
  constructor(segment: Segment, name: string) {
    this.segment = segment;
    this.name = name;
    this.nobits = isNobits(name);
    this.sections = [];
    this.components = [];
    this.veneerNames = new Set<string>();
    this.veneers = new Map<string,Veneer>();
    this.address = 0;
    this.size = 0;
    this.alignment = 1;
  }
}

export class Segment {
  name: string;
  base: number;
  length: number;
  fill: number;
  outputs: OutputSection[];
  memsz: number;
  filesz: number;
  paddr: number;
  used: number;
  image: Buffer | null;
  storage: number;
  constructor(name: string, base: number, length: number, fill: number, outputNames: string[]) {
    this.name = name; this.base = base; this.length = length; this.fill = fill;
    this.outputs = outputNames.map(output => new OutputSection(this, output));
    this.memsz = 0;
    this.filesz = 0;
    this.paddr = base;
    this.used = 0;
    this.image = null;
    this.storage = base;
  }
}

export function outputFor(section: Section, outputs: OutputSection[]): OutputSection | null {
  return outputs.find(output => belongs(section.name, output.name)) ?? null;
}

export function placeSegment(segment: Segment): void {
  let cursor = segment.base;
  segment.filesz = 0;
  for (const output of segment.outputs) {
    output.alignment = 1;
    for (const component of output.components) output.alignment = Math.max(output.alignment, component.alignment);
    cursor = align(cursor, output.alignment);
    output.address = cursor;
    for (const component of output.components) {
      cursor = align(cursor, component.alignment);
      component.address = cursor;
      cursor += component.size;
    }
    output.size = cursor - output.address;
    if (!output.nobits) segment.filesz = cursor - segment.base;
  }
  segment.memsz = cursor - segment.base;
}

