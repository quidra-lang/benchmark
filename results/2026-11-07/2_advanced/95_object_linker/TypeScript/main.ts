import {mkdirSync, writeFileSync} from 'node:fs';
import {Buffer} from 'node:buffer';
import * as objects from './object_parser.ts';
import * as archives from './archive.ts';
import * as resolver from './resolver.ts';
import * as layout from './layout.ts';
import * as relocator from './relocator.ts';
import type {Section, ObjectFile, SymbolEntry, Relocation} from './object_parser.ts';
import type {Segment, OutputSection} from './layout.ts';
import type {
 Script, State, GlobalSymbol, Component, Merged, Veneer, Extraction,
 RelocationRecord, RelocationCount, Archive, ComdatStatus
} from './types.ts';

function compareText(first: string, second: string): number {
  return first < second ? -1 : first > second ? 1 : 0;
}

function hex(value: number, width = 8): string {
  return value.toString(16).padStart(width, '0');
}

function readScript(): Script {
  const script: Script = {entry: '', gc: false, segments: [], loads: [], keeps: new Set<string>(), sorts: new Set<string>(),
    wraps: new Set<string>(), defines: [], scriptNames: new Set<string>(), checksum: null, inputs: [],
    outputs: [], segmentNames: new Map<string, Segment>(), outputNames: new Map<string, OutputSection>()};
  for (const line of objects.readLines('input/link.txt')) {
    const words = line.split(' ');
    switch (words[0]) {
      case 'entry': script.entry = words[1]; break;
      case 'gc': script.gc = words[1] === 'on'; break;
      case 'segment':
        script.segments.push(new layout.Segment(words[1], Number(words[2]), Number(words[3]), Number(words[4]), words.slice(5)));
        break;
      case 'load': script.loads.push({source: words[1], destination: words[2]}); break;
      case 'keep': script.keeps.add(words[1]); break;
      case 'sort': script.sorts.add(words[1]); break;
      case 'wrap': script.wraps.add(words[1]); break;
      case 'define':
        script.defines.push({name: words[1], expression: line.slice(line.indexOf(' = ') + 3)});
        script.scriptNames.add(words[1]);
        break;
      case 'checksum': script.checksum = {segment: words[1], symbol: words[2]}; break;
      default: script.inputs.push({kind: words[0], names: words.slice(1)});
    }
  }
  script.outputs = script.segments.flatMap(segment => segment.outputs);
  script.segmentNames = new Map(script.segments.map(segment => [segment.name, segment]));
  script.outputNames = new Map(script.outputs.map(output => [output.name, output]));
  return script;
}

