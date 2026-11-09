'use strict';

const fs = require('node:fs');

function leap(year) {
  return year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
}

function monthLengths(year) {
  return [31, leap(year) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
}

function beforeYear(year) {
  const previous = year - 1;
  return 365 * previous + Math.floor(previous / 4) - Math.floor(previous / 100) + Math.floor(previous / 400);
}

function dayNumber(text) {
  const [year, month, day] = text.split('-').map(Number);
  let result = beforeYear(year) - beforeYear(1970) + day - 1;
  const lengths = monthLengths(year);
  for (let index = 0; index < month - 1; index++) result += lengths[index];
  return result;
}

function dateText(value) {
  let year = 1970;
  while (value < 0) {
    year--;
    value += leap(year) ? 366 : 365;
  }
  while (value >= (leap(year) ? 366 : 365)) {
    value -= leap(year) ? 366 : 365;
    year++;
  }
  const lengths = monthLengths(year);
  let month = 0;
  while (value >= lengths[month]) value -= lengths[month++];
  return `${String(year).padStart(4, '0')}-${String(month + 1).padStart(2, '0')}-${String(value + 1).padStart(2, '0')}`;
}

function convert(text, type) {
  if (text === '') return null;
  if (type === 'DATE') return dayNumber(text);
  if (type === 'INT') return Number(text);
  if (type === 'BOOL') return text === 'true';
  return text;
}

function valueText(value, type, recovered = false) {
  if (value === null) return recovered ? '' : 'NULL';
  return type === 'DATE' ? dateText(value) : String(value);
}

function readInputs() {
  const lines = name => fs.readFileSync('input/' + name, 'ascii').slice(0, -1).split('\n');
  const schema = lines('schema.txt').map((line, number) => {
    const [name, type, nullability] = line.split(' ');
    return {name, type, nullable: nullability === 'NULLABLE', number};
  });
  const table = lines('table.csv').slice(1).map(line =>
    line.split(',').map((field, index) => convert(field, schema[index].type)));
  const options = {encodings: new Map()};
  for (const line of lines('options.txt')) {
    const fields = line.split(' ');
    if (fields[0] === 'encoding') options.encodings.set(fields[1], fields[2]);
    else options[fields[0]] = Number(fields[1]);
  }
  return {schema, table, options, queries: lines('queries.txt'),
    damaged: Buffer.from(lines('damaged.hex').join(''), 'hex')};
}

function writeFiles(files) {
  fs.mkdirSync('output', {recursive: true});
  for (const [name, lines] of Object.entries(files)) {
    fs.writeFileSync('output/' + name, lines.join('\n') + (lines.length ? '\n' : ''), 'ascii');
  }
}

module.exports = {readInputs, dayNumber, dateText, convert, valueText, writeFiles};
