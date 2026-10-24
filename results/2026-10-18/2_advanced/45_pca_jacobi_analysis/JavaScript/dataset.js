'use strict';

const fs = require('node:fs');

function readLines(filename) {
  return fs.readFileSync(filename, 'ascii').slice(0, -1).split('\n');
}

function readDataset() {
  const lines = readLines('input/data.csv');
  const names = lines[0].split(',').slice(1);
  const rows = input => input.slice(1).map(line => {
    const [id, ...values] = line.split(',');
    return { id, values: values.map(value => value === 'NA' ? null : Number(value)) };
  });
  const settings = {};
  for (const line of readLines('input/params.txt')) {
    const [keyword, ...values] = line.split(' ');
    switch (keyword) {
      case 'MISSING': settings.missing = values[0]; break;
      case 'SCALING': settings.scaling = values[0]; break;
      case 'COMPONENTS': settings.components = values[0]; break;
      case 'CUMULATIVE_TARGET': settings.target = Number(values[0]); break;
      case 'PARALLEL': [settings.parallel, settings.seed] = values.map(Number); break;
      case 'T2_LIMIT': settings.t2Limit = Number(values[0]); break;
      case 'SPE_LIMIT': settings.speLimit = Number(values[0]); break;
      case 'VARIMAX_CYCLES': settings.cycles = Number(values[0]); break;
      case 'TOP_ROWS': settings.top = Number(values[0]); break;
      case 'SCREE_WIDTH': settings.screeWidth = Number(values[0]); break;
      case 'BIPLOT_SIZE': [settings.biplotWidth, settings.biplotHeight] = values.map(Number); break;
      case 'CIRCLE_RADIUS': settings.radius = Number(values[0]); break;
      case 'DIAGNOSTIC_SIZE': [settings.diagnosticWidth, settings.diagnosticHeight] = values.map(Number); break;
    }
  }
  return { names, rows: rows(lines), supplementary: rows(readLines('input/supplementary.csv')), settings };
}

module.exports = { readDataset };
