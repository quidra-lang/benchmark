const fs = require('node:fs');

const compareText = (left, right) => left < right ? -1 : left > right ? 1 : 0;

function splitKey(key) {
  const position = key.lastIndexOf('.');
  return [key.slice(0, position), key.slice(position + 1)];
}

function compareKeys(left, right) {
  const [leftSection, leftName] = splitKey(left);
  const [rightSection, rightName] = splitKey(right);
  return compareText(leftSection, rightSection) || compareText(leftName, rightName);
}

class Schema {
  constructor(path) {
    this.specs = [];
    this.exact = new Map();
    const lines = fs.readFileSync(path, 'ascii').split('\n').slice(0, -1);
    for (let index = 0; index < lines.length; index++) {
      const line = lines[index];
      if (line.trim() === '' || line.startsWith('#')) continue;
      const [pattern, type, ...words] = line.split(' ');
      const [section, key] = splitKey(pattern);
      const attributes = new Map();
      for (const word of words) {
        const equals = word.indexOf('=');
        attributes.set(equals < 0 ? word : word.slice(0, equals), equals < 0 ? true : word.slice(equals + 1));
      }
      const spec = { pattern, type, key, parts: section.split('.'), wildcard: section.includes('*'),
        attributes, line: index + 1 };
      this.specs.push(spec);
      if (!spec.wildcard) this.exact.set(pattern, spec);
    }
  }

  matches(spec, section) {
    const parts = section.split('.');
    return parts.length === spec.parts.length && spec.parts.every((part, i) => part === '*' || part === parts[i]);
  }

  find(key) {
    if (this.exact.has(key)) return this.exact.get(key);
    const [section, name] = splitKey(key);
    return this.specs.find(spec => spec.wildcard && spec.key === name && this.matches(spec, section)) || null;
  }

  targets(spec, sections) {
    if (!spec.wildcard) return [spec.pattern];
    return [...sections].sort(compareText).filter(section => this.matches(spec, section))
      .map(section => `${section}.${spec.key}`).filter(key => this.find(key) === spec);
  }
}

module.exports = { Schema, compareText, compareKeys, splitKey };
