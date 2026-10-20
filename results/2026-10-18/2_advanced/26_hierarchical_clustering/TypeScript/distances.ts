export type DistanceType = 'euclidean' | 'manhattan' | 'correlation';
export type Matrix = number[][];

export function distanceType(name: string): DistanceType {
  if (name === 'euclidean' || name === 'manhattan' || name === 'correlation') return name;
  throw new Error(`Unknown distance: ${name}`);
}

export function prepareVectors(original: Matrix, standardize: boolean) {
  const count = original.length;
  const means: number[] = [];
  const deviations: number[] = [];
  for (let feature = 0; feature < original[0].length; feature++) {
    let total = 0;
    for (const vector of original) total += vector[feature];
    const mean = total / count;
    means.push(mean);
    let squared = 0;
    for (const vector of original) {
      const difference = vector[feature] - mean;
      squared += difference * difference;
    }
    deviations.push(Math.sqrt(squared / (count - 1)));
  }
  const vectors = original.map(vector => vector.map((value, feature) =>
    standardize ? (value - means[feature]) / deviations[feature] : value));
  return { means, deviations, vectors };
}

export function squaredDistance(first: number[], second: number[]): number {
  let total = 0;
  for (let feature = 0; feature < first.length; feature++) {
    const difference = first[feature] - second[feature];
    total += difference * difference;
  }
  return total;
}

export function distance(first: number[], second: number[], type: DistanceType): number {
  if (type === 'euclidean') return Math.sqrt(squaredDistance(first, second));
  if (type === 'manhattan') {
    let total = 0;
    for (let f = 0; f < first.length; f++) total += Math.abs(first[f] - second[f]);
    return total;
  }
  let firstTotal = 0, secondTotal = 0;
  for (let f = 0; f < first.length; f++) {
    firstTotal += first[f];
    secondTotal += second[f];
  }
  const firstMean = firstTotal / first.length, secondMean = secondTotal / second.length;
  let cross = 0, firstSquared = 0, secondSquared = 0;
  for (let f = 0; f < first.length; f++) {
    const a = first[f] - firstMean, b = second[f] - secondMean;
    cross += a * b;
    firstSquared += a * a;
    secondSquared += b * b;
  }
  return 1 - cross / Math.sqrt(firstSquared * secondSquared);
}

export function distanceMatrix(vectors: Matrix, type: DistanceType): Matrix {
  const matrix = vectors.map(() => Array<number>(vectors.length).fill(0));
  for (let i = 0; i < vectors.length; i++) for (let j = i + 1; j < vectors.length; j++) {
    matrix[i][j] = matrix[j][i] = distance(vectors[i], vectors[j], type);
  }
  return matrix;
}
