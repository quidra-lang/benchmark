const rows = [
  "date,region,product,quantity,unit_price",
  "2026-04-01,north,notebook,10,200", "2026-04-01,east,marker,6,150",
  "2026-04-01,south,eraser,25,80", "2026-04-02,west,stapler,4,600",
  "2026-04-02,north,marker,8,150", "2026-04-02,east,notebook,9,200",
  "2026-04-03,south,stapler,3,600", "2026-04-03,west,eraser,15,80",
  "2026-04-03,north,eraser,20,80", "2026-04-04,east,stapler,5,600",
  "2026-04-04,south,notebook,6,200", "2026-04-04,west,marker,8,150"
];
const regions = new Map<string, number>(), products = new Map<string, number>(), dates = new Map<string, number>();
let total = 0;
for (const line of rows.slice(1)) {
  const [date, region, product, quantityText, priceText] = line.split(",");
  const quantity = Number(quantityText), sales = quantity * Number(priceText);
  total += sales;
  regions.set(region, (regions.get(region) ?? 0) + sales);
  products.set(product, (products.get(product) ?? 0) + quantity);
  dates.set(date, (dates.get(date) ?? 0) + sales);
}
const alphabetical = (a: string, b: string): number => a < b ? -1 : a > b ? 1 : 0;
const regionOrder = [...regions.keys()].sort((a, b) => regions.get(b)! - regions.get(a)! || alphabetical(a, b));
console.log(`total: ${total}`);
for (const region of regionOrder) console.log(`${region}: ${regions.get(region)}`);
for (const product of [...products.keys()].sort()) console.log(`${product}: ${products.get(product)}`);
const best = [...dates.keys()].sort((a, b) => dates.get(b)! - dates.get(a)! || alphabetical(a, b))[0];
console.log(`best day: ${best} (${dates.get(best)})`);
