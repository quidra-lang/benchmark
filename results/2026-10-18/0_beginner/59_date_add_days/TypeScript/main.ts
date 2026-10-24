const formatDate = (year: number, month: number, day: number): string => [String(year).padStart(4, "0"), String(month).padStart(2, "0"), String(day).padStart(2, "0")].join("-");
const cases = [[1999, 12, 25, 10], [2000, 2, 27, 3], [2021, 2, 20, 14], [2023, 11, 15, 120], [2026, 10, 17, 1500]];
for (const [initialYear, initialMonth, initialDay, added] of cases) {
  let year = initialYear, month = initialMonth, day = initialDay;
  const original = formatDate(year, month, day);
  for (let i = 0; i < added; i++) {
    const leap = year % 400 === 0 || (year % 4 === 0 && year % 100 !== 0);
    const lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    day++;
    if (day > lengths[month - 1]) {
      day = 1;
      month++;
      if (month > 12) {
        month = 1;
        year++;
      }
    }
  }
  console.log(`${original} + ${added} days = ${formatDate(year, month, day)}`);
}
