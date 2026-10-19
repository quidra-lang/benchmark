'use strict';

const bases = [1000003, 1500007, 2750159, 4194301];
const initials = [11, 23, 37, 53];

function hash(text) {
    let result = '';
    for (let lane = 0; lane < bases.length; lane++) {
        let value = initials[lane];
        for (let i = 0; i < text.length; i++) value = (value * bases[lane] + text.charCodeAt(i)) % 2147483647;
        for (const suffix of [text.length, 0, 0]) value = (value * bases[lane] + suffix) % 2147483647;
        result += value.toString(16).padStart(8, '0');
    }
    return result;
}

function merkle(hashes) {
    let current = hashes.slice();
    while (current.length > 1) {
        if (current.length % 2 === 1) current.push(current.at(-1));
        const next = [];
        for (let i = 0; i < current.length; i += 2) next.push(hash(current[i] + current[i + 1]));
        current = next;
    }
    return current[0];
}

const short = value => value.slice(0, 8);

module.exports = { hash, merkle, short };
