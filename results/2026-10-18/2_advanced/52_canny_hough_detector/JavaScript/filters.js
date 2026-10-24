'use strict';

function at(values, x, y, width, height) {
  x = Math.min(Math.max(x, 0), width - 1);
  y = Math.min(Math.max(y, 0), height - 1);
  return values[y * width + x];
}

function smooth(image, params) {
  const { width, height, pixels } = image;
  const size = params.gauss_size, half = (size - 1) / 2;
  const result = new Int32Array(width * height);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      let sum = 0;
      for (let j = 0; j < size; j++) {
        for (let i = 0; i < size; i++) {
          sum += params.gauss_kernel[j * size + i] *
            at(pixels, x + i - half, y + j - half, width, height);
        }
      }
      result[y * width + x] = Math.floor(sum / params.gauss_divisor);
    }
  }
  return result;
}

function gradient(values, width, height) {
  const gx = new Int32Array(width * height), gy = new Int32Array(width * height);
  const magnitude = new Int32Array(width * height);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const q = [];
      for (let dy = -1; dy <= 1; dy++) {
        for (let dx = -1; dx <= 1; dx++) q.push(at(values, x + dx, y + dy, width, height));
      }
      const index = y * width + x;
      gx[index] = q[2] + 2 * q[5] + q[8] - q[0] - 2 * q[3] - q[6];
      gy[index] = q[6] + 2 * q[7] + q[8] - q[0] - 2 * q[1] - q[2];
      magnitude[index] = Math.abs(gx[index]) + Math.abs(gy[index]);
    }
  }
  return { gx, gy, magnitude };
}

module.exports = { at, smooth, gradient };
