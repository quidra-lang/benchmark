const ranks = "A23456789TJQK";
const deck = [..."SHDC"].flatMap(suit => [...ranks].map(rank => rank + suit));
let state = 2026;
for (let i = deck.length - 1; i >= 1; i--) {
  state = state * 48271 % 2147483647;
  const j = state % (i + 1);
  [deck[i], deck[j]] = [deck[j], deck[i]];
}
for (let start = 0; start < deck.length; start += 13) {
  console.log(deck.slice(start, start + 13).join(" "));
}
