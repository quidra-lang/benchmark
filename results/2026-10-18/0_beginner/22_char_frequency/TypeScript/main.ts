const sentence = "Peter Piper picked a peck of pickled peppers!";
const counts = new Map<string, number>();
for (const letter of sentence.toLowerCase()) {
  if (letter >= "a" && letter <= "z") counts.set(letter, (counts.get(letter) ?? 0) + 1);
}
for (const letter of [...counts.keys()].sort()) console.log(`${letter}: ${counts.get(letter)}`);
