'use strict';

const fs = require('fs');
const lines = path => fs.readFileSync(path, 'ascii').split('\n').slice(0, -1);

function read() {
  const references = [];
  for (const line of lines('input/reference.fasta')) {
    if (line.startsWith('>')) references.push({ name: line.slice(1).split(' ')[0], sequence: '', masked: 0 });
    else {
      const reference = references[references.length - 1];
      for (const base of line) if (base >= 'a' && base <= 'z') reference.masked++;
      reference.sequence += line.toUpperCase();
    }
  }
  const records = lines('input/reads.fastq'), reads = [];
  for (let i = 0; i < records.length; i += 4) reads.push({ name: records[i].slice(1),
    sequence: records[i + 1], quality: records[i + 3], qualities: Array.from(records[i + 3], character => character.charCodeAt(0) - 33) });
  const params = {};
  for (const line of lines('input/params.txt')) {
    const [key, ...values] = line.split(' ');
    params[key] = key === 'SCORES' || key === 'VARIANTS' ? values.map(Number) : Number(values[0]);
  }
  return { references, reads, params };
}

function reverseComplement(sequence) {
  const complements = { A: 'T', C: 'G', G: 'C', T: 'A', N: 'N' };
  return Array.from(sequence).reverse().map(base => complements[base]).join('');
}

module.exports = { read, reverseComplement };
