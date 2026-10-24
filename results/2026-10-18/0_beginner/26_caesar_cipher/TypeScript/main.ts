function caesar(text: string, shift: number): string {
  return text.replace(/[A-Za-z]/g, char => {
    const base = char <= "Z" ? 65 : 97;
    return String.fromCharCode(base + (char.charCodeAt(0) - base + shift + 26) % 26);
  });
}
const message = "Zoe, meet Max by the Old Bridge at six!";
const encrypted = caesar(message, 3);
console.log(encrypted);
console.log(caesar(encrypted, -3));
