'use strict';

const fs = require('node:fs');

function readLines(path) {
  return fs.readFileSync(path, 'ascii').slice(0, -1).split('\n');
}

function readDataset() {
  const subjects = readLines('input/subjects.csv').slice(1).map(line => {
    const [id, group, time, event, age, sex, stage] = line.split(',');
    return {
      id: Number(id), group, time: Number(time), event: Number(event),
      age: Number(age), sex, stage: Number(stage)
    };
  });
  subjects.sort((a, b) => a.id - b.id);
  const fields = readLines('input/params.txt').map(line => line.split(' ').slice(1));
  const [width, height, time, divisions] = fields[9].map(Number);
  const params = {
    groups: fields[0],
    reportTimes: fields[1].map(Number),
    tau: Number(fields[2][0]),
    lifeWidth: Number(fields[3][0]),
    lifeCount: Number(fields[3][1]),
    strata: fields[4][0],
    subgroups: fields[5],
    landmark: Number(fields[6][0]),
    covariates: fields[7],
    residuals: Number(fields[8][0]),
    plot: { width, height, time, divisions }
  };
  return { subjects, params };
}

module.exports = { readDataset };
