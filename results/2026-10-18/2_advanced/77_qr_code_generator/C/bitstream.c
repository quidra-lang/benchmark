#include "qr.h"
const char *alphanumeric = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:";
void word_add(Words *words, int value) { words->items[words->count++] = value; }
char *binary(int value, int width) {
    char *bits = allocate((size_t)width + 1);
    for (int i = 0; i < width; ++i)
        bits[width - 1 - i] = (char)('0' + ((value >> i) & 1));
    return bits;
}
void write_bits(BitWriter *writer, int value, int width) {
    for (int i = width - 1; i >= 0; --i)
        writer->bits[writer->length++] = (char)('0' + ((value >> i) & 1));
    writer->bits[writer->length] = '\0';
}
int remaining(const BitReader *reader) { return reader->length - reader->position; }
int read_bits(BitReader *reader, int width) {
    int value = 0;
    for (int i = 0; i < width; ++i)
        value = value * 2 + reader->bits[reader->position++] - '0';
    return value;
}
char *from_codewords(const Words *words) {
    char *bits = allocate((size_t)words->count * 8 + 1);
    int at = 0;
    for (int i = 0; i < words->count; ++i)
        for (int b = 7; b >= 0; --b)
            bits[at++] = (char)('0' + ((words->items[i] >> b) & 1));
    return bits;
}
Words to_codewords(const char *bits) {
    Words out = {0};
    BitReader reader = {bits, (int)strlen(bits), 0};
    while (remaining(&reader) >= 8)
        word_add(&out, read_bits(&reader, 8));
    return out;
}
char *hexadecimal(const Words *words) {
    const char *digits = "0123456789abcdef";
    char *out = allocate((size_t)words->count * 2 + 1);
    for (int i = 0; i < words->count; ++i) {
        out[2 * i] = digits[words->items[i] >> 4];
        out[2 * i + 1] = digits[words->items[i] & 15];
    }
    return out;
}
