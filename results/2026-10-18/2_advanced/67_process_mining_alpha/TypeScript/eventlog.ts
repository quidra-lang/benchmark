import { readFileSync } from 'node:fs';
import type { Fraction } from './report.ts';

export interface InputRow {
  caseId: string;
  activity: string;
  timestamp: string;
  resource: string;
  line: number;
}
export interface Event extends InputRow {
  time: number;
}
export interface Case {
  id: string;
  events: Event[];
  trace: string[];
  duration: number;
  variant: number;
}
const months = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
export function readInputs(): { rows: InputRow[]; parameters: Map<string, string> } {
  const rows = readFileSync('input/eventlog.csv', 'ascii')
    .trimEnd()
    .split('\n')
    .slice(1)
    .map((text, i) => {
      const [caseId, activity, timestamp, resource] = text.split(',');
      return { caseId, activity, timestamp, resource, line: i + 2 };
    });
  const parameters = new Map<string, string>();
  for (const line of readFileSync('input/params.txt', 'ascii').trimEnd().split('\n')) {
    const [key, value] = line.split(' ');
    parameters.set(key, value);
  }
  return { rows, parameters };
}
export function timestampMinutes(timestamp: string): number | null {
  const month = Number(timestamp.slice(5, 7));
  const day = Number(timestamp.slice(8, 10));
  const hour = Number(timestamp.slice(11, 13));
  const minute = Number(timestamp.slice(14, 16));
  if (month < 1 || month > 12 || day < 1 || day > months[month - 1] || hour > 23 || minute > 59) {
    return null;
  }
  let days = 0;
  for (let i = 0; i < month - 1; i++) days += months[i];
  return ((days + day - 1) * 24 + hour) * 60 + minute;
}
export function buildCases(events: Event[]): Case[] {
  const groups = new Map<string, Event[]>();
  for (const event of events) {
    let group = groups.get(event.caseId);
    if (!group) {
      group = [];
      groups.set(event.caseId, group);
    }
    group.push(event);
  }
  return [...groups.keys()].sort().map((id) => {
    const ordered = groups.get(id)!.sort((a, b) => a.time - b.time || a.line - b.line);
    return {
      id,
      events: ordered,
      trace: ordered.map((e) => e.activity),
      duration: ordered.at(-1)!.time - ordered[0].time,
      variant: 0,
    };
  });
}
export function median(values: number[]): Fraction {
  const sorted = values.toSorted((a, b) => a - b);
  const m = Math.floor(sorted.length / 2);
  return sorted.length % 2
    ? [BigInt(sorted[m]), 1n]
    : [BigInt(sorted[m - 1]) + BigInt(sorted[m]), 2n];
}
export const quotient = (numerator: number, denominator: number): number =>
  Number(BigInt(numerator) / BigInt(denominator));
