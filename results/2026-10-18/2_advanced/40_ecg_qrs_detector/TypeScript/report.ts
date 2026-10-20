export const div = (a: number, b: number): number => Math.floor(a / b);
export const rdiv = (a: number, b: number): number => div(2 * a + b, 2 * b);
export function decimal2(value: number): string {
  const magnitude = Math.abs(value);
  return (value < 0 ? '-' : '') + div(magnitude, 100) + '.' + String(magnitude % 100).padStart(2, '0');
}
export const decimal4 = (value: number): string => div(value, 10000) + '.' + String(value % 10000).padStart(4, '0');
export function fraction(a: number, b: number): string {
  let x = a, y = b;
  while (y !== 0) [x, y] = [y, x % y];
  return `${div(a, x)}/${div(b, x)}`;
}
export const ratio = (a: number, b: number): string => b === 0 ? `${a}/${b} none`
  : `${a}/${b} reduced=${fraction(a, b)} percent=${decimal2(rdiv(10000 * a, b))}`;
export const missing = (value: number | string | null): string => value === null ? '-' : String(value);
