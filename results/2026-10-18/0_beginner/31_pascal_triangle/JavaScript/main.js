let row = [1];
for (let n = 0; n < 12; n++) {
  console.log(row.join(" "));
  row = [1, ...row.slice(1).map((value, i) => row[i] + value), 1];
}
