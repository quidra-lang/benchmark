#include "linker.hpp"
const std::array<std::string, 7> relocation_types = {"ABS32", "REL32",   "ABS16", "HI16",
                                                     "LO16",  "GPREL16", "CALL24"};
int relocation_width(const std::string &kind) {
    if (kind == "ABS32" || kind == "REL32")
        return 4;
    return kind == "CALL24" ? 3 : 2;
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
RelocationField relocation_field(const std::string &kind, int64_t s, int64_t a, int64_t p,
                                 int64_t gp) {
    RelocationField result{s + a, 0, true};
    if (kind == "REL32" || kind == "CALL24")
        result.value -= p;
    else if (kind == "GPREL16")
        result.value -= gp;
    int64_t v = result.value;
    if (kind == "ABS32" || kind == "HI16")
        result.valid = v >= -(int64_t(1) << 31) && v < (int64_t(1) << 32);
    else if (kind == "REL32")
        result.valid = v >= -(int64_t(1) << 31) && v < (int64_t(1) << 31);
    else if (kind == "ABS16")
        result.valid = v >= -32768 && v < 65536;
    else if (kind == "GPREL16")
        result.valid = v >= -32768 && v < 32768;
    else if (kind == "CALL24")
        result.valid = v >= -(int64_t(1) << 25) && v < (int64_t(1) << 25);
    if (kind == "ABS32" || kind == "REL32")
        result.field = modulo(v, int64_t(1) << 32);
    else if (kind == "HI16")
        result.field = modulo((modulo(v, int64_t(1) << 32) + 32768) / 65536, 65536);
    else if (kind == "CALL24")
        result.field = modulo(floor_divide(v, 4), int64_t(1) << 24);
    else
        result.field = modulo(v, 65536);
    return result;
}
bool unpaired(const std::vector<std::unique_ptr<Relocation>> &relocations, size_t index) {
    const Relocation &current = *relocations[index];
    if (current.type != "HI16")
        return false;
    if (index + 1 == relocations.size())
        return true;
    const Relocation &next = *relocations[index + 1];
    return next.type != "LO16" || next.symbol != current.symbol || next.addend != current.addend;
}
void little_endian(std::vector<uint8_t> &data, size_t offset, int64_t value, int width) {
    for (int i = 0; i < width; ++i)
        data[offset + i] = static_cast<uint8_t>((value >> (8 * i)) & 255);
}
