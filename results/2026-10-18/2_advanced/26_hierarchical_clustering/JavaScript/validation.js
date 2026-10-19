function correlation(first, second) {
  let firstTotal = 0;
  let secondTotal = 0;
  for (let index = 0; index < first.length; index += 1) {
    firstTotal += first[index];
    secondTotal += second[index];
  }
  const firstMean = firstTotal / first.length;
  const secondMean = secondTotal / second.length;
  let cross = 0;
  let firstSquared = 0;
  let secondSquared = 0;
  for (let index = 0; index < first.length; index += 1) {
    const a = first[index] - firstMean;
    const b = second[index] - secondMean;
    cross += a * b;
    firstSquared += a * a;
    secondSquared += b * b;
  }
  return cross / Math.sqrt(firstSquared * secondSquared);
}

function contingency(first, second, rows = Math.max(...first) + 1, columns = Math.max(...second) + 1) {
  const table = Array.from({ length: rows }, () => Array(columns).fill(0));
  for (let index = 0; index < first.length; index += 1) table[first[index]][second[index]] += 1;
  return table;
}

function adjustedRand(first, second) {
  const table = contingency(first, second);
  const chooseTwo = value => value * (value - 1) / 2;
  const columns = table[0].map(() => 0);
  let cells = 0;
  let rows = 0;
  for (const row of table) {
    let total = 0;
    row.forEach((value, column) => {
      cells += chooseTwo(value);
      total += value;
      columns[column] += value;
    });
    rows += chooseTwo(total);
  }
  let columnPairs = 0;
  for (const total of columns) columnPairs += chooseTwo(total);
  const pairs = chooseTwo(first.length);
  let numerator = 2 * (pairs * cells - rows * columnPairs);
  let denominator = pairs * (rows + columnPairs) - 2 * rows * columnPairs;
  if (denominator === 0) return [1, 1];
  if (denominator < 0) {
    numerator = -numerator;
    denominator = -denominator;
  }
  let a = Math.abs(numerator);
  let b = denominator;
  while (b !== 0) [a, b] = [b, a % b];
  return [numerator / a, denominator / a];
}

function silhouettes(matrix, partition) {
  const count = Math.max(...partition) + 1;
  if (count === 1) return null;
  const groups = Array.from({ length: count }, () => []);
  partition.forEach((cluster, observation) => groups[cluster].push(observation));
  return partition.map((cluster, observation) => {
    if (groups[cluster].length === 1) return 0;
    let within = 0;
    for (const other of groups[cluster]) if (other !== observation) within += matrix[observation][other];
    const a = within / (groups[cluster].length - 1);
    let b = null;
    for (let other = 0; other < count; other += 1) {
      if (other === cluster) continue;
      let total = 0;
      for (const member of groups[other]) total += matrix[observation][member];
      const mean = total / groups[other].length;
      if (b === null || mean < b) b = mean;
    }
    return (b - a) / Math.max(a, b);
  });
}

module.exports = { correlation, contingency, adjustedRand, silhouettes };
