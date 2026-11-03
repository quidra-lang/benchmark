const days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
const counts = [7, 12, 4, 15, 9, 18, 11];
days.forEach((day, i) => console.log(`${day} | ${"*".repeat(counts[i])} ${counts[i]}`));
