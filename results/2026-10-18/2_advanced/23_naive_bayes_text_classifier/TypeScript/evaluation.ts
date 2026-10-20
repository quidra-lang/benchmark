export function real(value: number): string { const text = value.toFixed(4); return +text === 0 ? '0.0000' : text; }
export function rounded(value: number): number { return +real(value); }
export function proportion(n: number, d: number): string { return `${n}/${d} ${real(n / d)}`; }
export function metric(n: number, d: number): string {
  if (!d) return '- -';
  let a = n, b = d;
  while (b) [a, b] = [b, a % b];
  return `${n / a}/${d / a} ${real(n / d)}`;
}
export function evaluate(actual: number[], predicted: number[], k: number) {
  const matrix: number[][] = Array.from({ length: k }, () => Array(k).fill(0));
  for (let i = 0; i < actual.length; i++) matrix[actual[i]][predicted[i]]++;
  let correct = 0, macroTotal = 0, defined = 0;
  const details = matrix.map((row, c) => {
    const truePositive = row[c]; let support = 0, predictedCount = 0;
    for (let other = 0; other < k; other++) { support += row[other]; predictedCount += matrix[other][c]; }
    correct += truePositive;
    if (support + predictedCount > 0) { macroTotal += 2 * truePositive / (predictedCount + support); defined++; }
    return { truePositive, support, predictedCount };
  });
  return { matrix, details, correct, micro: correct / actual.length, macro: macroTotal / defined };
}
export type Evaluation = ReturnType<typeof evaluate>;
export function evaluationLines(result: Evaluation, classes: string[]): string[] {
  return ['true\\predicted ' + classes.join(' '), ...classes.map((c, i) => c + ' ' + result.matrix[i].join(' ')),
    ...classes.map((c, i) => { const d = result.details[i]; return `class ${c} precision ${metric(d.truePositive, d.predictedCount)} recall ${metric(d.truePositive, d.support)} f1 ${metric(2 * d.truePositive, d.predictedCount + d.support)} support ${d.support}`; }),
    `micro_f1 ${real(result.micro)} macro_f1 ${real(result.macro)}`];
}
