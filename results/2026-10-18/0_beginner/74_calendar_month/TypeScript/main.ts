const names = [
  "January", "February", "March", "April", "May", "June", "July",
  "August", "September", "October", "November", "December"
];
const offsets = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4];
const months = [[2024, 2], [2026, 8], [2026, 11]];
months.forEach(([year, month], index) => {
  if (index > 0) console.log("");
  const adjusted = year - (month < 3 ? 1 : 0);
  const weekday = (adjusted + Math.floor(adjusted / 4) - Math.floor(adjusted / 100) + Math.floor(adjusted / 400) + offsets[month - 1] + 1) % 7;
  const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  console.log(`${names[month - 1]} ${year}`);
  console.log("Su Mo Tu We Th Fr Sa");
  let week = Array(weekday).fill("  ");
  for (let day = 1; day <= lengths[month - 1]; day++) {
    week.push(String(day).padStart(2, " "));
    if (week.length === 7) {
      console.log(week.join(" "));
      week = [];
    }
  }
  if (week.length > 0) console.log(week.join(" "));
});
