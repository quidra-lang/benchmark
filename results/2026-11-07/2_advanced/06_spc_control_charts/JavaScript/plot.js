'use strict';

function place(band, position, character) {
  band[Math.max(0, Math.min(60, position))] = character;
}

function variableBand(control, value, signal) {
  const band = Array(61).fill('.');
  const position = point => Math.floor(60 * ((point - control.lcl) / (control.ucl - control.lcl)) + 0.5);
  place(band, 0, ':');
  place(band, 60, ':');
  place(band, position(control.cl), '|');
  place(band, position(value), signal ? '*' : 'o');
  return band.join('');
}

function cusumBand(plus, minus, threshold, upperSignal, lowerSignal) {
  const band = Array(61).fill('.');
  place(band, 0, ':');
  place(band, 60, ':');
  place(band, 30, '|');
  if (minus > 0) {
    const distance = Math.min(30, Math.floor(30 * (minus / threshold) + 0.5));
    place(band, 30 - distance, lowerSignal ? '*' : '-');
  }
  if (plus > 0) {
    const distance = Math.min(30, Math.floor(30 * (plus / threshold) + 0.5));
    place(band, 30 + distance, upperSignal ? '*' : '+');
  }
  return band.join('');
}

function averageBand(value, width, fullWidth, center, signal) {
  const band = Array(61).fill('.');
  const boundary = Math.min(30, Math.floor(30 * (width / fullWidth) + 0.5));
  const distance = (value - center) / fullWidth;
  place(band, 30, '|');
  place(band, 30 - boundary, ':');
  place(band, 30 + boundary, ':');
  place(band, 30 + Math.floor(30 * distance + 0.5), signal ? '*' : 'o');
  return band.join('');
}

function standardizedBand(value, status) {
  const band = Array(61).fill('.');
  place(band, 0, ':');
  place(band, 60, ':');
  place(band, 30, '|');
  place(band, 30 + Math.floor(10 * value + 0.5), status === 'ok' ? 'o' : '*');
  return band.join('');
}

module.exports = {variableBand, cusumBand, averageBand, standardizedBand};
