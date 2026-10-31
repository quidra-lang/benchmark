#include "tides.hpp"
std::string real(double value, int digits) {
    std::ostringstream out;
    out << std::fixed << std::setprecision(digits) << value;
    std::string text = out.str();
    if (text[0] == '-' && text.find_first_not_of("0.", 1) == std::string::npos)
        text.erase(text.begin());
    return text;
}
void save(const std::string &name, const Lines &lines) {
    std::ofstream output("output/" + name);
    for (const std::string &line : lines)
        output << line << '\n';
}
Lines plot_lines(const Vector &heights, const Lines &cells, const std::string &axis) {
    Lines labels, out;
    int width = 0;
    for (double value : heights) {
        labels.push_back(real(value, 2));
        width = std::max(width, int(labels.back().size()));
    }
    for (int i = 0; i < int(labels.size()); ++i)
        out.push_back(std::string(width - labels[i].size(), ' ') + labels[i] + " |" + cells[i] +
                      "|");
    out.push_back(std::string(width, ' ') + " +" + axis + "+");
    return out;
}
