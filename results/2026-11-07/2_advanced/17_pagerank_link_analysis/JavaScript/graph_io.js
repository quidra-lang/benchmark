const fs = require('node:fs');

function readLines(path) {
  return fs.readFileSync(path, 'ascii').slice(0, -1).split('\n');
}

function readInput() {
  const pages = readLines('input/pages.csv').slice(1).map(line => {
    const [id, host, title] = line.split(',');
    return { id: Number(id), host, title, words: new Set(title.split(' ')) };
  }).sort((first, second) => first.id - second.id);
  const records = readLines('input/links.csv').slice(1).map((line, index) => {
    const [source, destination] = line.split(',').map(Number);
    return { source, destination, line: index + 2 };
  });
  const queries = readLines('input/queries.txt').map(line => {
    const [words, seeds] = line.split(' | ');
    return { words: words.split(' '), seeds: seeds.split(' ').map(Number) };
  });
  const params = new Map(readLines('input/params.txt').map(line => {
    const [name, ...values] = line.split(' ');
    return [name, values.map(Number)];
  }));
  const settings = {
    damping: params.get('DAMPING')[0],
    iterations: params.get('PAGERANK_ITERATIONS')[0],
    tolerance: params.get('TOLERANCE')[0],
    sweep: params.get('DAMPING_SWEEP'),
    trusted: params.get('TRUSTED'),
    spamTop: params.get('SPAM_TOP')[0],
    spamThreshold: params.get('SPAM_THRESHOLD')[0],
    hitsIterations: params.get('HITS_ITERATIONS')[0],
    top: params.get('TOP_K')[0],
    rootLimit: params.get('ROOT_LIMIT')[0],
    neighborLimit: params.get('NEIGHBOR_LIMIT')[0],
  };
  return { pages, records, queries, settings };
}

module.exports = { readInput };
