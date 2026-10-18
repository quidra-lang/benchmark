String caesar(String text, int amount) => String.fromCharCodes(text.codeUnits.map((c) {
    final base = c >= 97 && c <= 122 ? 97 : c >= 65 && c <= 90 ? 65 : -1;
    return base < 0 ? c : base + (c - base + amount) % 26;
}));
void main() {
    const message = 'Zoe, meet Max by the Old Bridge at six!';
    final cipher = caesar(message, 3);
    final plain = caesar(cipher, 23);
    print(cipher);
    print(plain);
}