function loadInputs(script: Script): State {
  const state: State = {script, objects: [], entries: new Map<string, SymbolEntry[]>(),
    comdats: new Map<string, ComdatStatus>(), extractions: [], archives: new Map<string,Archive>(),
    names: [], globals: new Map<string,GlobalSymbol>(), commons: [], entryUndefined: false,
    relocations: [], relocationCounts: new Map<string,RelocationCount>()};
  function load(object: ObjectFile): void {
    object.rank = state.objects.length;
    for (const group of object.comdats) {
      const keeper = state.comdats.get(group.signature);
      if (keeper === undefined) state.comdats.set(group.signature, {keeper: object.name, discarders: []});
      else {
        for (const section of group.sections) section.discarded = 'comdat';
        keeper.discarders.push(object.name);
      }
    }
    for (const symbol of object.symbols) {
      if (symbol.binding !== 'local' && symbol.kind === 'defined' && symbol.section!.discarded === 'comdat') {
        symbol.kind = 'undef';
        symbol.section = null;
        symbol.offset = 0;
      }
      if (symbol.kind === 'undef') {
        if (script.wraps.has(symbol.name)) symbol.name = '__wrap_' + symbol.name;
        else if (symbol.name.startsWith('__real_') && script.wraps.has(symbol.name.slice(7))) symbol.name = symbol.name.slice(7);
      }
      if (symbol.binding !== 'local') {
        if (!state.entries.has(symbol.name)) state.entries.set(symbol.name, []);
        state.entries.get(symbol.name)!.push(symbol);
      }
    }
    state.objects.push(object);
  }
  function isUndefined(name: string): boolean {
    if (script.scriptNames.has(name)) return false;
    const entries = state.entries.get(name) ?? [];
    if (entries.some(entry => entry.kind === 'defined' || entry.kind === 'common')) return false;
    return name === script.entry || entries.some(entry => entry.kind === 'undef' && entry.binding === 'global');
  }
  function scan(name: string): number {
    if (!state.archives.has(name)) state.archives.set(name, archives.readArchive(name));
    return archives.scan(state.archives.get(name)!,  isUndefined, (object, reason) => {
      const reference = (state.entries.get(reason) ?? []).find(entry => entry.kind === 'undef' && entry.binding === 'global');
      state.extractions.push({object: object.name, reason, referrer: reference === undefined ? '*entry*' : reference.object.name});
      load(object);
    });
  }
  for (const input of script.inputs) {
    if (input.kind === 'object') load(objects.readObject(input.names[0]));
    else if (input.kind === 'library') scan(input.names[0]);
    else {
      let extracted;
      do {
        extracted = 0;
        for (const name of input.names) extracted += scan(name);
      } while (extracted !== 0);
    }
  }
  state.names = [...new Set([...state.entries.keys(), ...script.scriptNames])].sort(compareText);
  state.globals = new Map(state.names.map(name => [name, resolver.resolve(name, state.entries.get(name) ?? [], script.scriptNames.has(name))]));
  return state;
}

function assignSections(state: State): void {
  for (const object of state.objects) {
    for (const section of object.sections) {
      if (section.discarded === 'comdat') continue;
      section.output = layout.outputFor(section, state.script.outputs);
      if (section.output === null) section.discarded = 'orphan';
      else section.output.sections.push(section);
    }
  }
}

function relocationTarget(symbol: SymbolEntry, globals: Map<string,GlobalSymbol>): Section | GlobalSymbol | null {
  if (symbol.binding === 'local') return symbol.section;
  const global = globals.get(symbol.name)!;
  if (global.kind === 'global' || global.kind === 'weak') return global.definition!.section;
  return global.kind === 'common' ? global : null;
}

function collectGarbage(state: State): void {
  const candidates = state.script.outputs.flatMap(output => output.sections);
  const commons = [...state.globals.values()].filter(global => global.kind === 'common');
  if (!state.script.gc) {
    for (const unit of [...candidates, ...commons]) unit.live = true;
  } else {
    const queue: (Section | GlobalSymbol)[] = [];
    function visit(unit: Section | GlobalSymbol | null): void {
      if (unit === null || unit.live) return;
      if (unit.kind === 'section' && (unit.output === null || unit.discarded !== null)) return;
      unit.live = true;
      queue.push(unit);
    }
    for (const section of candidates) if (state.script.keeps.has(section.output!.name)) visit(section);
    const entry = state.globals.get(state.script.entry);
    if (entry !== undefined) {
      if (entry.kind === 'global' || entry.kind === 'weak') visit(entry.definition!.section);
      else if (entry.kind === 'common') visit(entry);
    }
    for (let index = 0; index < queue.length; index++) {
      const unit = queue[index];
      if (unit.kind !== 'section') continue;
      for (const relocation of unit.relocations) visit(relocationTarget(relocation.symbol, state.globals));
    }
  }
  for (const section of candidates) if (!section.live) section.discarded = 'gc';
  state.commons = commons;
  const entry = state.globals.get(state.script.entry);
  state.entryUndefined = entry === undefined || entry.kind === 'undefined' || entry.kind === 'weakundef';
  for (const global of state.globals.values()) global.unresolved = [];
  for (const object of state.objects) {
    const referenced = new Set<string>();
    for (const section of object.sections) {
      if (!section.live) continue;
      for (const relocation of section.relocations) {
        if (relocation.symbol.binding !== 'local' && state.globals.get(relocation.symbol.name)!.kind === 'undefined') {
          referenced.add(relocation.symbol.name);
        }
      }
    }
    for (const name of referenced) state.globals.get(name)!.unresolved.push(object.name);
  }
}

