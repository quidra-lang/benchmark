'use strict';

const {readLines, parseObject} = require('./object_parser');

function readArchive(filename) {
  const lines = readLines('input/' + filename);
  const members = [];
  let index = 0;
  while (index < lines.length) {
    const words = lines[index].split(' ');
    const parsed = parseObject(lines, index + 1, `${filename}(${words[1]})`);
    members.push({object: parsed.object, exports: words.slice(2), loaded: false});
    index = parsed.next;
  }
  return {name: filename, members};
}

function scan(archive, isUndefined, extract) {
  let total = 0;
  let count;
  do {
    count = 0;
    for (const member of archive.members) {
      if (member.loaded) continue;
      const reason = member.exports.find(isUndefined);
      if (reason === undefined) continue;
      member.loaded = true;
      extract(member.object, reason);
      count++;
      total++;
    }
  } while (count !== 0);
  return total;
}

module.exports = {readArchive, scan};
