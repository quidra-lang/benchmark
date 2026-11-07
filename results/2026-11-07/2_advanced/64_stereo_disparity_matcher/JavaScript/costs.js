function clamped(image, width, height, x, y) {
  return image[Math.min(Math.max(y, 0), height - 1) * width
    + Math.min(Math.max(x, 0), width - 1)];
}

function boxSum(image, width, height, window) {
  const radius = Math.floor(window / 2);
  const paddedWidth = width + 2 * radius;
  const paddedHeight = height + 2 * radius;
  const integral = Array.from({ length: paddedHeight + 1 }, () => Array(paddedWidth + 1).fill(0));
  for (let y = 0; y < paddedHeight; y++) {
    let row = 0;
    for (let x = 0; x < paddedWidth; x++) {
      row += clamped(image, width, height, x - radius, y - radius);
      integral[y + 1][x + 1] = integral[y][x + 1] + row;
    }
  }
  const output = [];
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      output.push(integral[y + window][x + window] - integral[y][x + window]
        - integral[y + window][x] + integral[y][x]);
    }
  }
  return output;
}

function census(image, width, height) {
  const output = [];
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      let code = 0;
      for (let dy = -2; dy <= 2; dy++) {
        for (let dx = -2; dx <= 2; dx++) {
          if (dx !== 0 || dy !== 0) {
            code = code * 2 + Number(clamped(image, width, height, x + dx, y + dy) < image[y * width + x]);
          }
        }
      }
      output.push(code);
    }
  }
  return output;
}

function texture(image, width, height, window) {
  const gradient = [];
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      gradient.push(Math.abs(clamped(image, width, height, x + 1, y)
        - clamped(image, width, height, x - 1, y)));
    }
  }
  return boxSum(gradient, width, height, window);
}

function popcount(value) {
  let count = 0;
  while (value !== 0) {
    value &= value - 1;
    count++;
  }
  return count;
}

function costVolume(left, right, censusLeft, censusRight, width, height, kind, window, minimum, maximum) {
  const volume = Array.from({ length: left.length }, () => []);
  for (let disparity = minimum; disparity <= maximum; disparity++) {
    const costs = [];
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const p = y * width + x;
        const q = y * width + Math.max(x - disparity, 0);
        const difference = left[p] - right[q];
        costs.push(kind === 'census' ? popcount(censusLeft[p] ^ censusRight[q])
          : kind === 'sad' ? Math.abs(difference) : difference * difference);
      }
    }
    boxSum(costs, width, height, window).forEach((value, p) => volume[p].push(value));
  }
  return volume;
}

module.exports = { clamped, boxSum, census, texture, costVolume };
