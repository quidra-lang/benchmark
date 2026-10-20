import { mkdirSync, writeFileSync } from 'node:fs';

export const floorRatio = (a: number,b: number): number => Number(BigInt(a)/BigInt(b));
export function ceilRatio(a: number,b: number): number {
  const numerator = BigInt(a), denominator = BigInt(b);
  return Number((numerator+denominator-1n)/denominator);
}
export function percentage(a: number,b: number): number {
  const numerator = BigInt(a), denominator = BigInt(b);
  return Number((200n*numerator+denominator)/(2n*denominator));
}
export function tableLine(label: string,values: (string | number)[],labelWidth: number,columnWidth: number): string {
  return label.padEnd(labelWidth)+values.map(v => String(v).padStart(columnWidth)).join('');
}
export function writeReports(reports: Record<string,string[]>): void {
  mkdirSync('output',{recursive:true});
  for (const [name,lines] of Object.entries(reports)) writeFileSync(`output/${name}`,lines.length ? lines.join('\n')+'\n' : '','ascii');
}
