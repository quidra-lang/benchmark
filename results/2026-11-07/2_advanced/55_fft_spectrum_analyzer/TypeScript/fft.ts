export interface Complex {
  re: number;
  im: number;
}
export const PI = 3.141592653589793;
export const complex = (re = 0, im = 0): Complex => ({ re, im });
export const add = (a: Complex, b: Complex): Complex => complex(a.re + b.re, a.im + b.im);
export const subtract = (a: Complex, b: Complex): Complex => complex(a.re - b.re, a.im - b.im);
export const multiply = (a: Complex, b: Complex): Complex =>
  complex(a.re * b.re - a.im * b.im, a.re * b.im + a.im * b.re);
export const scale = (a: Complex, factor: number): Complex => complex(a.re * factor, a.im * factor);
export const conjugate = (a: Complex): Complex => complex(a.re, -a.im);
export const squaredMagnitude = (a: Complex): number => a.re * a.re + a.im * a.im;
export const magnitude = (a: Complex): number => Math.sqrt(squaredMagnitude(a));
export const argument = (a: Complex): number => Math.atan2(a.im, a.re);
export const rot = (angle: number): Complex => complex(Math.cos(angle), -Math.sin(angle));
export function pow2(length: number): number {
  let size = 1;
  while (size < length) size *= 2;
  return size;
}
export const isPowerOfTwo = (length: number): boolean =>
  length > 0 && (length & (length - 1)) === 0;
export function radix2(input: Complex[], inverse = false): Complex[] {
  const values = input.map((value) => ({ ...value }));
  const size = values.length;
  for (let n = 1; n < size; n++) {
    let reversed = 0;
    let value = n;
    for (let bit = 1; bit < size; bit *= 2) {
      reversed = 2 * reversed + (value % 2);
      value = Math.floor(value / 2);
    }
    if (n < reversed) [values[n], values[reversed]] = [values[reversed], values[n]];
  }
  const twiddles = Array.from({ length: size / 2 }, (_, k) => {
    const value = rot((2 * PI * k) / size);
    return inverse ? conjugate(value) : value;
  });
  for (let width = 2; width <= size; width *= 2) {
    for (let start = 0; start < size; start += width) {
      for (let j = 0; j < width / 2; j++) {
        const upper = start + j;
        const lower = upper + width / 2;
        const t = multiply(twiddles[j * (size / width)], values[lower]);
        const u = values[upper];
        values[upper] = add(u, t);
        values[lower] = subtract(u, t);
      }
    }
  }
  return inverse ? values.map((value) => complex(value.re / size, value.im / size)) : values;
}
function bluestein(input: Complex[]): Complex[] {
  const length = input.length;
  const size = pow2(2 * length - 1);
  const chirp = input.map((_, n) => rot((PI * ((n * n) % (2 * length))) / length));
  const a = Array.from({ length: size }, (_, n) =>
    n < length ? multiply(input[n], chirp[n]) : complex(),
  );
  const b = Array.from({ length: size }, () => complex());
  b[0] = conjugate(chirp[0]);
  for (let n = 1; n < length; n++) b[n] = b[size - n] = conjugate(chirp[n]);
  const first = radix2(a);
  const second = radix2(b);
  const convolution = radix2(
    first.map((value, k) => multiply(value, second[k])),
    true,
  );
  return chirp.map((value, k) => multiply(value, convolution[k]));
}
export function transform(input: Complex[], inverse = false): Complex[] {
  if (isPowerOfTwo(input.length)) return radix2(input, inverse);
  if (!inverse) return bluestein(input);
  return bluestein(input.map(conjugate)).map((value) =>
    complex(value.re / input.length, -value.im / input.length),
  );
}
export function packedReal(input: number[]): Complex[] {
  const size = input.length;
  const half = size / 2;
  const packed = radix2(
    Array.from({ length: half }, (_, j) => complex(input[2 * j], input[2 * j + 1])),
  );
  return Array.from({ length: half + 1 }, (_, k) => {
    const a = packed[k % half];
    const b = conjugate(packed[(half - k) % half]);
    const difference = subtract(a, b);
    const even = scale(add(a, b), 0.5);
    const odd = complex(difference.im / 2, -difference.re / 2);
    return add(even, multiply(rot((2 * PI * k) / size), odd));
  });
}
export function convolution(a: number[], b: number[]): number[] {
  const length = a.length + b.length - 1;
  const size = pow2(length);
  const first = radix2(Array.from({ length: size }, (_, n) => complex(a[n] ?? 0)));
  const second = radix2(Array.from({ length: size }, (_, n) => complex(b[n] ?? 0)));
  return radix2(
    first.map((value, k) => multiply(value, second[k])),
    true,
  )
    .slice(0, length)
    .map((value) => value.re);
}
export function chirpZ(
  input: number[],
  start: number,
  step: number,
  count: number,
  sampleRate: number,
): Complex[] {
  const size = pow2(input.length + count - 1);
  const a = Array.from({ length: size }, () => complex());
  const b = a.map(() => complex());
  for (let n = 0; n < input.length; n++) {
    a[n] = multiply(
      scale(rot((2 * PI * start * n) / sampleRate), input[n]),
      rot((PI * step * (n * n)) / sampleRate),
    );
  }
  for (let m = -(input.length - 1); m < count; m++) {
    b[m < 0 ? m + size : m] = conjugate(rot((PI * step * (m * m)) / sampleRate));
  }
  const first = radix2(a);
  const second = radix2(b);
  const values = radix2(
    first.map((value, k) => multiply(value, second[k])),
    true,
  );
  return Array.from({ length: count }, (_, j) =>
    multiply(rot((PI * step * (j * j)) / sampleRate), values[j]),
  );
}