function mergeStrings(sections: Section[]): Merged {
  const block: Merged = {kind: 'merged', size: 0, alignment: 1, address: 0, data: Buffer.alloc(0),
    sectionCount: sections.length, strings: 0, unique: 0, saved: 0};
  const contents: Buffer[] = [];
  const positions = new Map<string,number>();
  let originalSize = 0;
  for (const section of sections) {
    originalSize += section.size;
    section.merged = block;
    section.mergedPositions = new Map<number,number>();
    let start = 0;
    for (let end = 0; end < section.data.length; end++) {
      if (section.data[end] !== 0) continue;
      const string = section.data.subarray(start, end + 1);
      const key = string.toString('hex');
      if (!positions.has(key)) {
        positions.set(key, block.size);
        contents.push(string);
        block.size += string.length;
        block.unique++;
      }
      section.mergedPositions.set(start, positions.get(key)!);
      block.strings++;
      start = end + 1;
    }
  }
  block.data = Buffer.concat(contents, block.size);
  block.saved = originalSize - block.size;
  return block;
}

function buildComponents(state: State): void {
  const commons = state.commons.filter(common => common.live).sort((first, second) =>
    second.alignment - first.alignment || compareText(first.name, second.name));
  for (const output of state.script.outputs) {
    const sections = output.sections.filter(section => section.live);
    if (state.script.sorts.has(output.name)) {
      const priority = (section: Section): number => section.name === output.name ? 65536 : Number(section.name.slice(output.name.length + 1));
      sections.sort((first, second) => priority(first) - priority(second));
    }
    const strings = sections.filter(section => section.string);
    const merged = strings.length === 0 ? null : mergeStrings(strings);
    output.components = [];
    let inserted = false;
    for (const section of sections) {
      if (!section.string) output.components.push(section);
      else if (!inserted) {
        output.components.push(merged!);
        inserted = true;
      }
    }
    if (output.name === '.bss') for (const common of commons) output.components.push(common);
    output.veneers = new Map<string,Veneer>();
    for (const name of [...output.veneerNames].sort(compareText)) {
      const veneer: Veneer = {kind: 'veneer', name, size: 8, alignment: 4, address: 0, data: Buffer.alloc(0)};
      output.components.push(veneer);
      output.veneers.set(name, veneer);
    }
  }
}

function sectionAddress(section: Section, offset: number): number {
  return section.string ? section.merged!.address + section.mergedPositions.get(offset)! : section.address + offset;
}

function definitionAddress(global: GlobalSymbol): number {
  return sectionAddress(global.definition!.section!, global.definition!.offset);
}

function farCall(relocation: Relocation, globals: Map<string,GlobalSymbol>): boolean {
  if (relocation.type !== 'CALL24' || relocation.symbol.binding === 'local') return false;
  const global = globals.get(relocation.symbol.name)!;
  if (global.kind !== 'global' && global.kind !== 'weak') return false;
  const value = definitionAddress(global) + relocation.addend - (relocation.section.address + relocation.offset);
  return !relocator.inRange('CALL24', value);
}

