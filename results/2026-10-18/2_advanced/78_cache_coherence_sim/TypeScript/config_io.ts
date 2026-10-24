import { readFileSync, writeFileSync } from 'node:fs';
import type { Config } from './types.ts';
export const decimalInteger = (text: string): boolean => /^(0|[1-9][0-9]*)$/.test(text);
export const hexDigits = (text: string): boolean => /^[0-9a-f]{8}$/.test(text);
export const hex = (address: number): string => address.toString(16).padStart(8, '0');
const lines = (path: string): string[] => readFileSync(path, 'ascii').split('\n').slice(0, -1);

export function read(): {config: Config; trace: string[]} {
  const config = { scenarios: [], regions: [], watches: [] } as unknown as Config;
  for (const line of lines('input/config.txt')) {
    const [key, ...fields] = line.split(' ');
    if (key === 'CORES') config.cores = Number(fields[0]);
    else if (key === 'LINE') config.line = Number(fields[0]);
    else if (key === 'L1' || key === 'L2') {
      const geometry = { size: Number(fields[0]), ways: Number(fields[1]), sets: 0 };
      if (key === 'L1') config.l1 = geometry;
      else config.l2 = geometry;
    }
    else if (key === 'LATENCY') config.latencies = fields.map(Number);
    else if (key === 'SCENARIO') config.scenarios.push({ name: fields[0], protocol: fields[1], l1Policy: fields[2], l2Policy: fields[3], order: config.scenarios.length });
    else if (key === 'PRIMARY') config.primary = fields[0];
    else if (key === 'INTERVAL') config.interval = Number(fields[0]);
    else if (key === 'TOP') config.top = Number(fields[0]);
    else if (key === 'REGION') config.regions.push({ name: fields[0], first: Number.parseInt(fields[1], 16), last: Number.parseInt(fields[2], 16) });
    else config.watches.push(Number.parseInt(fields[0], 16) / config.line);
  }
  for (const cache of [config.l1, config.l2]) cache.sets = cache.size / (config.line * cache.ways);
  config.capacity = config.l1.sets * config.l1.ways;
  return { config, trace: lines('input/trace.txt') };
}

export function write(path: string, lines: string[]): void { writeFileSync(path, lines.length ? lines.join('\n') + '\n' : '', 'ascii'); }

