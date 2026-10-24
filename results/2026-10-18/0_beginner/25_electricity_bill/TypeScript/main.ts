const households = [{name: "Sato", usage: 85}, {name: "Suzuki", usage: 120}, {name: "Takahashi", usage: 254}, {name: "Tanaka", usage: 300}, {name: "Ito", usage: 438}, {name: "Watanabe", usage: 176}];
let total = 0;
for (const {name, usage} of households) {
  const bill = 900 + Math.min(usage, 120) * 30 + Math.max(0, Math.min(usage, 300) - 120) * 36 + Math.max(0, usage - 300) * 40;
  total += bill;
  console.log(`${name}: ${usage} kWh, ${bill} yen`);
}
console.log(`total: ${total} yen`);
