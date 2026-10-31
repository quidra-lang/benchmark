'use strict';

const fs = require('fs');
const lines = path => fs.readFileSync(path, 'ascii').split('\n').slice(0, -1);
const partitionGroups = tokens => tokens.map(token => token.split(',').map(Number));

function read() {
  const settings = {};
  for (const line of lines('input/cluster.txt')) {
    const [key, ...values] = line.split(' ');
    settings[key] = key === 'ELECTION' ? values.map(Number) : Number(values[0]);
  }
  const controls = new Map(), requests = [];
  for (const line of lines('input/script.txt')) {
    const [when, kind, ...args] = line.split(' '), time = Number(when);
    if (kind === 'REQUEST') {
      requests.push({ number: requests.length + 1, time, startNode: Number(args[0]), destination: Number(args[0]),
        scheduled: time, command: args.slice(1).join(' '), attempts: 0, redirects: 0, accepted: null, abandoned: false });
    } else {
      if (!controls.has(time)) controls.set(time, []);
      controls.get(time).push({ kind, args: kind === 'PARTITION' ? partitionGroups(args) : args.map(Number) });
    }
  }
  return { settings, controls, requests };
}

module.exports = { read, partitionGroups };