function placeWithVeneers(state: State): void {
  while (true) {
    buildComponents(state);
    for (const segment of state.script.segments) layout.placeSegment(segment);
    let added = false;
    for (const object of state.objects) {
      for (const section of object.sections) {
        if (!section.live) continue;
        for (const relocation of section.relocations) {
          if (farCall(relocation, state.globals) && !section.output!.veneerNames.has(relocation.symbol.name)) {
            section.output!.veneerNames.add(relocation.symbol.name);
            added = true;
          }
        }
      }
    }
    if (!added) break;
  }
  for (const output of state.script.outputs) {
    for (const veneer of output.veneers.values()) {
      veneer.data = Buffer.concat([Buffer.from([4, 240, 31, 229]),
        relocator.littleEndian(definitionAddress(state.globals.get(veneer.name)!), 4)]);
    }
  }
}

function loadAddresses(script: Script): void {
  for (const segment of script.segments) {
    segment.paddr = segment.base;
    segment.storage = segment.base + segment.memsz;
  }
  for (const load of script.loads) {
    const source = script.segmentNames.get(load.source)!;
    const destination = script.segmentNames.get(load.destination)!;
    source.paddr = layout.align(destination.storage, 4);
    destination.storage = source.paddr + source.filesz;
  }
  for (const segment of script.segments) segment.used = segment.storage - segment.base;
}

function evaluateExpression(source: string, script: Script, globals: Map<string,GlobalSymbol>): number {
  const tokens = source.match(/0x[0-9a-f]+|[0-9]+|[A-Za-z_.][A-Za-z0-9_.]*|[(),+\-]/g)!;
  let index = 0;
  function term(): number {
    const token = tokens[index++];
    if (token === '(') {
      const value = expression();
      index++;
      return value;
    }
    if (token[0] >= '0' && token[0] <= '9') return Number(token);
    if (tokens[index] !== '(') return globals.get(token)!.value!;
    index++;
    if (token === 'align') {
      const first = expression();
      index++;
      const second = expression();
      index++;
      return layout.align(first, second);
    }
    const output = script.outputNames.get(tokens[index++])!;
    index++;
    if (token === 'start') return output.address;
    if (token === 'end') return output.address + output.size;
    if (token === 'size') return output.size;
    return output.segment.paddr + output.address - output.segment.base;
  }
  function expression(): number {
    let value = term();
    while (tokens[index] === '+' || tokens[index] === '-') {
      const operator = tokens[index++];
      const right = term();
      value = operator === '+' ? value + right : value - right;
    }
    return value;
  }
  return expression();
}

function symbolValue(symbol: SymbolEntry, globals: Map<string,GlobalSymbol>): number | null {
  if (symbol.binding === 'local') return sectionAddress(symbol.section!, symbol.offset);
  const global = globals.get(symbol.name)!;
  if (global.kind === 'global' || global.kind === 'weak') return definitionAddress(global);
  if (global.kind === 'common') return global.address;
  if (global.kind === 'script') return global.value;
  return global.kind === 'weakundef' ? 0 : null;
}

function applyRelocations(state: State): void {
  const records: RelocationRecord[] = [];
  const counts = new Map<string,RelocationCount>(relocator.types.map(type =>
    [type, {total: 0, ok: 0, veneer: 0, overflow: 0, undefined: 0}]));
  const gp = state.globals.get('_gp')?.value ?? 0;
  for (const segment of state.script.segments) {
    for (const output of segment.outputs) {
      for (const component of output.components) {
        if (component.kind !== 'section') continue;
        for (let index = 0; index < component.relocations.length; index++) {
          const relocation = component.relocations[index];
          const record: RelocationRecord = {relocation, position: component.address + relocation.offset,
            symbol: symbolValue(relocation.symbol, state.globals), value: null, field: null,
            width: relocator.specifications[relocation.type].width, status: 'undefined',
            unpaired: relocator.isUnpaired(component.relocations, index)};
          if (record.symbol !== null) {
            record.status = 'ok';
            if (farCall(relocation, state.globals)) {
              record.symbol = output.veneers.get(relocation.symbol.name)!.address;
              record.status = 'veneer';
            }
            const calculated = relocator.calculate(relocation.type, record.symbol!, relocation.addend, record.position, gp);
            record.value = calculated.value;
            record.field = calculated.field;
            if (calculated.overflow) record.status = 'overflow';
            relocator.littleEndian(record.field!, record.width).copy(component.data, relocation.offset);
          }
          records.push(record);
          const count = counts.get(relocation.type)!;
          count.total++;
          count[record.status]++;
        }
      }
    }
  }
  state.relocations = records;
  state.relocationCounts = counts;
}

