function solve(n: number): { count: number; first: number[] } {
  const placement: number[] = [];
  let count = 0;
  let first: number[] = [];
  function visit(): void {
    const row = placement.length;
    if (row === n) {
      count++;
      if (first.length === 0) first = [...placement];
      return;
    }
    for (let column = 0; column < n; column++) {
      const conflict = placement.some((previous, r) => previous === column || Math.abs(previous - column) === row - r);
      if (conflict) continue;
      placement.push(column);
      visit();
      placement.pop();
    }
  }
  visit();
  return {count, first};
}
let firstEight: number[] = [];
for (let n = 4; n <= 8; n++) {
  const {count, first} = solve(n);
  console.log(`N=${n}: ${count} solutions`);
  if (n === 8) firstEight = first;
}
for (const column of firstEight) console.log(".".repeat(column) + "Q" + ".".repeat(7 - column));
