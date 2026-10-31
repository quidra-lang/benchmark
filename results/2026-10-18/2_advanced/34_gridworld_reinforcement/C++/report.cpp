#include "reinforcement.hpp"
Lines read_lines(const std::string &path) {
    std::ifstream in(path);
    Lines result;
    std::string line;
    while (std::getline(in, line))
        result.push_back(line);
    return result;
}
std::string number(Integer value) {
    return std::to_string(value);
}
std::string join(const Lines &lines, const std::string &separator) {
    std::string result;
    for (std::size_t i = 0; i < lines.size(); ++i) {
        if (i)
            result += separator;
        result += lines[i];
    }
    return result;
}
std::string fixed(Integer value) {
    std::ostringstream out;
    const Integer magnitude = absolute(value);
    out << (value < 0 ? "-" : "") << magnitude / 10000 << '.' << std::setw(4) << std::setfill('0')
        << magnitude % 10000;
    return out.str();
}
std::string average(Integer total, Integer count) {
    return fixed(floor_div(10000 * total, count));
}
std::string cell_text(const World &w, int cell) {
    return number(cell / w.cols) + "," + number(cell % w.cols);
}
std::string cells_text(const World &w, const std::vector<int> &cells) {
    Lines values;
    for (int cell : cells)
        values.push_back(cell_text(w, cell));
    return join(values, " ");
}
Lines grid(const World &w, const Lines &fields, const std::string &separator) {
    Lines result;
    for (int row = 0; row < w.rows; ++row) {
        Lines values;
        for (int col = 0; col < w.cols; ++col) {
            const int cell = row * w.cols + col, state = w.index[cell];
            values.push_back(state < 0 ? std::string(1, w.cells[cell]) : fields[state]);
        }
        result.push_back(join(values, separator));
    }
    return result;
}
Lines value_grid(const World &w, const Values &values) {
    Lines fields;
    for (Integer value : values)
        fields.push_back(fixed(value));
    return grid(w, fields, " ");
}
Lines policy_grid(const World &w, const Policy &policy) {
    Lines fields;
    for (int action : policy)
        fields.push_back(std::string(1, "^>v<"[action]));
    return grid(w, fields, "");
}
Lines q_rows(const World &w, const std::string &name, const Table &q, const Table *visits) {
    Lines result;
    for (std::size_t state = 0; state < q.size(); ++state)
        for (int a = 0; a < 4; ++a)
            result.push_back(name + "," + cell_text(w, w.states[state]) + "," + "NESW"[a] + "," +
                             fixed(q[state][a]) + "," + (visits ? number((*visits)[state][a]) : "-"));
    return result;
}
Lines parts(const std::vector<Lines> &parts_) {
    Lines result;
    for (const Lines &part : parts_) {
        if (!result.empty())
            result.push_back("");
        result.insert(result.end(), part.begin(), part.end());
    }
    return result;
}
void write_lines(const std::string &name, const Lines &lines) {
    std::ofstream out("output/" + name, std::ios::binary);
    for (const std::string &line : lines)
        out << line << '\n';
}
