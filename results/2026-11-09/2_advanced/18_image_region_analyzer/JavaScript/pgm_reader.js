'use strict';

const fs = require('node:fs');

function readImages() {
    const text = fs.readFileSync('input/images.txt', 'ascii').replace(/#[^\n]*/g, '');
    const words = text.trim().split(/\s+/);
    const images = [];
    let position = 0;
    while (position < words.length) {
        position++;
        const name = words[position++];
        position++;
        const width = Number(words[position++]);
        const height = Number(words[position++]);
        const maxval = Number(words[position++]);
        const pixels = words.slice(position, position + width * height).map(Number);
        position += pixels.length;
        images.push({ name, width, height, maxval, pixels });
    }
    return images;
}

module.exports = { readImages };
