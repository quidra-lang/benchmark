#include "heat.hpp"
#include <filesystem>
std::string real(double value, int digits) {
    std::ostringstream out;
    out << std::fixed << std::setprecision(digits) << value;
    std::string text = out.str();
    if (text[0] == '-' && text.find_first_not_of("0.", 1) == std::string::npos)
        text.erase(text.begin());
    return text;
}
std::string time_text(int milliseconds) {
    std::ostringstream out;
    out << milliseconds / 1000 << '.' << std::setfill('0') << std::setw(3) << milliseconds % 1000;
    return out.str();
}
int hottest(const Field &field) {
    return int(std::max_element(field.begin(), field.end()) - field.begin());
}
std::string summary(const std::string &prefix, const Mesh &mesh, const Field &field) {
    const int p = hottest(field);
    return prefix + " max " + real(field[p], 2) + " at " + mesh.coordinates(p) + " min " +
           real(*std::min_element(field.begin(), field.end()), 2) + " mean " +
           real(std::accumulate(field.begin(), field.end(), 0.0) / mesh.count, 2);
}
void field_lines(Lines &lines, const Mesh &mesh, const Field &field) {
    for (int r = 0; r < mesh.height; ++r) {
        std::string row;
        for (int c = 0; c < mesh.width; ++c) {
            if (c)
                row += ' ';
            row += real(field[mesh.cell(r, c)], 2);
        }
        lines.push_back(row);
    }
}
void isotherms(Lines &lines, const std::string &prefix, const Mesh &mesh, const Field &field,
               const Field &bands) {
    std::vector<int> counts(bands.size() + 1), digits(field.size());
    for (int p = 0; p < mesh.count; ++p) {
        for (double boundary : bands)
            digits[p] += boundary <= field[p];
        ++counts[digits[p]];
    }
    std::string heading = prefix + " counts";
    for (int count : counts)
        heading += " " + std::to_string(count);
    lines.push_back(heading);
    const int peak = hottest(field);
    for (int r = 0; r < mesh.height; ++r) {
        std::string row;
        for (int c = 0; c < mesh.width; ++c) {
            int p = mesh.cell(r, c);
            row += p == peak ? '*' : char('0' + digits[p]);
        }
        lines.push_back(row);
    }
}
void save(const std::string &name, const Lines &lines) {
    std::filesystem::create_directories("output");
    std::ofstream output("output/" + name);
    for (const std::string &line : lines)
        output << line << '\n';
}
