const systems = [
  [[2, -1, 3, 7], [4, 1, -2, 3], [-3, 5, 1, -4]],
  [[1, 3, -2, 4, 6], [5, -2, 1, 3, -7], [-2, 4, 6, -1, 9], [3, 1, -4, 2, 5]]
];
systems.forEach((system, number) => {
  const a = system.map(row => [...row]), n = a.length;
  for (let k = 0; k < n; k++) {
    let pivot = k;
    for (let row = k + 1; row < n; row++) {
      if (Math.abs(a[row][k]) > Math.abs(a[pivot][k])) pivot = row;
    }
    [a[k], a[pivot]] = [a[pivot], a[k]];
    for (let i = k + 1; i < n; i++) {
      const factor = a[i][k] / a[k][k];
      for (let j = k; j <= n; j++) a[i][j] = a[i][j] - factor * a[k][j];
    }
  }
  const solution = Array(n).fill(0);
  for (let i = n - 1; i >= 0; i--) {
    let s = a[i][n];
    for (let j = i + 1; j < n; j++) s = s - a[i][j] * solution[j];
    solution[i] = s / a[i][i];
  }
  console.log(`system ${number + 1}:`);
  solution.forEach((value, i) => console.log(`x${i + 1} = ${value.toFixed(4)}`));
});
