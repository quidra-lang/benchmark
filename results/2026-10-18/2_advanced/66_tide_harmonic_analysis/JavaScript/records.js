'use strict';

const fs = require('node:fs');

function lines(path) {
  const result = fs.readFileSync(path, 'ascii').split('\n');
  result.pop();
  return result;
}

function absoluteMinute(datetime) {
  return Date.parse(datetime.replace(' ', 'T') + ':00Z') / 60000;
}

function datetime(epoch, minute) {
  return new Date((epoch + minute) * 60000).toISOString().slice(0, 16).replace('T', ' ');
}

function hourDatetime(epoch, hour) {
  return datetime(epoch, hour * 60);
}

function date(epoch, day) {
  return datetime(epoch, day * 1440).slice(0, 10);
}

function readParams() {
  const source = lines('input/params.txt');
  const params = {epoch: absoluteMinute(source[0].slice(6)), stations: []};
  let index = 1;
  while (source[index].startsWith('station ')) {
    params.stations.push({code: source[index].slice(8, 11), name: source[index].slice(12)});
    index++;
  }
  const next = () => source[index++].split(' ');
  params.reference = next()[1];
  params.flatRun = Number(next()[1]);
  const spike = next();
  params.spike = {window: Number(spike[1]), count: Number(spike[2]),
    factor: Number(spike[3]), minimum: Number(spike[4])};
  params.rayleigh = Number(next()[1]);
  params.snrMin = Number(next()[1]);
  params.topResiduals = Number(next()[1]);
  const surge = next();
  params.surge = {threshold: Number(surge[1]), hours: Number(surge[2])};
  const prediction = next();
  params.start = (absoluteMinute(prediction[1] + ' ' + prediction[2]) - params.epoch) / 60;
  params.hours = Number(prediction[3]);
  params.grid = Number(next()[1]);
  params.minRange = Number(next()[1]);
  params.correlationLag = Number(next()[1]);
  const plot = next();
  params.plot = {code: plot[1], hours: Number(plot[2]), top: Number(plot[3]),
    bottom: Number(plot[4]), step: Number(plot[5])};
  return params;
}

function readConstituents() {
  const source = lines('input/constituents.txt');
  const constituents = [];
  for (let index = 1; index <= Number(source[0]); index++) {
    const [name, speed] = source[index].split(' ');
    constituents.push({name, speed: Number(speed)});
  }
  return constituents;
}

function readAll() {
  const params = readParams();
  const constituents = readConstituents();
  const observations = new Map(params.stations.map(station => [station.code, []]));
  const source = lines('input/observations.csv');
  for (let index = 1; index < source.length; index++) {
    const [code, time, level] = source[index].split(',');
    observations.get(code).push({time: (absoluteMinute(time) - params.epoch) / 60,
      value: level === 'NA' ? null : Number(level),
      milli: level === 'NA' ? null : Number(level.replace('.', ''))});
  }
  return {params, constituents, observations};
}

module.exports = {readAll, datetime, hourDatetime, date};
