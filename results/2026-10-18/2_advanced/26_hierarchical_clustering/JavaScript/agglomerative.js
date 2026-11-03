function coefficients(method, firstSize, secondSize, otherSize) {
  const combined = firstSize + secondSize;
  if (method === 'single') return [0.5, 0.5, 0, -0.5];
  if (method === 'complete') return [0.5, 0.5, 0, 0.5];
  if (method === 'average') return [firstSize / combined, secondSize / combined, 0, 0];
  if (method === 'weighted') return [0.5, 0.5, 0, 0];
  if (method === 'centroid') return [firstSize / combined, secondSize / combined,
    -(firstSize * secondSize) / (combined * combined), 0];
  if (method === 'median') return [0.5, 0.5, -0.25, 0];
  const total = combined + otherSize;
  return [(firstSize + otherSize) / total, (secondSize + otherSize) / total, -otherSize / total, 0];
}

function agglomerate(delta, method) {
  const count = delta.length;
  const square = ['centroid', 'median', 'ward'].includes(method);
  const matrix = Array.from({ length: 2 * count - 1 }, () => Array(2 * count - 1).fill(0));
  for (let first = 0; first < count; first += 1) {
    for (let second = first + 1; second < count; second += 1) {
      const value = square ? delta[first][second] * delta[first][second] : delta[first][second];
      matrix[first][second] = value;
      matrix[second][first] = value;
    }
  }
  const sizes = Array(2 * count - 1).fill(1);
  let active = delta.map((_, index) => index);
  const merges = [];
  for (let step = 0; step < count - 1; step += 1) {
    let a = active[0];
    let b = active[1];
    let smallest = matrix[a][b];
    for (let first = 0; first < active.length; first += 1) {
      for (let second = first + 1; second < active.length; second += 1) {
        const value = matrix[active[first]][active[second]];
        if (value < smallest) {
          a = active[first];
          b = active[second];
          smallest = value;
        }
      }
    }
    const created = count + step;
    sizes[created] = sizes[a] + sizes[b];
    merges.push({ a, b, height: square ? Math.sqrt(smallest) : smallest, size: sizes[created] });
    const remaining = active.filter(cluster => cluster !== a && cluster !== b);
    for (const other of remaining) {
      const [alphaA, alphaB, beta, gamma] = coefficients(method, sizes[a], sizes[b], sizes[other]);
      const first = matrix[a][other];
      const second = matrix[b][other];
      const value = alphaA * first + alphaB * second + beta * smallest + gamma * Math.abs(first - second);
      matrix[other][created] = value;
      matrix[created][other] = value;
    }
    active = [...remaining, created];
  }
  return merges;
}

function minimumSpanningTree(matrix) {
  const included = matrix.map(() => false);
  included[0] = true;
  const keys = matrix[0].slice();
  const parents = matrix.map(() => 0);
  const edges = [];
  for (let step = 0; step < matrix.length - 1; step += 1) {
    let selected = null;
    for (let vertex = 0; vertex < matrix.length; vertex += 1) {
      if (!included[vertex] && (selected === null || keys[vertex] < keys[selected])) selected = vertex;
    }
    included[selected] = true;
    edges.push({ a: parents[selected], b: selected, weight: keys[selected], number: step + 1 });
    for (let vertex = 0; vertex < matrix.length; vertex += 1) {
      if (!included[vertex] && matrix[selected][vertex] < keys[vertex]) {
        keys[vertex] = matrix[selected][vertex];
        parents[vertex] = selected;
      }
    }
  }
  return edges;
}

module.exports = { coefficients, agglomerate, minimumSpanningTree };
