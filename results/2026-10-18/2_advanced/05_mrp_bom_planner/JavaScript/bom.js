const { csvRows, compareIds } = require('./items');
const { ceilRatio } = require('./report');

function need(row, quantity) {
  return ceilRatio(quantity * row.quantity * (100 + row.scrap), 100);
}

function cyclePath(items, start, target) {
  const visited = new Set();
  function visit(id) {
    if (id === target) return [id];
    visited.add(id);
    for (const row of items.get(id).children) {
      if (visited.has(row.child)) continue;
      const path = visit(row.child);
      if (path !== null) return [id, ...path];
    }
    return null;
  }
  return visit(start);
}

function loadBom(path, items, errors) {
  for (const { line, fields } of csvRows(path)) {
    const [parent, child, quantityText, scrapText] = fields;
    const quantity = Number(quantityText);
    const scrap = Number(scrapText);
    let error = null;
    if (!items.has(parent)) error = `unknown item ${parent}`;
    else if (!items.has(child)) error = `unknown item ${child}`;
    else if (quantity < 1) error = `bad quantity ${quantity}`;
    else if (scrap > 50) error = `bad scrap ${scrap}`;
    else if (parent === child) error = `cycle ${parent} -> ${parent}`;
    else if (items.get(parent).children.some(row => row.child === child)) {
      error = `duplicate ${parent} -> ${child}`;
    } else {
      const pathToParent = cyclePath(items, child, parent);
      if (pathToParent !== null) error = `cycle ${parent} -> ${pathToParent.join(' -> ')}`;
    }
    if (error !== null) {
      errors.push(`bom.csv line ${line}: ${error}`);
      continue;
    }
    const row = { parent, child, quantity, scrap, line };
    items.get(parent).children.push(row);
    items.get(parent).children.sort((first, second) => compareIds(first.child, second.child));
    items.get(child).parents.push(row);
  }
  for (const item of items.values()) {
    item.parents.sort((first, second) => compareIds(first.parent, second.parent));
  }
}

function computeStructure(items) {
  function lowLevel(item) {
    if (item.lowLevel !== undefined) return item.lowLevel;
    let level = 0;
    for (const row of item.parents) level = Math.max(level, lowLevel(items.get(row.parent)) + 1);
    item.lowLevel = level;
    return level;
  }
  function cumulativeLead(item) {
    if (item.cumulativeLead !== undefined) return item.cumulativeLead;
    let longest = 0;
    for (const row of item.children) longest = Math.max(longest, cumulativeLead(items.get(row.child)));
    item.cumulativeLead = item.leadTime + longest;
    return item.cumulativeLead;
  }
  for (const item of items.values()) {
    lowLevel(item);
    cumulativeLead(item);
  }
  return [...items.values()].sort((first, second) =>
    first.lowLevel - second.lowLevel || compareIds(first.id, second.id));
}

module.exports = { need, loadBom, computeStructure };
