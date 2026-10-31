import type { CoreStats } from './types.ts';

import { TYPES } from './protocol.ts';
export const SERVICES = ['l1', 'upgrade', 'through', 'cache', 'l2', 'memory'];
export const coreString = (cores: Iterable<number>): string => Array.from(cores).sort((a, b) => a - b).join('') || '-';
export const ranges = (labels: string[], counts: number[]): string => labels.map((label, i) => `${label}:${counts[i]}`).join(' ');

export function decimal(numerator: number, denominator: number): string {
  const scaled = Math.floor((2 * numerator * 100 + denominator) / (2 * denominator));
  return Math.floor(scaled / 100) + '.' + String(scaled % 100).padStart(2, '0');
}

export function fraction(numerator: number, denominator: number): string {
  let a = numerator, b = denominator;
  while (b !== 0) { const remainder = a % b; a = b; b = remainder; }
  return `${numerator / a}/${denominator / a}`;
}

export function create(): CoreStats {
  return { accesses: 0, reads: 0, writes: 0, hits: 0, misses: 0, fences: 0,
    compulsory: 0, capacity: 0, conflict: 0, coherence: 0, trueSharing: 0, falseSharing: 0,
    service: Object.fromEntries(SERVICES.map(service => [service, 0])), bus: Object.fromEntries(TYPES.map(type => [type, 0])),
    invalidationsSent: 0, invalidationsReceived: 0, supplied: 0, backInvalidations: 0,
    latency: 0, readLatency: 0, writeLatency: 0, fenceStall: 0, finish: 0 };
}

export function total(cores: CoreStats[]): CoreStats {
  const result = create();
  for (const core of cores) for (const key of Object.keys(result)) {
    if (typeof result[key] === 'number') result[key] = key === 'finish' ? Math.max(result[key], core[key]) : result[key] + core[key];
    else for (const field of Object.keys(result[key])) result[key][field] += core[key][field];
  }
  return result;
}

export function lines(label: string, stats: CoreStats): string[] {
  return [
    `${label} accesses ${stats.accesses} reads ${stats.reads} writes ${stats.writes} hits ${stats.hits} misses ${stats.misses} fences ${stats.fences}`,
    `${label} misses compulsory ${stats.compulsory} capacity ${stats.capacity} conflict ${stats.conflict} coherence ${stats.coherence} true_sharing ${stats.trueSharing} false_sharing ${stats.falseSharing}`,
    `${label} service ${SERVICES.map(service => `${service} ${stats.service[service]}`).join(' ')}`,
    `${label} bus ${TYPES.map(type => `${type} ${stats.bus[type]}`).join(' ')}`,
    `${label} snoop invalidations_sent ${stats.invalidationsSent} invalidations_received ${stats.invalidationsReceived} supplied ${stats.supplied} back_invalidations ${stats.backInvalidations}`,
    `${label} time latency ${stats.latency} amat ${fraction(stats.latency, stats.accesses)} ${decimal(stats.latency, stats.accesses)} fence_stall ${stats.fenceStall} finish ${stats.finish}`,
  ];
}

