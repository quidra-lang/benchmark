import type { Control } from './variable_charts.ts';
function place(band: string[], position: number, character: string) {
  band[Math.max(0, Math.min(60, position))] = character;
}
export function variableBand(c: Control, value: number, signal: boolean): string {
  const band: string[] = Array(61).fill('.');
  const position = (v: number) => Math.floor(60 * ((v - c.lcl) / (c.ucl - c.lcl)) + 0.5);
  place(band, 0, ':');
  place(band, 60, ':');
  place(band, position(c.cl), '|');
  place(band, position(value), signal ? '*' : 'o');
  return band.join('');
}
export function cusumBand(
  plus: number,
  minus: number,
  h: number,
  upper: boolean,
  lower: boolean,
): string {
  const band: string[] = Array(61).fill('.');
  place(band, 0, ':');
  place(band, 60, ':');
  place(band, 30, '|');
  if (minus > 0) {
    place(band, 30 - Math.min(30, Math.floor(30 * (minus / h) + 0.5)), lower ? '*' : '-');
  }
  if (plus > 0) {
    place(band, 30 + Math.min(30, Math.floor(30 * (plus / h) + 0.5)), upper ? '*' : '+');
  }
  return band.join('');
}
export function averageBand(
  value: number,
  width: number,
  full: number,
  center: number,
  signal: boolean,
): string {
  const band: string[] = Array(61).fill('.');
  const e = Math.min(30, Math.floor(30 * (width / full) + 0.5));
  place(band, 30, '|');
  place(band, 30 - e, ':');
  place(band, 30 + e, ':');
  place(band, 30 + Math.floor(30 * ((value - center) / full) + 0.5), signal ? '*' : 'o');
  return band.join('');
}
export function standardizedBand(value: number, status: string): string {
  const band: string[] = Array(61).fill('.');
  place(band, 0, ':');
  place(band, 60, ':');
  place(band, 30, '|');
  place(band, 30 + Math.floor(10 * value + 0.5), status === 'ok' ? 'o' : '*');
  return band.join('');
}
