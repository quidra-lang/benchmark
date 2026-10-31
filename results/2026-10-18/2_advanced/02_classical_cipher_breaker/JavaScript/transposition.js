'use strict';

function railNumber(index, rails) {
  const cycle = 2 * rails - 2;
  const offset = index % cycle;
  return Math.min(offset, cycle - offset);
}

function railFence(text, rails, decrypt) {
  const positions = Array.from({length: rails}, () => []);
  for (let index = 0; index < text.length; index++) {
    positions[railNumber(index, rails)].push(index);
  }
  const output = new Array(text.length);
  let cursor = 0;
  for (const rail of positions) {
    for (const index of rail) {
      if (decrypt) output[index] = text[cursor];
      else output[cursor] = text[index];
      cursor++;
    }
  }
  return output.join('');
}

function columnOrder(key) {
  return Array.from({length: key.length}, (_, index) => index)
    .sort((left, right) => key.charCodeAt(left) - key.charCodeAt(right) || left - right);
}

function rankString(key) {
  const ranks = new Array(key.length);
  columnOrder(key).forEach((column, rank) => {
    ranks[column] = String(rank + 1);
  });
  return ranks.join('');
}

function columnar(text, key, decrypt) {
  const width = key.length;
  const ranks = rankString(key);
  const order = new Array(width);
  for (let column = 0; column < width; column++) {
    order[Number(ranks[column]) - 1] = column;
  }
  const columns = Array(width).fill('');
  if (!decrypt) {
    for (let index = 0; index < text.length; index++) {
      columns[index % width] += text[index];
    }
    return order.map(column => columns[column]).join('');
  }
  let cursor = 0;
  for (const column of order) {
    const length = Math.floor((text.length + width - 1 - column) / width);
    columns[column] = text.slice(cursor, cursor + length);
    cursor += length;
  }
  const output = [];
  for (let index = 0; index < text.length; index++) {
    output.push(columns[index % width][Math.floor(index / width)]);
  }
  return output.join('');
}

module.exports = {railNumber, railFence, columnOrder, rankString, columnar};
