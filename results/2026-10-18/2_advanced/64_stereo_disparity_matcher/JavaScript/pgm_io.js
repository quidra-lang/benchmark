const fs = require('node:fs');

function readPgm(path) {
  const lines = fs.readFileSync(path, 'ascii').trimEnd().split('\n');
  const [width, height] = lines[1].split(' ').map(Number);
  const pixels = lines.slice(3).flatMap(line => line.split(' ').map(Number));
  return { width, height, pixels };
}

function readParameters(path = 'input/params.txt') {
  const parameters = { samplePixels: [] };
  const textKeys = new Set(['wta_cost', 'sgm_cost']);
  const listKeys = new Set(['sad_windows', 'ssd_windows', 'census_windows']);
  for (const line of fs.readFileSync(path, 'ascii').trimEnd().split('\n')) {
    const [key, ...values] = line.split(' ');
    if (key === 'sample') parameters.samplePixels.push(values.map(Number));
    else if (textKeys.has(key)) parameters[key] = values[0];
    else if (listKeys.has(key)) parameters[key] = values.map(Number);
    else parameters[key] = Number(values[0]);
  }
  return parameters;
}

function writePgm(path, width, height, pixels) {
  const lines = ['P2', `${width} ${height}`, '255'];
  for (let y = 0; y < height; y++) {
    lines.push(pixels.slice(y * width, (y + 1) * width).join(' '));
  }
  fs.writeFileSync(path, lines.join('\n') + '\n', 'ascii');
}

module.exports = { readPgm, readParameters, writePgm };