function makeImages(state: State): void {
  for (const segment of state.script.segments) {
    segment.image = Buffer.alloc(segment.filesz, segment.fill);
    for (const output of segment.outputs) {
      if (output.nobits) continue;
      for (const component of output.components) if ('data' in component) component.data.copy(segment.image!, component.address - segment.base);
    }
  }
  if (state.script.checksum === null) return;
  const checksum = state.script.checksum;
  const segment = state.script.segmentNames.get(checksum.segment)!;
  const offset = definitionAddress(state.globals.get(checksum.symbol)!) - segment.base;
  segment.image!.fill(0, offset, offset + 4);
  let total = 0;
  for (let start = 0; start < segment.image!.length; start += 4) {
    let chunk = 0;
    let factor = 1;
    for (let index = 0; index < 4; index++) {
      if (start + index < segment.image!.length) chunk += segment.image![start + index] * factor;
      factor *= 256;
    }
    total += chunk;
  }
  relocator.littleEndian(relocator.mod(-total, 2 ** 32), 4).copy(segment.image!, offset);
}

function diagnostics(state: State): string[] {
  const lines: string[] = [];
  const orphanCounts = new Map<string,number>();
  for (const object of state.objects) {
    for (const section of object.sections) {
      if (section.discarded === 'orphan') orphanCounts.set(section.name, (orphanCounts.get(section.name) ?? 0) + 1);
    }
  }
  for (const name of [...orphanCounts.keys()].sort(compareText)) {
    lines.push(`warning: orphan section ${name} discarded from ${orphanCounts.get(name)} object(s)`);
  }
  for (const global of state.globals.values()) {
    if (global.definers.length >= 2) lines.push(`error: multiple definition of ${global.name}: ${global.definers.join(' ')}`);
    if (global.common.length > 0 && (global.kind === 'global' || global.kind === 'script')) {
      lines.push(`warning: common symbol ${global.name} overridden by ${global.definer}`);
    }
    if (global.kind === 'common' && global.commonShapes.size >= 2) {
      lines.push(`warning: common symbol ${global.name} merged to size ${global.size} align ${global.alignment}`);
    }
  }
  if (state.entryUndefined) lines.push(`error: entry symbol ${state.script.entry} is undefined`);
  for (const global of state.globals.values()) {
    if (global.kind === 'undefined' && global.unresolved.length > 0) {
      lines.push(`error: undefined symbol ${global.name} referenced by ${global.unresolved.join(' ')}`);
    }
  }
  for (const segment of state.script.segments) {
    if (segment.used > segment.length) lines.push(`error: segment ${segment.name} overflows its length by ${segment.used - segment.length} bytes`);
  }
  for (let first = 0; first < state.script.segments.length; first++) {
    const a = state.script.segments[first];
    for (let second = first + 1; second < state.script.segments.length; second++) {
      const b = state.script.segments[second];
      if (a.memsz > 0 && b.memsz > 0 && a.base < b.base + b.memsz && b.base < a.base + a.memsz) {
        lines.push(`error: segments ${a.name} and ${b.name} overlap`);
      }
    }
  }
  for (const record of state.relocations) {
    const relocation = record.relocation;
    const location = `${relocation.section.object.name} ${relocation.section.name}+${relocation.offset}`;
    if (record.unpaired) lines.push(`error: unpaired HI16 at ${location} against ${relocation.symbol.name}`);
    if (record.status === 'overflow') {
      lines.push(`error: relocation overflow at ${location}: ${relocation.type} value ${record.value} against ${relocation.symbol.name}`);
    }
  }
  const errors = lines.filter(line => line.startsWith('error')).length;
  const warnings = lines.filter(line => line.startsWith('warning')).length;
  lines.push(`errors ${errors} warnings ${warnings}`);
  return lines;
}

