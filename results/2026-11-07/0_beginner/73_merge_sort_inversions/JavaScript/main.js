const values = [47, 12, 85, 33, 6, 71, 29, 58, 90, 14];
let inversions = 0;

function mergeSort(left, right) {
  if (left === right) return;
  const middle = Math.floor((left + right) / 2);
  mergeSort(left, middle);
  mergeSort(middle + 1, right);
  const a = values.slice(left, middle + 1), b = values.slice(middle + 1, right + 1);
  let i = 0, j = 0;
  const merged = [];
  while (i < a.length && j < b.length) {
    if (a[i] < b[j]) {
      merged.push(a[i]);
      i++;
    } else {
      merged.push(b[j]);
      j++;
      inversions += a.length - i;
    }
  }
  merged.push(...a.slice(i), ...b.slice(j));
  values.splice(left, right - left + 1, ...merged);
  console.log(`merge [${left}..${right}]: ${merged.join(" ")}`);
}

mergeSort(0, values.length - 1);
console.log(`sorted: ${values.join(" ")}`);
console.log(`inversions: ${inversions}`);
