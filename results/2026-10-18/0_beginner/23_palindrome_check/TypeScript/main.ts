const phrases = [
  "Never odd or even", "Race a car", "Was it a car or a cat I saw?", "Hello, World!",
  "Step on no pets.", "No lemon, no melon"
];
for (const phrase of phrases) {
  const letters = phrase.toLowerCase().replace(/[^a-z]/g, "");
  console.log(`${phrase} -> ${letters === letters.split("").reverse().join("") ? "yes" : "no"}`);
}
