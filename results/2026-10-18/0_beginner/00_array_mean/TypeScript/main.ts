const values = [48, 73, 56, 91, 35, 62, 84];
const mean = values.reduce((sum, value) => sum + value, 0) / values.length;
console.log(mean.toFixed(2));
