#include "linker.h"
const char *relocation_types[7] = {"ABS32", "REL32", "ABS16", "HI16", "LO16", "GPREL16", "CALL24"};
int relocation_width(const char *kind) {
    if (equal(kind, "ABS32") || equal(kind, "REL32"))
        return 4;
    return equal(kind, "CALL24") ? 3 : 2;
}
int64_t modulo(int64_t value, int64_t divisor) {
    int64_t result = value % divisor;
    return result < 0 ? result + divisor : result;
}
int64_t floor_divide(int64_t value, int64_t divisor) {
    int64_t quotient = value / divisor;
    if (value < 0 && value % divisor)
        --quotient;
    return quotient;
}
RelocationField relocation_field(const char *kind, int64_t s, int64_t a, int64_t p, int64_t gp) {
    RelocationField result = {s + a, 0, true};
    if (equal(kind, "REL32") || equal(kind, "CALL24"))
        result.value -= p;
    else if (equal(kind, "GPREL16"))
        result.value -= gp;
    int64_t v = result.value;
    if (equal(kind, "ABS32") || equal(kind, "HI16"))
        result.valid = v >= -(INT64_C(1) << 31) && v < (INT64_C(1) << 32);
    else if (equal(kind, "REL32"))
        result.valid = v >= -(INT64_C(1) << 31) && v < (INT64_C(1) << 31);
    else if (equal(kind, "ABS16"))
        result.valid = v >= -32768 && v < 65536;
    else if (equal(kind, "GPREL16"))
        result.valid = v >= -32768 && v < 32768;
    else if (equal(kind, "CALL24"))
        result.valid = v >= -(INT64_C(1) << 25) && v < (INT64_C(1) << 25);
    if (equal(kind, "ABS32") || equal(kind, "REL32"))
        result.field = modulo(v, INT64_C(1) << 32);
    else if (equal(kind, "HI16"))
        result.field = modulo((modulo(v, INT64_C(1) << 32) + 32768) / 65536, 65536);
    else if (equal(kind, "CALL24"))
        result.field = modulo(floor_divide(v, 4), INT64_C(1) << 24);
    else
        result.field = modulo(v, 65536);
    return result;
}
bool unpaired(RelocationList relocations, int index) {
    Relocation *current = relocations.items[index];
    if (!equal(current->type, "HI16"))
        return false;
    if (index + 1 == relocations.count)
        return true;
    Relocation *next = relocations.items[index + 1];
    return !equal(next->type, "LO16") || next->symbol != current->symbol ||
           next->addend != current->addend;
}
void little_endian(Bytes data, int offset, int64_t value, int width) {
    for (int i = 0; i < width; ++i)
        data.items[offset + i] = (uint8_t)((value >> (8 * i)) & 255);
}
