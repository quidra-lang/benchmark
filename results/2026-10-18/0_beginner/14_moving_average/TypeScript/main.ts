const sales = [120, 135, 98, 143, 160, 152, 171, 149, 188, 176];
for (let day = 3; day <= sales.length; day++) {
  const average = sales.slice(day - 3, day).reduce((sum, n) => sum + n, 0) / 3;
  console.log(`day ${day}: ${average.toFixed(2)}`);
}
