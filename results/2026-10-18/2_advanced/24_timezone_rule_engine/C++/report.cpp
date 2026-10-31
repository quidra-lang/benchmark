#include "timezone.hpp"

std::string localText(Time value) {
    std::array<int, 6> parts = splitTime(value);
    std::ostringstream text;
    text << std::setfill('0') << std::setw(4) << parts[0] << '-' << std::setw(2) << parts[1] << '-' << std::setw(2) << parts[2] << 'T' << std::setw(2) << parts[3] << ':' << std::setw(2) << parts[4] << ':' << std::setw(2) << parts[5];
    return text.str();
}
std::string utText(Time value) { return localText(value) + "Z"; }
std::string offsetText(Time value) {
    char sign = value < 0 ? '-' : '+';
    Time absolute = value < 0 ? -value : value;
    std::ostringstream text;
    text << sign << std::setfill('0') << std::setw(2) << absolute / 3600 << ':' << std::setw(2) << absolute / 60 % 60;
    if (absolute % 60) text << ':' << std::setw(2) << absolute % 60;
    return text.str();
}
std::string durationText(Time value) {
    Time absolute = value < 0 ? -value : value;
    std::ostringstream text;
    if (value < 0) text << '-';
    text << absolute / 3600 << ':' << std::setfill('0') << std::setw(2) << absolute / 60 % 60 << ':' << std::setw(2) << absolute % 60;
    return text.str();
}
std::string clockText(Time value) {
    std::ostringstream text;
    text << value / 3600 << ':' << std::setfill('0') << std::setw(2) << value / 60 % 60;
    if (value % 60) text << ':' << std::setw(2) << value % 60;
    return text.str();
}
std::string stateText(const Period& period) { return offsetText(period.offset) + (period.dst ? " DST " : " STD ") + period.abbreviation; }
std::string changeText(Time value, const Period& before, const Period& after) { return utText(value) + " " + stateText(before) + " -> " + stateText(after); }
void writeLines(const std::string& path, const Lines& lines) {
    std::ofstream output(path, std::ios::binary);
    for (const std::string& line : lines) output << line << '\n';
}
void writeBlocks(const std::string& path, const std::vector<Lines>& blocks) {
    std::ofstream output(path, std::ios::binary);
    for (std::size_t index = 0; index < blocks.size(); ++index) {
        if (index) output << '\n';
        for (const std::string& line : blocks[index]) output << line << '\n';
    }
}
