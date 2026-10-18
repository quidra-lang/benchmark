const values = [7, 98000, 4096, 50301, 2718281, 123456789];
for (const value of values) {
  const digits = String(value).split("");
  const digitSum = digits.reduce((sum, digit) => sum + Number(digit), 0);
  const reversed = Number(digits.slice().reverse().join(""));
  console.log(`${value}: digits=${digits.length} sum=${digitSum} reversed=${reversed}`);
}
