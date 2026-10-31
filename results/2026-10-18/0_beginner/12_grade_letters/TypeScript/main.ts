const scores = [78, 90, 100, 59, 80, 85, 89, 70, 45, 93];
const counts = new Map(["A", "B", "C", "D", "F"].map(grade => [grade, 0]));
for (const score of scores) {
  const grade = score >= 90 ? "A" : score >= 80 ? "B" : score >= 70 ? "C" : score >= 60 ? "D" : "F";
  counts.set(grade, counts.get(grade)! + 1);
  console.log(`${score}: ${grade}`);
}
for (const [grade, count] of counts) console.log(`${grade}: ${count}`);
