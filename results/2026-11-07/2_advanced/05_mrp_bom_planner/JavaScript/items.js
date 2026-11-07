const fs = require('node:fs');

function readLines(path) {
  const text = fs.readFileSync(path, 'ascii');
  return text === '' ? [] : text.slice(0, -1).split('\n');
}

function csvRows(path) {
  return readLines(path).slice(1).map((text, index) => ({ line: index + 2, fields: text.split(',') }));
}

function compareIds(first, second) {
  return first < second ? -1 : first > second ? 1 : 0;
}

function lotParameters(rule, text) {
  const parts = text.split('/');
  if (!parts.every(part => /^[0-9]+$/.test(part))) return null;
  const values = parts.map(Number);
  if (rule === 'LFL' && values.length === 1 && values[0] === 0) return {};
  if (rule === 'FOQ' && values.length === 1 && values[0] >= 1) return { fixed: values[0] };
  if (rule === 'POQ' && values.length === 1 && values[0] >= 1) return { periods: values[0] };
  if (rule === 'MIN' && values.length === 2 && values.every(value => value >= 1)) {
    return { minimum: values[0], multiple: values[1] };
  }
  return null;
}

function loadItems(path, errors) {
  const items = new Map();
  for (const { line, fields } of csvRows(path)) {
    const [id, leadTime, rule, lotParameter, safety, onHand, material, labor, description] = fields;
    let error = null;
    let parameters = null;
    if (items.has(id)) {
      error = `duplicate item ${id}`;
    } else if (!['LFL', 'FOQ', 'POQ', 'MIN'].includes(rule)) {
      error = `unknown lot rule ${rule}`;
    } else {
      parameters = lotParameters(rule, lotParameter);
      if (parameters === null) error = `bad lot parameter ${lotParameter} for ${rule}`;
    }
    if (error !== null) {
      errors.push(`items.csv line ${line}: ${error}`);
      continue;
    }
    items.set(id, {
      id, line, leadTime: Number(leadTime), rule, ...parameters,
      safety: Number(safety), onHand: Number(onHand), material: Number(material),
      labor: Number(labor), description, children: [], parents: [], routing: [], receipts: [],
    });
  }
  return items;
}

module.exports = { readLines, csvRows, compareIds, lotParameters, loadItems };
