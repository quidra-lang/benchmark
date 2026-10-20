'use strict';

const fs = require('node:fs');
const readLines = name => fs.readFileSync('input/' + name, 'ascii').trimEnd().split('\n');

function readInput() {
  const stations = readLines('stations.csv').slice(1).map((line, index) => {
    const [code, x, y, elevation] = line.split(',');
    return { index, code, x: Number(x), y: Number(y), elevation: Number(elevation) };
  });
  const waveformLines = readLines('waveforms.txt');
  let position = 0;
  for (const station of stations) {
    const header = waveformLines[position++].split(' ');
    station.start = Number(header[2]);
    const count = Number(header[3]);
    station.samples = [];
    while (station.samples.length < count) station.samples.push(...waveformLines[position++].split(' ').map(Number));
  }
  const fields = readLines('params.txt').map(line => line.split(' ').slice(1).map(Number));
  const params = {
    staWindow: fields[0][0], ltaWindow: fields[1][0], triggerOn: fields[2], triggerOff: fields[3],
    minDuration: fields[4][0], noiseLevel: fields[5][0], amplitudeWindow: fields[6][0], clipLevel: fields[7][0],
    associationWindow: fields[8][0], minStations: fields[9][0], velocity: fields[10][0],
    gridX: fields[11], gridY: fields[12], gridZ: fields[13], residualLimit: fields[14][0],
    qualityA: fields[15], qualityB: fields[16], cluster: fields[17],
    localMagnitude: fields[18], durationMagnitude: fields[19],
    mapArea: fields[20], mapSize: fields[21], section: fields[22], timeline: fields[23]
  };
  return { stations, params };
}

module.exports = { readInput };
