#include "crossword.hpp"
#include <iomanip>

std::string decimal(Integer numerator, Integer denominator, int places) {
    Integer scale = 1;
    for (int i = 0; i < places; ++i) scale *= 10;
    Integer rounded = (2 * numerator * scale + denominator) / (2 * denominator);
    std::ostringstream stream;
    stream << rounded / scale << '.' << std::setw(places) << std::setfill('0') << rounded % scale;
    return stream.str();
}
Lines gridLines(const Grid& grid, const std::string& letters) { Lines lines; for (int row = 0; row < grid.height; ++row) lines.push_back(letters.substr(static_cast<std::size_t>(row * grid.width), grid.width)); return lines; }
Lines numberLines(const Layout& layout) {
    Lines lines;
    for (int row = 0; row < layout.grid.height; ++row) {
        Lines marks;
        for (int column = 0; column < layout.grid.width; ++column) {
            int cell = layout.grid.cell(row, column), number = layout.numbers[cell];
            marks.push_back(!layout.grid.isOpen(row, column) ? "##" : number ? (number < 10 ? " " : "") + text(number) : " .");
        }
        lines.push_back(join(marks));
    }
    return lines;
}
std::string listLine(const Slot& slot, const std::string& clue, const std::string& entry, const std::string& score, bool theme) { return text(slot.number, ". ", clue, " (", slot.length(), ") ", entry, ' ', score, theme ? " theme" : ""); }
