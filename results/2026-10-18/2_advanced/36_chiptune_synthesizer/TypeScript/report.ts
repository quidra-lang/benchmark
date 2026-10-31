export const hex2 = (value: number): string => value.toString(16).toUpperCase().padStart(2, '0');
export const hex1 = (value: number): string => value.toString(16).toUpperCase();
export function isqrt(value: number): number {
  let low = 0;
  let high = 1;
  while (high * high <= value) high *= 2;
  while (low + 1 < high) {
    const middle = Math.floor((low + high) / 2);
    if (middle * middle <= value) low = middle;
    else high = middle;
  }
  return low;
}
export function adler32(samples: number[]): string {
  let a = 1;
  let b = 0;
  for (const value of samples) {
    a = (a + value) % 65521;
    b = (b + a) % 65521;
  }
  return (b * 65536 + a).toString(16).toUpperCase().padStart(8, '0');
}
export function statistics(values: number[], center = 128) {
  let peak = 0;
  let minimum = values[0];
  let maximum = values[0];
  let squares = 0;
  let crossings = 0;
  for (let i = 0; i < values.length; i++) {
    const difference = values[i] - center;
    peak = Math.max(peak, Math.abs(difference));
    minimum = Math.min(minimum, values[i]);
    maximum = Math.max(maximum, values[i]);
    squares += difference * difference;
    if (i > 0 && values[i - 1] < center !== values[i] < center) crossings++;
  }
  return { peak, minimum, maximum, rms: isqrt(Math.floor(squares / values.length)), crossings };
}
export function hexDump(samples: number[]): string[] {
  const lines: string[] = [];
  for (let i = 0; i < samples.length; i += 32) {
    lines.push(
      samples
        .slice(i, i + 32)
        .map(hex2)
        .join(''),
    );
  }
  return lines;
}
