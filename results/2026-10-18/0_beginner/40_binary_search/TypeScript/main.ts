const values = [3, 8, 11, 15, 19, 24, 27, 31, 36, 42, 47, 53, 58, 64, 70, 77];
for (const target of [42, 3, 77, 31, 50, 1]) {
  let lo = 0, hi = values.length - 1, found = -1;
  const probes = [];
  while (lo <= hi) {
    const mid = Math.floor((lo + hi) / 2);
    probes.push(mid);
    if (values[mid] === target) { found = mid; break; }
    if (values[mid] < target) lo = mid + 1;
    else hi = mid - 1;
  }
  const result = found >= 0 ? `index ${found}` : "not found";
  console.log(`${target}: probes ${probes.join(" ")} -> ${result}`);
}
