const fs = require('node:fs');

function readLines(path) {
  return fs.readFileSync(path, 'ascii').slice(0, -1).split('\n');
}

function readDataset() {
  const lines = readLines('input/data.csv');
  const features = lines[0].split(',').slice(2);
  const observations = lines.slice(1).map(line => {
    const [id, label, ...values] = line.split(',');
    return { id, label, values: values.map(Number) };
  });
  const parameters = new Map(readLines('input/params.txt').map(line => {
    const [name, ...values] = line.split(' ');
    return [name, values];
  }));
  return { features, observations, parameters };
}

function writeReports(reports) {
  fs.mkdirSync('output', { recursive: true });
  for (const [name, lines] of Object.entries(reports)) {
    fs.writeFileSync(`output/${name}`, lines.join('\n') + '\n', 'ascii');
  }
}

module.exports = { readDataset, writeReports };
