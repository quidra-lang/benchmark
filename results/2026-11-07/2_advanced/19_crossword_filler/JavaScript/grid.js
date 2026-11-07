'use strict';

const isWhite = cell => cell !== '#';

function firstAsymmetry(rows, kind) {
    for (let r = 0; r < rows.length; r++) {
        for (let c = 0; c < rows[r].length; c++) {
            const otherRow = kind === 'rot180' ? rows.length - 1 - r : r;
            const otherColumn = rows[r].length - 1 - c;
            if (isWhite(rows[r][c]) !== isWhite(rows[otherRow][otherColumn])) return { r, c };
        }
    }
    return null;
}

function componentCount(rows) {
    const h = rows.length;
    const w = rows[0].length;
    const seen = Array.from({ length: h }, () => Array(w).fill(false));
    let count = 0;
    for (let r = 0; r < h; r++) {
        for (let c = 0; c < w; c++) {
            if (!isWhite(rows[r][c]) || seen[r][c]) continue;
            count++;
            const pending = [{ r, c }];
            seen[r][c] = true;
            while (pending.length > 0) {
                const cell = pending.pop();
                for (const [dr, dc] of [[-1, 0], [1, 0], [0, -1], [0, 1]]) {
                    const rr = cell.r + dr;
                    const cc = cell.c + dc;
                    if (rr < 0 || rr >= h || cc < 0 || cc >= w || seen[rr][cc] || !isWhite(rows[rr][cc])) continue;
                    seen[rr][cc] = true;
                    pending.push({ r: rr, c: cc });
                }
            }
        }
    }
    return count;
}

module.exports = { isWhite, firstAsymmetry, componentCount };