function entryAddress(state: State): number {
  const entry = state.globals.get(state.script.entry);
  if (entry === undefined) return 0;
  if (entry.kind === 'global' || entry.kind === 'weak') return definitionAddress(entry);
  return entry.kind === 'common' ? entry.address : 0;
}

function imageDump(state: State, entry: number): string[] {
  const lines: string[] = [`entry ${hex(entry)} ${state.script.entry}`];
  for (const segment of state.script.segments) {
    lines.push(`segment ${segment.name} vaddr ${hex(segment.base)} paddr ${hex(segment.paddr)} filesz ${segment.filesz} memsz ${segment.memsz}`);
    for (let start = 0; start < segment.image!.length; start += 16) {
      const bytes = Array.from(segment.image!.subarray(start, start + 16), byte => hex(byte, 2));
      lines.push(`${hex(segment.base + start)} ${bytes.join(' ')}`);
    }
  }
  return lines;
}

function intelRecord(type: number, address: number, data: number[] | Uint8Array): string {
  const bytes = [data.length, Math.floor(address / 256), address % 256, type, ...data];
  let total = 0;
  for (const byte of bytes) total += byte;
  bytes.push(relocator.mod(-total, 256));
  return ':' + bytes.map(byte => hex(byte, 2).toUpperCase()).join('');
}

function intelHex(state: State, entry: number): string[] {
  const lines: string[] = [];
  const segments = state.script.segments.filter(segment => segment.filesz > 0).sort((first, second) => first.paddr - second.paddr);
  let upper = 0;
  for (const segment of segments) {
    let offset = 0;
    while (offset < segment.filesz) {
      const address = segment.paddr + offset;
      const count = Math.min(16, segment.filesz - offset, 65536 - address % 65536);
      const nextUpper = Math.floor(address / 65536);
      if (nextUpper !== upper) {
        upper = nextUpper;
        lines.push(intelRecord(4, 0, [Math.floor(upper / 256), upper % 256]));
      }
      lines.push(intelRecord(0, address % 65536, segment.image!.subarray(offset, offset + count)));
      offset += count;
    }
  }
  lines.push(intelRecord(5, 0, Array.from(relocator.littleEndian(entry, 4)).reverse()));
  lines.push(intelRecord(1, 0, []));
  return lines;
}

