const items = [
  {name: "milk", price: 198, quantity: 2, category: "food"},
  {name: "notebook", price: 165, quantity: 3, category: "general"},
  {name: "bread", price: 248, quantity: 1, category: "food"},
  {name: "apple", price: 128, quantity: 4, category: "food"},
  {name: "detergent", price: 437, quantity: 1, category: "general"},
  {name: "eggs", price: 268, quantity: 1, category: "food"}
];
const totals = new Map([["food", 0], ["general", 0]]);
for (const {name, price, quantity, category} of items) {
  const subtotal = price * quantity;
  totals.set(category, totals.get(category) + subtotal);
  console.log(`${name} ${price} x ${quantity} = ${subtotal}`);
}
let payment = [...totals.values()].reduce((sum, n) => sum + n, 0);
for (const category of ["food", "general"]) {
  const rate = category === "food" ? 8 : 10;
  const tax = Math.floor(totals.get(category) * rate / 100);
  payment += tax;
  console.log(`${category}: ${totals.get(category)} yen, tax ${tax} yen`);
}
console.log(`total: ${payment} yen`);
