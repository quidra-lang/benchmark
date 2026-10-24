const students = [{name: "Tanaka", scores: [78, 85, 94]}, {name: "Suzuki", scores: [88, 74, 82]}, {name: "Yamada", scores: [65, 90, 71]}, {name: "Ito", scores: [80, 79, 85]}, {name: "Kato", scores: [92, 88, 95]}, {name: "Mori", scores: [70, 62, 78]}];
const records = students.map(({name, scores}) => ({name, total: scores.reduce((sum, n) => sum + n, 0)}));
records.sort((a, b) => b.total - a.total || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
let rank = 0;
records.forEach(({name, total}, i) => {
  if (i === 0 || total !== records[i - 1].total) rank = i + 1;
  console.log(`${rank}. ${name} total=${total} average=${(total / 3).toFixed(2)}`);
});
