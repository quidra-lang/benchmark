const values = [12, 5, 12, 8, 3, 5, 20, 8, 8, 15, 3, 7, 20, 12, 9];
const unique = [...new Set(values)];
console.log(unique.join(" "));
console.log(`removed: ${values.length - unique.length}`);
