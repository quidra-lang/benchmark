const years = [1900, 1988, 2000, 2019, 2024, 2026, 2032, 2100];
for (const year of years) {
  const leap = year % 400 === 0 || (year % 4 === 0 && year % 100 !== 0);
  console.log(`${year}: ${leap ? "leap year" : "common year"}`);
}
