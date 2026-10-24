'use strict';

function floorDiv(numerator, denominator) {
  const n = BigInt(numerator), d = BigInt(denominator);
  const quotient = n / d;
  return Number(quotient - (n < 0n && n % d !== 0n ? 1n : 0n));
}

function round(numerator, denominator) {
  if (denominator < 0) [numerator, denominator] = [-numerator, -denominator];
  return floorDiv(2 * numerator + denominator, 2 * denominator);
}

class Layer {
  constructor(block, width, height, number) {
    Object.assign(this, block, { number, commands: 0, errors: 0 });
    this.pixels = Array(width * height).fill(null);
  }

  paint(index, color, line) {
    this.pixels[index] = { color, line };
  }

  erase(index) {
    this.pixels[index] = null;
  }

  alpha(index) {
    return this.pixels[index] === null ? 0 : round(this.pixels[index].color[3] * this.opacity, 255);
  }
}

function composite(layers, background, size) {
  const image = Array.from({ length: size }, () => background.slice(0, 3));
  for (const layer of layers) {
    for (let index = 0; index < size; index++) {
      if (layer.pixels[index] === null) continue;
      const color = layer.pixels[index].color, alpha = layer.alpha(index);
      for (let channel = 0; channel < 3; channel++) {
        const current = image[index][channel];
        let source = color[channel];
        if (layer.mode === 'multiply') source = round(source * current, 255);
        else if (layer.mode === 'screen') source = 255 - round((255 - source) * (255 - current), 255);
        image[index][channel] = round(alpha * source + (255 - alpha) * current, 255);
      }
    }
  }
  return image;
}

module.exports = { floorDiv, round, Layer, composite };
