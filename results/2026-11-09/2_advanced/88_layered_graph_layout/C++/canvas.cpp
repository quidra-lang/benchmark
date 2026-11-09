#include "layout.hpp"
Canvas::Canvas(int mainLength, int secondaryLength, Direction direction)
    : mainLength(mainLength), secondaryLength(secondaryLength),
      rows(vertical(direction) ? mainLength : secondaryLength),
      columns(vertical(direction) ? secondaryLength : mainLength), direction(direction),
      cells(static_cast<std::size_t>(rows) * columns) {}
Cell Canvas::map(int main, int secondary) const {
    if (direction == Direction::BT || direction == Direction::RL)
        main = mainLength - 1 - main;
    return vertical(direction) ? Cell{main, secondary} : Cell{secondary, main};
}
Pixel &Canvas::at(Cell cell) {
    return cells[static_cast<std::size_t>(cell.row) * columns + cell.column];
}
const Pixel &Canvas::at(Cell cell) const {
    return cells[static_cast<std::size_t>(cell.row) * columns + cell.column];
}
void Canvas::line(int main, int secondary, unsigned char kind) {
    at(map(main, secondary)).lines |= kind;
}
void Canvas::mainLine(int main, int secondary) {
    line(main, secondary, vertical(direction) ? 1 : 2);
}
void Canvas::secondaryLine(int main, int secondary) {
    line(main, secondary, vertical(direction) ? 2 : 1);
}
void Canvas::segment(int start, int gap, int upper, int lower, int offset) {
    if (upper == lower) {
        for (int i = 0; i < gap; ++i)
            mainLine(start + i, upper);
        return;
    }
    for (int i = 0; i < offset; ++i)
        mainLine(start + i, upper);
    line(start + offset, upper, 4);
    line(start + offset, lower, 4);
    for (int x = std::min(upper, lower) + 1; x < std::max(upper, lower); ++x)
        secondaryLine(start + offset, x);
    for (int i = offset + 1; i < gap; ++i)
        mainLine(start + i, lower);
}
void Canvas::highlight(Cell from, Cell to) {
    int dr = (from.row < to.row) - (from.row > to.row),
        dc = (from.column < to.column) - (from.column > to.column);
    for (;;) {
        at(from).highlighted = true;
        if (from.row == to.row && from.column == to.column)
            return;
        from.row += dr;
        from.column += dc;
    }
}
int Canvas::crossingCells() const {
    int count = 0;
    for (const Pixel &pixel : cells)
        if ((pixel.lines & 3) == 3)
            ++count;
    return count;
}
char Canvas::character(Cell cell) const {
    const Pixel &pixel = at(cell);
    if (pixel.box)
        return pixel.box;
    if (pixel.arrow)
        return pixel.arrow;
    if (pixel.highlighted)
        return '#';
    if (!pixel.lines)
        return ' ';
    if (pixel.lines == 1)
        return '|';
    if (pixel.lines == 2)
        return '-';
    return '+';
}
Lines Canvas::drawing(const std::string &name) const {
    std::string ruler = "    ";
    for (int c = 0; c < columns; ++c)
        ruler += static_cast<char>('0' + c % 10);
    Lines out{text("graph ", name, " ", columns, "x", rows), ruler};
    for (int r = 0; r < rows; ++r) {
        std::string number = std::to_string(r), line(3 - number.size(), ' ');
        line += number + " ";
        for (int c = 0; c < columns; ++c)
            line += character({r, c});
        while (!line.empty() && line.back() == ' ')
            line.pop_back();
        out.push_back(std::move(line));
    }
    return out;
}
