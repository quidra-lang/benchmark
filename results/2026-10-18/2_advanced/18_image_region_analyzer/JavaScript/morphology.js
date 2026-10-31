'use strict';

function at(mask, x, y, width, height) {
    return x >= 0 && x < width && y >= 0 && y < height ? mask[y * width + x] : 0;
}

function transform(mask, width, height, offsets, erosion) {
    const result = new Uint8Array(mask.length);
    for (let y = 0; y < height; y++) {
        for (let x = 0; x < width; x++) {
            let foreground = erosion ? 1 : 0;
            for (const [dx, dy] of offsets) {
                const nx = erosion ? x + dx : x - dx;
                const ny = erosion ? y + dy : y - dy;
                const value = at(mask, nx, ny, width, height);
                if (erosion && !value) {
                    foreground = 0;
                    break;
                }
                if (!erosion && value) {
                    foreground = 1;
                    break;
                }
            }
            result[y * width + x] = foreground;
        }
    }
    return result;
}

function applyMorphology(mask, width, height, offsets, operation) {
    if (operation === 'erode') return transform(mask, width, height, offsets, true);
    if (operation === 'dilate') return transform(mask, width, height, offsets, false);
    if (operation === 'open') {
        return transform(transform(mask, width, height, offsets, true), width, height, offsets, false);
    }
    return transform(transform(mask, width, height, offsets, false), width, height, offsets, true);
}

function neighborhood(mask, x, y, width, height) {
    return [
        at(mask, x, y - 1, width, height), at(mask, x + 1, y - 1, width, height),
        at(mask, x + 1, y, width, height), at(mask, x + 1, y + 1, width, height),
        at(mask, x, y + 1, width, height), at(mask, x - 1, y + 1, width, height),
        at(mask, x - 1, y, width, height), at(mask, x - 1, y - 1, width, height),
    ];
}

function transitions(values) {
    let count = 0;
    for (let index = 0; index < values.length; index++) {
        if (values[index] === 0 && values[(index + 1) % values.length] === 1) count++;
    }
    return count;
}

function thin(mask, width, height) {
    const result = new Uint8Array(mask);
    while (true) {
        let removed = 0;
        for (let step = 0; step < 2; step++) {
            const pending = [];
            for (let y = 0; y < height; y++) {
                for (let x = 0; x < width; x++) {
                    const index = y * width + x;
                    if (!result[index]) continue;
                    const p = neighborhood(result, x, y, width, height);
                    let count = 0;
                    for (const value of p) count += value;
                    if (count < 2 || count > 6 || transitions(p) !== 1) continue;
                    if (step === 0) {
                        if (p[0] * p[2] * p[4] !== 0 || p[2] * p[4] * p[6] !== 0) continue;
                    } else {
                        if (p[0] * p[2] * p[6] !== 0 || p[0] * p[4] * p[6] !== 0) continue;
                    }
                    pending.push(index);
                }
            }
            for (const index of pending) result[index] = 0;
            removed += pending.length;
        }
        if (removed === 0) return result;
    }
}

module.exports = { applyMorphology, neighborhood, transitions, thin };
