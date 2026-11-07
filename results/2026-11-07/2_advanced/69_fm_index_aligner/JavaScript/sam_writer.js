'use strict';

const fs = require('fs');
const { reverseComplement } = require('./sequence_io');

function ratio(numerator, denominator) { return denominator === 0 ? '-' : (numerator / denominator).toFixed(4); }

function header(references) {
  return ['@HD\tVN:1.6\tSO:unsorted', ...references.map(reference => `@SQ\tSN:${reference.name}\tLN:${reference.sequence.length}`),
    '@PG\tID:fm_index_aligner\tPN:fm_index_aligner\tVN:1.0'];
}

function record(read, result, references, maximumAlternatives) {
  if (result.reason) return [read.name, 4, '*', 0, 0, '*', '*', 0, 0, read.sequence, read.quality, `YM:Z:${result.reason}`].join('\t');
  const primary = result.alignments[0], reverse = primary.strand === 1;
  const fields = [read.name, reverse ? 16 : 0, references[primary.r].name, primary.pos + 1, result.mapq,
    primary.cigar, '*', 0, 0, reverse ? reverseComplement(read.sequence) : read.sequence,
    reverse ? Array.from(read.quality).reverse().join('') : read.quality,
    `NM:i:${primary.nm}`, `MD:Z:${primary.md}`, `AS:i:${result.score}`, `X0:i:${result.x0}`, `X1:i:${result.x1}`, `YM:Z:${result.method}`];
  const alternatives = result.alignments.slice(1);
  if (alternatives.length > 0 && alternatives.length <= maximumAlternatives) {
    fields.push('XA:Z:' + alternatives.map(alignment =>
      `${references[alignment.r].name},${alignment.strand === 0 ? '+' : '-'}${alignment.pos + 1},${alignment.cigar},${alignment.nm};`).join(''));
  }
  return fields.join('\t');
}

function write(path, lines) { fs.writeFileSync(path, lines.join('\n') + '\n', 'ascii'); }

module.exports = { ratio, header, record, write };
