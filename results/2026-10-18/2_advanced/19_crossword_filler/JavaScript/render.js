'use strict';

function decimal(numerator, denominator, digits) {
    const factor = 10n ** BigInt(digits);
    const p = BigInt(numerator);
    const q = BigInt(denominator);
    const rounded = (2n * p * factor + q) / (2n * q);
    return (rounded / factor).toString() + '.' + (rounded % factor).toString().padStart(digits, '0');
}

function gridLines(template, state) {
    const lines = [];
    for (let r = 0; r < template.h; r++) lines.push(state.cells.slice(r * template.w, (r + 1) * template.w).join(''));
    return lines;
}

function numberDiagram(template) {
    const lines = [];
    for (let r = 0; r < template.h; r++) {
        const cells = [];
        for (let c = 0; c < template.w; c++) {
            const number = template.numbers[r * template.w + c];
            cells.push(template.rows[r][c] === '#' ? '##' : number === 0 ? ' .' : String(number).padStart(2, ' '));
        }
        lines.push(cells.join(' '));
    }
    return lines;
}

function listLine(slot, word, clue, pattern, theme) {
    if (word === null) return `${slot.number}. (unfilled) (${slot.length}) ${pattern} -`;
    return `${slot.number}. ${clue === null ? '(no clue)' : clue} (${slot.length}) ${word.word} ${word.score}` + (theme ? ' theme' : '');
}

module.exports = { decimal, gridLines, numberDiagram, listLine };
