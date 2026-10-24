'use strict';

function condition(mask, x, y) {
  switch (mask) {
    case 0: return (x + y) % 2 === 0;
    case 1: return y % 2 === 0;
    case 2: return x % 3 === 0;
    case 3: return (x + y) % 3 === 0;
    case 4: return (Math.floor(y / 2) + Math.floor(x / 3)) % 2 === 0;
    case 5: return (x * y) % 2 + (x * y) % 3 === 0;
    case 6: return ((x * y) % 2 + (x * y) % 3) % 2 === 0;
    case 7: return ((x + y) % 2 + (x * y) % 3) % 2 === 0;
  }
}

function apply(grid, areas, mask) {
  return grid.map((row, y) => row.map((value, x) => areas[y][x] === 'data' && condition(mask, x, y) ? value ^ 1 : value));
}

function penalties(grid) {
  const size = grid.length;
  let n1 = 0, n2 = 0, n3 = 0, dark = 0;
  const examine = values => {
    let length = 1;
    for (let i = 1; i <= size; i++) {
      if (i < size && values[i] === values[i - 1]) length++;
      else { if (length >= 5) n1 += length - 2; length = 1; }
    }
    const text = values.join('');
    for (let i = 0; i + 11 <= size; i++) {
      const pattern = text.slice(i, i + 11);
      if (pattern === '10111010000' || pattern === '00001011101') n3 += 40;
    }
  };
  for (let y = 0; y < size; y++) {
    examine(grid[y]);
    examine(grid.map(row => row[y]));
    for (let x = 0; x < size; x++) {
      dark += grid[y][x];
      if (x + 1 < size && y + 1 < size && grid[y][x] === grid[y][x + 1] &&
          grid[y][x] === grid[y + 1][x] && grid[y][x] === grid[y + 1][x + 1]) n2 += 3;
    }
  }
  const n4 = 10 * Math.floor(Math.abs(20 * dark - 10 * size * size) / (size * size));
  return { n1, n2, n3, n4, total: n1 + n2 + n3 + n4, dark };
}

module.exports = { condition, apply, penalties };