function mapLines(state: State): string[] {
  const lines: string[] = [];
  for (const extraction of state.extractions) lines.push(`member ${extraction.object} ${extraction.referrer} ${extraction.reason}`);
  for (const [signature, group] of state.comdats) lines.push(`comdat ${signature} ${group.keeper} ${group.discarders.join(',') || '-'}`);
  for (const segment of state.script.segments) {
    lines.push(`segment ${segment.name} vaddr ${hex(segment.base)} paddr ${hex(segment.paddr)} filesz ${segment.filesz} ` +
      `memsz ${segment.memsz} used ${segment.used} length ${segment.length} ${Math.floor(100 * segment.used / segment.length)}%`);
    for (const output of segment.outputs) {
      lines.push(`section ${output.name} ${hex(output.address)} ${output.size} ${output.alignment}`);
      for (const component of output.components) {
        if (component.kind === 'section') {
          lines.push(`input ${hex(component.address)} ${component.size} ${component.alignment} ${component.object.name} ${component.name}`);
        } else if (component.kind === 'merged') {
          lines.push(`merged ${hex(component.address)} ${component.size} sections ${component.sectionCount} ` +
            `strings ${component.strings} unique ${component.unique} saved ${component.saved}`);
        } else if (component.kind === 'common') {
          lines.push(`common ${hex(component.address)} ${component.size} ${component.alignment} ${component.definer} ${component.name}`);
        } else lines.push(`veneer ${hex(component.address)} 8 ${component.name}`);
      }
    }
  }
  for (const object of state.objects) {
    for (const section of object.sections) {
      if (section.discarded !== null) lines.push(`discard ${object.name} ${section.name} ${section.size} ${section.discarded}`);
    }
  }
  for (const common of state.commons) if (!common.live) lines.push(`discard ${common.definer} COMMON(${common.name}) ${common.size} gc`);
  const symbols: {address:number;name:string;kind:string;definer:string}[] = [];
  for (const global of state.globals.values()) {
    if ((global.kind === 'global' || global.kind === 'weak') && global.definition!.section!.live) {
      symbols.push({address: definitionAddress(global), name: global.name, kind: global.kind, definer: global.definer});
    } else if (global.kind === 'common' && global.live) {
      symbols.push({address: global.address, name: global.name, kind: 'common', definer: global.definer});
    } else if (global.kind === 'script') symbols.push({address: global.value!, name: global.name, kind: 'script', definer: '*script*'});
  }
  for (const output of state.script.outputs) {
    for (const veneer of output.veneers.values()) symbols.push({address: veneer.address, name: '__veneer_' + veneer.name, kind: 'veneer', definer: '*linker*'});
  }
  symbols.sort((first, second) => first.address - second.address || compareText(first.name, second.name));
  for (const symbol of symbols) lines.push(`symbol ${hex(symbol.address)} ${symbol.name} ${symbol.kind} ${symbol.definer}`);
  return lines;
}

function xrefLines(state: State): string[] {
  const lines: string[] = [];
  for (const global of state.globals.values()) {
    let status = '-';
    if (global.kind === 'global' || global.kind === 'weak') status = global.definition!.section!.live ? 'kept' : 'discarded';
    else if (global.kind === 'common') status = global.live ? 'kept' : 'discarded';
    else if (global.kind === 'script') status = 'kept';
    lines.push(`${global.name} ${global.kind} ${status} ${global.definer} ${global.referrers.join(',') || '-'}`);
  }
  return lines;
}

function relocationLines(state: State): string[] {
  const lines: string[] = [];
  for (const record of state.relocations) {
    const relocation = record.relocation;
    const values = record.status === 'undefined' ? '- - -' : `${hex(record.symbol!)} ${record.value} ${hex(record.field!, record.width * 2)}`;
    lines.push(`${hex(record.position)} ${relocation.section.object.name} ${relocation.section.name}+${relocation.offset} ` +
      `${relocation.type} ${relocation.symbol.name} ${relocation.addend} ${values} ${record.status}`);
  }
  for (const type of relocator.types) {
    const count = state.relocationCounts.get(type)!;
    lines.push(`summary ${type} total ${count.total} ok ${count.ok} veneer ${count.veneer} overflow ${count.overflow} undefined ${count.undefined}`);
  }
  return lines;
}

function main(): void {
  const script = readScript();
  const state = loadInputs(script);
  assignSections(state);
  collectGarbage(state);
  placeWithVeneers(state);
  loadAddresses(script);
  for (const definition of script.defines) {
    state.globals.get(definition.name)!.value = evaluateExpression(definition.expression, script, state.globals);
  }
  applyRelocations(state);
  makeImages(state);
  const entry = entryAddress(state);
  const files = {'image.hex': imageDump(state, entry), 'flash.ihex': intelHex(state, entry),
    'link.map': mapLines(state), 'xref.txt': xrefLines(state), 'relocations.txt': relocationLines(state),
    'diagnostics.txt': diagnostics(state)};
  mkdirSync('output', {recursive: true});
  for (const [name, lines] of Object.entries(files)) {
    writeFileSync('output/' + name, lines.join('\n') + (lines.length === 0 ? '' : '\n'), 'ascii');
  }
}

main();
