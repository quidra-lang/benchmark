const text = "The cat sat on the mat. The dog sat on the rug, and the cat watched the dog. A bird sang on the fence, and the Dog barked at the bird. The cat slept in the sun, the bird flew away, and the dog sat by the door.";
const counts = new Map();
for (const word of text.toLowerCase().match(/[a-z]+/g)) counts.set(word, (counts.get(word) ?? 0) + 1);
const ordered = [...counts.keys()].sort((a, b) => counts.get(b) - counts.get(a) || (a < b ? -1 : a > b ? 1 : 0));
for (const word of ordered.slice(0, 5)) console.log(`${word}: ${counts.get(word)}`);
console.log(`distinct words: ${counts.size}`);
