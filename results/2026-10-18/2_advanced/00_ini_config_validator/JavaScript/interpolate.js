const { compareKeys, splitKey } = require('./schema');

const REFERENCE = /^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$/;

function expandAll(configuration, report) {
  const results = new Map(), active = [], cycleKeys = new Set();
  function expand(key) {
    if (results.has(key)) return results.get(key);
    active.push(key);
    const definition = configuration.get(key);
    const { text, literals } = definition.value;
    let value = '', failed = false;
    for (let index = 0; index < text.length;) {
      if (text[index] !== '$' || literals.has(index) || text[index + 1] !== '{') {
        value += text[index++];
        continue;
      }
      const end = text.indexOf('}', index + 2);
      const name = end < 0 ? '' : text.slice(index + 2, end);
      if (end < 0 || name.includes('\n') || !REFERENCE.test(name)) {
        report(definition.origin, 'E_BAD_REF', `${key}: invalid reference`);
        failed = true;
        break;
      }
      const target = name.includes('.') ? name : `${splitKey(key)[0]}.${name}`;
      if (!configuration.has(target)) {
        report(definition.origin, 'E_UNDEFINED', `${key}: undefined reference ${target}`);
        failed = true;
        break;
      }
      let replacement;
      const start = active.indexOf(target);
      if (start >= 0) {
        const path = [...active.slice(start), target];
        for (const member of path) cycleKeys.add(member);
        report(configuration.get(target).origin, 'E_CYCLE', `interpolation cycle ${path.join(' -> ')}`);
        replacement = null;
      } else {
        replacement = expand(target);
      }
      if (replacement === null) {
        if (!cycleKeys.has(key)) report(definition.origin, 'E_DEPENDENCY', `${key}: depends on failed key ${target}`);
        failed = true;
        break;
      }
      value += replacement;
      index = end + 1;
    }
    active.pop();
    results.set(key, failed ? null : value);
    return results.get(key);
  }
  for (const key of [...configuration.keys()].sort(compareKeys)) expand(key);
  return results;
}

module.exports = { expandAll };
