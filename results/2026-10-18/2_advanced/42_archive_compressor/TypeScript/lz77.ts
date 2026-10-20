import { DecodingError } from './bitio.ts';
export type Token = { literal: number } | { distance: number; length: number };
export function tokenize(data: Uint8Array, offsetBits: number, lengthBits: number): Token[] {
    const window = 2 ** offsetBits, lookahead = 2 ** lengthBits + 2, previous: number[] = Array(data.length).fill(-1), latest = new Map<number, number>();
    for (let i = 0; i + 2 < data.length; i++) { const key = data[i] * 65536 + data[i + 1] * 256 + data[i + 2]; previous[i] = latest.get(key) ?? -1; latest.set(key, i); }
    const tokens: Token[] = []; let i = 0;
    while (i < data.length) {
        const maximum = Math.min(lookahead, data.length - i); let bestLength = 2, bestDistance = 0, candidate = maximum >= 3 ? previous[i] : -1;
        // Equal prefixes are visited from nearest to farthest to preserve ties.
        while (candidate >= 0 && i - candidate <= window) { const distance = i - candidate; let length = 3; while (length < maximum && data[i + length] === data[i + length - distance]) length++; if (length > bestLength) { bestLength = length; bestDistance = distance; } if (length === maximum) break; candidate = previous[candidate]; }
        if (bestDistance) { tokens.push({ distance: bestDistance, length: bestLength }); i += bestLength; } else tokens.push({ literal: data[i++] });
    }
    return tokens;
}
export function copyMatch(output: number[], distance: number, length: number, originalLength: number) {
    if (distance > output.length) throw new DecodingError('bad_offset'); if (output.length + length > originalLength) throw new DecodingError('overrun');
    for (let i = 0; i < length; i++) output.push(output[output.length - distance]);
}
