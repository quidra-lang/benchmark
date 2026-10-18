const words = "we planted beans and carrots in the garden behind our old house".split(" ");
const longest = words.reduce((best, word) => word.length > best.length ? word : best);
const shortest = words.reduce((best, word) => word.length < best.length ? word : best);
const average = words.reduce((sum, word) => sum + word.length, 0) / words.length;
console.log(`words: ${words.length}`);
console.log(`longest: ${longest}`);
console.log(`shortest: ${shortest}`);
console.log(`average length: ${average.toFixed(2)}`);
