import type { SymbolEntry } from './object_parser.ts';
import type { GlobalSymbol } from './types.ts';

export function resolve(name: string, entries: SymbolEntry[], script: boolean): GlobalSymbol {
  const strong = entries.filter(entry => entry.kind === 'defined' && entry.binding === 'global');
  const weak = entries.filter(entry => entry.kind === 'defined' && entry.binding === 'weak');
  const common = entries.filter(entry => entry.kind === 'common');
  const references = entries.filter(entry => entry.kind === 'undef');
  const referrers = [...new Set(references.map(entry => entry.object.name))];
  const definers = strong.map(entry => entry.object.name);
  if (script) definers.unshift('*script*');
  const result: GlobalSymbol = {name, entries, strong, weak, common, references, referrers, definers,
    kind: 'weakundef', definition: null, definer: '-', size: 0, alignment: 1, live: false, address: 0, value: null, commonShapes: new Set<string>(), unresolved: []};
  if (script) {
    result.kind = 'script';
    result.definer = '*script*';
  } else if (strong.length > 0) {
    result.kind = 'global';
    result.definition = strong[0];
    result.definer = strong[0].object.name;
  } else if (common.length > 0) {
    result.kind = 'common';
    for (const entry of common) {
      result.size = Math.max(result.size, entry.size);
      result.alignment = Math.max(result.alignment, entry.alignment);
    }
    result.definer = common.find(entry => entry.size === result.size)!.object.name;
  } else if (weak.length > 0) {
    result.kind = 'weak';
    result.definition = weak[0];
    result.definer = weak[0].object.name;
  } else if (references.some(entry => entry.binding === 'global')) result.kind = 'undefined';
  result.commonShapes = new Set(common.map(entry => `${entry.size},${entry.alignment}`));
  return result;
}

