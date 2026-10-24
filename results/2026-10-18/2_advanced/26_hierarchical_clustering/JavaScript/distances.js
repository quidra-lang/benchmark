function prepareVectors(original, standardize) {
  const count = original.length;
  const features = original[0].length;
  const means = Array(features);
  const deviations = Array(features);
  for (let feature = 0; feature < features; feature += 1) {
    let total = 0;
    for (const vector of original) total += vector[feature];
    means[feature] = total / count;
    let squared = 0;
    for (const vector of original) {
      const difference = vector[feature] - means[feature];
      squared += difference * difference;
    }
    deviations[feature] = Math.sqrt(squared / (count - 1));
  }
  const vectors = original.map(vector => vector.map((value, feature) =>
    standardize ? (value - means[feature]) / deviations[feature] : value));
  return { means, deviations, vectors };
}

function squaredDistance(first, second) {
  let total = 0;
  for (let feature = 0; feature < first.length; feature += 1) {
    const difference = first[feature] - second[feature];
    total += difference * difference;
  }
  return total;
}

function distance(first, second, type) {
  if (type === 'euclidean') return Math.sqrt(squaredDistance(first, second));
  if (type === 'manhattan') {
    let total = 0;
    for (let feature = 0; feature < first.length; feature += 1) total += Math.abs(first[feature] - second[feature]);
    return total;
  }
  let firstTotal = 0;
  let secondTotal = 0;
  for (let feature = 0; feature < first.length; feature += 1) {
    firstTotal += first[feature];
    secondTotal += second[feature];
  }
  const firstMean = firstTotal / first.length;
  const secondMean = secondTotal / second.length;
  let cross = 0;
  let firstSquared = 0;
  let secondSquared = 0;
  for (let feature = 0; feature < first.length; feature += 1) {
    const a = first[feature] - firstMean;
    const b = second[feature] - secondMean;
    cross += a * b;
    firstSquared += a * a;
    secondSquared += b * b;
  }
  return 1 - cross / Math.sqrt(firstSquared * secondSquared);
}

function distanceMatrix(vectors, type) {
  const matrix = vectors.map(() => Array(vectors.length).fill(0));
  for (let first = 0; first < vectors.length; first += 1) {
    for (let second = first + 1; second < vectors.length; second += 1) {
      const value = distance(vectors[first], vectors[second], type);
      matrix[first][second] = value;
      matrix[second][first] = value;
    }
  }
  return matrix;
}

module.exports = { prepareVectors, squaredDistance, distance, distanceMatrix };
