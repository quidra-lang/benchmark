const small = "zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen".split(" ");
const tens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"];
function underThousand(value) {
  const parts = [];
  if (value >= 100) parts.push(small[Math.floor(value / 100)] + " hundred");
  const remainder = value % 100;
  if (remainder >= 20) {
    let word = tens[Math.floor(remainder / 10)];
    if (remainder % 10 !== 0) word += "-" + small[remainder % 10];
    parts.push(word);
  } else if (remainder > 0) parts.push(small[remainder]);
  return parts.join(" ");
}
for (const number of [0, 13, 40, 100, 568, 71000, 300019, 999999]) {
  const parts = [];
  if (number >= 1000) parts.push(underThousand(Math.floor(number / 1000)) + " thousand");
  if (number % 1000 > 0) parts.push(underThousand(number % 1000));
  console.log(`${number}: ${parts.length > 0 ? parts.join(" ") : small[0]}`);
}
