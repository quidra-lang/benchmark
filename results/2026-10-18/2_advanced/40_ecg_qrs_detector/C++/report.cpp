#include "ecg.hpp"
Integer floor_div(Integer a, Integer b) {
    Integer quotient = a / b;
    if (a % b < 0)
        --quotient;
    return quotient;
}
Integer rdiv(Integer a, Integer b) {
    return floor_div(2 * a + b, 2 * b);
}
std::string decimal2(Integer value) {
    const Integer magnitude = std::abs(value);
    std::ostringstream out;
    if (value < 0)
        out << '-';
    out << magnitude / 100 << '.' << std::setw(2) << std::setfill('0') << magnitude % 100;
    return out.str();
}
std::string decimal4(Integer value) {
    std::ostringstream out;
    out << value / 10000 << '.' << std::setw(4) << std::setfill('0') << value % 10000;
    return out.str();
}
std::string reduced(Integer a, Integer b) {
    const Integer divisor = std::gcd(a, b);
    return std::to_string(a / divisor) + "/" + std::to_string(b / divisor);
}
std::string ratio(Integer a, Integer b) {
    const std::string prefix = std::to_string(a) + "/" + std::to_string(b);
    return b ? prefix + " reduced=" + reduced(a, b) + " percent=" + decimal2(rdiv(10000 * a, b))
             : prefix + " none";
}
std::string optional_number(bool exists, Integer value) {
    return exists ? std::to_string(value) : "-";
}
