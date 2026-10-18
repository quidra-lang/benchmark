const paragraph =
  "Good software is written for people first and for machines second. " +
  "A clear program explains its purpose through careful names, small functions and honest tests. " +
  "When a team agrees on shared rules for internationalization, documentation and code review, " +
  "every newcomer can read the code quickly, change it safely and ship new improvements " +
  "with confidence instead of fear, week after week.";
const width = 30, lines = [];
let line = [], letters = 0;
for (const word of paragraph.split(" ")) {
  if (line.length > 0 && letters + line.length + word.length > width) {
    lines.push(line);
    line = [];
    letters = 0;
  }
  line.push(word);
  letters += word.length;
}
lines.push(line);
lines.forEach((words, index) => {
  let text;
  if (index === lines.length - 1 || words.length === 1) text = words.join(" ").padEnd(width, " ");
  else {
    const spaces = width - words.reduce((sum, word) => sum + word.length, 0);
    const gaps = words.length - 1, base = Math.floor(spaces / gaps), extra = spaces % gaps;
    text = words[0];
    for (let gap = 0; gap < gaps; gap++) text += " ".repeat(base + (gap < extra ? 1 : 0)) + words[gap + 1];
  }
  console.log(`|${text}|`);
});
