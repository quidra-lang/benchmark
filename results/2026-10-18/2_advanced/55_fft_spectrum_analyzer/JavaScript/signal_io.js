'use strict';

const fs = require('node:fs');
const lines = name => fs.readFileSync('input/' + name, 'ascii').split('\n').slice(0, -1);

function readInput() {
  const signal = lines('signal.csv').map(line => line.split(',').map(Number));
  const [sampleRate, count] = signal[0];
  const channels = [signal.slice(1).map(row => row[0]), signal.slice(1).map(row => row[1])];
  const fields = lines('params.txt').map(line => line.split(' ').slice(1));
  const params = {
    mainLength: Number(fields[0][0]), mainWindow: fields[1][0], threshold: Number(fields[2][0]),
    peakCount: Number(fields[3][0]), fundamental: Number(fields[4][0]), search: Number(fields[4][1]),
    welchLength: Number(fields[5][0]), welchWindow: fields[5][1],
    frameLength: Number(fields[6][0]), hop: Number(fields[6][1]), shadeWidth: Number(fields[6][2]), frameWindow: fields[6][3],
    onsetFactor: Number(fields[7][0]), pitch: fields[8].map(Number), bandpass: fields[9].map(Number),
    notch: fields[10].map(Number), envelope: fields[11].map(Number), zoom: fields[12].map(Number),
    fir: fields[13].map(Number), maxLag: Number(fields[14][0]), bands: fields[15].map(Number),
    thirdOctave: fields[16].map(Number), blockLength: Number(fields[17][0])
  };
  return { sampleRate, count, channels, params };
}

module.exports = { readInput };
