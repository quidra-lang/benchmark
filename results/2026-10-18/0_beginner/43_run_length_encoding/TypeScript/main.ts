const strings = ["AAABBBCCCD", "WWWWWWWWWWWWBWWWWWWWWWWWWBBB", "ALGORITHM", "MISSISSIPPI", "XXXXXXXXXXYYYYYYYYYYYYYYYYYYYYYZ"];
for (const text of strings) {
  const encoded = text.match(/(.)\1*/g)!.map(run => `${run.length}${run[0]}`).join("");
  const decoded = encoded.replace(/(\d+)([A-Z])/g, (_, count, char) => char.repeat(Number(count)));
  console.log(`${text} -> ${encoded} -> ${decoded}`);
}
