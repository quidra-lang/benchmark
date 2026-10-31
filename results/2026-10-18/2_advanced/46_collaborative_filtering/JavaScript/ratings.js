'use strict';

const fs = require('node:fs');

function readLines(filename) {
  return fs.readFileSync(filename, 'ascii').slice(0, -1).split('\n');
}

function readData() {
  const train = readLines('input/ratings.csv').slice(1).map((line, index) => {
    const [user, item, rating, time] = line.split(',').map(Number);
    return { user, item, rating, time, index };
  });
  const catalog = new Map();
  for (const line of readLines('input/items.csv').slice(1)) {
    const [id, title, genreText] = line.split(',');
    catalog.set(Number(id), { id: Number(id), title, genreText, genres: genreText.split('|') });
  }
  const users = [...new Set(train.map(row => row.user))].sort((a, b) => a - b).map(id => ({ id, entries: [] }));
  const items = [...new Set(train.map(row => row.item))].sort((a, b) => a - b).map(id => ({ ...catalog.get(id), entries: [] }));
  const userIndex = new Map(users.map((user, index) => [user.id, index]));
  const itemIndex = new Map(items.map((item, index) => [item.id, index]));
  let total = 0;
  for (const row of train) {
    row.u = userIndex.get(row.user);
    row.i = itemIndex.get(row.item);
    users[row.u].entries.push(row);
    items[row.i].entries.push(row);
    total += row.rating;
  }
  function organize(groups, key) {
    for (const group of groups) {
      group.entries.sort((a, b) => a[key] - b[key]);
      group.ratings = new Map(group.entries.map(row => [row[key], row.rating]));
      group.count = group.entries.length;
      group.sum = 0;
      for (const row of group.entries) group.sum += row.rating;
      group.mean = group.sum / group.count;
    }
  }
  organize(users, 'i');
  organize(items, 'u');
  const test = readLines('input/test.csv').slice(1).map((line, index) => {
    const [user, item, rating] = line.split(',').map(Number);
    return { user, item, rating, index, u: userIndex.get(user), i: itemIndex.get(item) };
  });
  const settings = {};
  const names = {
    NEIGHBORS: 'neighbors', SHRINKAGE: 'shrinkage', MIN_SIMILARITY: 'minSimilarity', FACTORS: 'factors',
    LEARNING_RATE: 'learningRate', REGULARIZATION: 'regularization', EPOCHS: 'epochs', ALS_REG: 'alsReg',
    ALS_ITERATIONS: 'alsIterations', SEED: 'seed', TOP_N: 'topN', TIME_BUCKETS: 'timeBuckets', LIST_SIZE: 'listSize'
  };
  const lists = { CUTOFFS: 'cutoffs', NEIGHBOR_GRID: 'neighborGrid', USER_GROUPS: 'userGroups', ITEM_GROUPS: 'itemGroups',
    RECOMMEND_USERS: 'recommendUsers', SIMILAR_ITEMS: 'similarItems' };
  for (const line of readLines('input/params.txt')) {
    const [keyword, ...fields] = line.split(' ');
    const values = fields.map(Number);
    if (keyword === 'BIAS_REG') [settings.itemReg, settings.userReg] = values;
    else if (names[keyword]) settings[names[keyword]] = values[0];
    else settings[lists[keyword]] = values;
  }
  return { train, test, catalog, users, items, userIndex, itemIndex, settings, mean: total / train.length };
}

module.exports = { readData };
