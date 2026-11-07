const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
for (const text of ["Man", "Hello, World!", "", "<b>bold</b>", "a+b=c?"]) {
  let encoded = "";
  for (let start = 0; start < text.length; start += 3) {
    const size = Math.min(3, text.length - start);
    const bytes = [0, 0, 0];
    for (let i = 0; i < size; i++) bytes[i] = text.charCodeAt(start + i);
    const value = (bytes[0] << 16) | (bytes[1] << 8) | bytes[2];
    const symbols = [18, 12, 6, 0].map(shift => alphabet[(value >> shift) & 63]).join("");
    encoded += symbols.slice(0, size + 1) + "=".repeat(3 - size);
  }
  console.log(`"${text}" -> "${encoded}"`);
}
