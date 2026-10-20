export function strictBase64(text: string): string | undefined {
  if (text.length % 4 !== 0) return undefined;
  const unpadded = text.replace(/=+$/, '');
  if (text.length - unpadded.length > 2 || /[^A-Za-z0-9+/]/.test(unpadded)) return undefined;
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let bits = 0, value = 0, output = '';
  for (const character of unpadded) {
    value = value * 64 + alphabet.indexOf(character); bits += 6;
    if (bits >= 8) {
      bits -= 8;
      output += String.fromCharCode(Math.floor(value / 2 ** bits));
      value %= 2 ** bits;
    }
  }
  return output;
}
export function base64Body(text: string): string | undefined {
  const decoded = strictBase64(text.replace(/[ \t\n]/g, ''));
  if (decoded === undefined) return undefined;
  const normalized = decoded.replace(/\r\n/g, '\n');
  return /[^\t\n\x20-\x7e]/.test(normalized) ? undefined : normalized;
}
export function quotedPrintable(text: string): { text: string; error: boolean } {
  const lines = text.split('\n');
  let output = '', error = false;
  lines.forEach((line, number) => {
    line = line.replace(/[ \t]+$/, '');
    const soft = line.endsWith('=');
    if (soft) line = line.slice(0, -1);
    for (let i = 0; i < line.length; i++) {
      if (line[i] === '=') {
        const hex = line.slice(i + 1, i + 3), value = /^[0-9A-Fa-f]{2}$/.test(hex) ? parseInt(hex, 16) : -1;
        if (value === 9 || (value >= 32 && value <= 126)) { output += String.fromCharCode(value); i += 2; }
        else { output += '='; error = true; }
      } else output += line[i];
    }
    if (!soft && number < lines.length - 1) output += '\n';
  });
  return { text: output, error };
}
