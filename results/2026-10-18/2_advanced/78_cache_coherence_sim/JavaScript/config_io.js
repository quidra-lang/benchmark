'use strict';

const fs = require('fs');
const decimalInteger = text => /^(0|[1-9][0-9]*)$/.test(text);
const hexDigits = text => /^[0-9a-f]{8}$/.test(text);
const hex = address => address.toString(16).padStart(8, '0');
const lines = path => fs.readFileSync(path, 'ascii').split('\n').slice(0, -1);

function read() {
  const config = { scenarios: [], regions: [], watches: [] };
  for (const line of lines('input/config.txt')) {
    const [key, ...fields] = line.split(' ');
    if (key === 'CORES') config.cores = Number(fields[0]);
    else if (key === 'LINE') config.line = Number(fields[0]);
    else if (key === 'L1' || key === 'L2') config[key.toLowerCase()] = { size: Number(fields[0]), ways: Number(fields[1]) };
    else if (key === 'LATENCY') config.latencies = fields.map(Number);
    else if (key === 'SCENARIO') config.scenarios.push({ name: fields[0], protocol: fields[1], l1Policy: fields[2], l2Policy: fields[3], order: config.scenarios.length });
    else if (key === 'PRIMARY') config.primary = fields[0];
    else if (key === 'INTERVAL') config.interval = Number(fields[0]);
    else if (key === 'TOP') config.top = Number(fields[0]);
    else if (key === 'REGION') config.regions.push({ name: fields[0], first: Number.parseInt(fields[1], 16), last: Number.parseInt(fields[2], 16) });
    else config.watches.push(Number.parseInt(fields[0], 16) / config.line);
  }
  for (const cache of [config.l1, config.l2]) cache.sets = cache.size / (config.line * cache.ways);
  config.capacity = config.l1.sets * config.l1.ways;
  return { config, trace: lines('input/trace.txt') };
}

function write(path, lines) { fs.writeFileSync(path, lines.length ? lines.join('\n') + '\n' : '', 'ascii'); }

module.exports = { read, decimalInteger, hexDigits, hex, write };
