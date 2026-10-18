const words = "we planted beans and carrots in the garden behind our old house".split(" ");
let longest = words[0], shortest = words[0];
for (const word of words) {
  if (word.length > longest.length) longest = word;
  if (word.length < shortest.length) shortest = word;
}
const average = words.reduce((sum, word) => sum + word.length, 0) / words.length;
console.log(`words: ${words.length}`);
console.log(`longest: ${longest}`);
console.log(`shortest: ${shortest}`);
console.log(`average length: ${average.toFixed(2)}`);
