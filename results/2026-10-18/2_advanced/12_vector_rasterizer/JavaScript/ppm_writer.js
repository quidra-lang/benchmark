'use strict';

const fs = require('node:fs');
const { floorDiv } = require('./canvas');

function writeImages(image, width, height) {
  fs.mkdirSync('output', { recursive: true });
  const ppm = ['P3', `${width} ${height}`, '255'];
  for (let y = 0; y < height; y++) ppm.push(image.slice(y * width, (y + 1) * width).flat().join(' '));
  fs.writeFileSync('output/image.ppm', ppm.join('\n') + '\n', 'ascii');
  const preview = [], shades = '@%#*+=-:,.';
  for (let y = 0; y < height; y += 4) {
    let line = '';
    for (let x = 0; x < width; x += 2) {
      let total = 0;
      for (let j = 0; j < 4; j++) for (let i = 0; i < 2; i++) {
        const [red, green, blue] = image[(y + j) * width + x + i];
        total += 299 * red + 587 * green + 114 * blue;
      }
      const brightness = floorDiv(total, 8000);
      line += shades[floorDiv(brightness * 10, 256)];
    }
    preview.push(line);
  }
  fs.writeFileSync('output/preview.txt', preview.join('\n') + '\n', 'ascii');
}

module.exports = { writeImages };
