const { csvRows, compareIds } = require('./items');
const { floorRatio } = require('./report');

function loadCenters(path, errors) {
  const centers = new Map();
  for (const { line, fields } of csvRows(path)) {
    const [id, minutesText, efficiencyText, description] = fields;
    const minutes = Number(minutesText);
    const efficiency = Number(efficiencyText);
    let error = null;
    if (centers.has(id)) error = `duplicate center ${id}`;
    else if (efficiency < 50 || efficiency > 150) error = `bad efficiency ${efficiency}`;
    if (error !== null) {
      errors.push(`workcenters.csv line ${line}: ${error}`);
    } else {
      centers.set(id, { id, line, minutes, efficiency, available: floorRatio(minutes * efficiency, 100), description });
    }
  }
  return centers;
}

function loadRoutings(path, items, centers, errors) {
  for (const { line, fields } of csvRows(path)) {
    const [id, operationText, center, setupText, runText] = fields;
    const operation = Number(operationText);
    const setup = Number(setupText);
    const run = Number(runText);
    const item = items.get(id);
    let error = null;
    if (item === undefined) error = `unknown item ${id}`;
    else if (!centers.has(center)) error = `unknown center ${center}`;
    else if (item.children.length === 0) error = `purchased item ${id}`;
    else if (run < 1) error = `bad run time ${run}`;
    else if (item.routing.some(row => row.operation === operation)) error = `duplicate ${id} operation ${operation}`;
    if (error !== null) {
      errors.push(`routings.csv line ${line}: ${error}`);
    } else {
      item.routing.push({ item: id, operation, center, setup, run, line });
    }
  }
  for (const item of items.values()) item.routing.sort((first, second) => first.operation - second.operation);
}

function operationWeek(receipt, leadTime, index, count) {
  return Math.max(1, receipt - leadTime + floorRatio(index * leadTime, count));
}

function levelLoad(load, available) {
  const leveled = Array(load.length).fill(0);
  let carry = 0;
  for (let week = load.length - 1; week >= 2; week -= 1) {
    const quantity = load[week] + carry;
    leveled[week] = Math.min(quantity, available);
    carry = quantity - leveled[week];
  }
  leveled[1] = load[1] + carry;
  return { leveled, backlog: Math.max(0, leveled[1] - available) };
}

function orderedCenters(centers) {
  return [...centers.values()].sort((first, second) => compareIds(first.id, second.id));
}

module.exports = { loadCenters, loadRoutings, operationWeek, levelLoad, orderedCenters };
