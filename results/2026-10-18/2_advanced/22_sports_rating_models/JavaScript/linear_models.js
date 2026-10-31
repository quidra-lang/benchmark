function cholesky(matrix, right) {
  const count = right.length;
  const lower = Array.from({ length: count }, () => Array(count).fill(0));
  for (let row = 0; row < count; row += 1) {
    for (let column = 0; column <= row; column += 1) {
      let sum = 0;
      for (let k = 0; k < column; k += 1) sum += lower[row][k] * lower[column][k];
      lower[row][column] = row === column
        ? Math.sqrt(matrix[row][column] - sum)
        : (matrix[row][column] - sum) / lower[column][column];
    }
  }
  const intermediate = Array(count);
  for (let row = 0; row < count; row += 1) {
    let sum = 0;
    for (let k = 0; k < row; k += 1) sum += lower[row][k] * intermediate[k];
    intermediate[row] = (right[row] - sum) / lower[row][row];
  }
  const values = Array(count);
  for (let row = count - 1; row >= 0; row -= 1) {
    let sum = 0;
    for (let k = row + 1; k < count; k += 1) sum += lower[k][row] * values[k];
    values[row] = (intermediate[row] - sum) / lower[row][row];
  }
  return values;
}

function fitColley(count, matches) {
  const matrix = Array.from({ length: count }, (_, row) =>
    Array.from({ length: count }, (_, column) => row === column ? 2 : 0));
  const right = Array(count).fill(1);
  for (const match of matches) {
    const { home, away, result } = match;
    matrix[home][home] += 1;
    matrix[away][away] += 1;
    matrix[home][away] -= 1;
    matrix[away][home] -= 1;
    right[home] += result - 0.5;
    right[away] += 0.5 - result;
  }
  return cholesky(matrix, right);
}

function eliminate(matrix, right) {
  const count = right.length;
  for (let column = 0; column < count; column += 1) {
    let pivot = column;
    for (let row = column + 1; row < count; row += 1) {
      if (Math.abs(matrix[row][column]) > Math.abs(matrix[pivot][column])) pivot = row;
    }
    [matrix[column], matrix[pivot]] = [matrix[pivot], matrix[column]];
    [right[column], right[pivot]] = [right[pivot], right[column]];
    for (let row = column + 1; row < count; row += 1) {
      const scale = matrix[row][column] / matrix[column][column];
      for (let k = column; k < count; k += 1) matrix[row][k] -= scale * matrix[column][k];
      right[row] -= scale * right[column];
    }
  }
  const values = Array(count);
  for (let row = count - 1; row >= 0; row -= 1) {
    let sum = 0;
    for (let column = row + 1; column < count; column += 1) sum += matrix[row][column] * values[column];
    values[row] = (right[row] - sum) / matrix[row][row];
  }
  return values;
}

function fitMassey(count, matches) {
  const size = count + 1;
  const matrix = Array.from({ length: size }, () => Array(size).fill(0));
  const right = Array(size).fill(0);
  for (const match of matches) {
    const { home, away } = match;
    const margin = match.homeScore - match.awayScore;
    matrix[home][home] += 1;
    matrix[away][away] += 1;
    matrix[home][away] -= 1;
    matrix[away][home] -= 1;
    matrix[home][count] += 1;
    matrix[count][home] += 1;
    matrix[away][count] -= 1;
    matrix[count][away] -= 1;
    matrix[count][count] += 1;
    right[home] += margin;
    right[away] -= margin;
    right[count] += margin;
  }
  for (let column = 0; column < count; column += 1) matrix[count - 1][column] = 1;
  matrix[count - 1][count] = 0;
  right[count - 1] = 0;
  const solution = eliminate(matrix, right);
  return { values: solution.slice(0, count), home: solution[count] };
}

module.exports = { fitColley, fitMassey };
