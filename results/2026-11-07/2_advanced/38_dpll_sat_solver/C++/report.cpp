#include "sat.hpp"
std::string number(int value) {
    return std::to_string(value);
}
std::string number_list(const std::vector<int> &values) {
    if (values.empty())
        return "-";
    std::string result;
    for (int value : values) {
        if (!result.empty())
            result += ",";
        result += number(value);
    }
    return result;
}
std::string frequency_list(const std::map<int, int> &counts) {
    if (counts.empty())
        return "-";
    std::string result;
    for (const auto &entry : counts) {
        if (!result.empty())
            result += ",";
        result += number(entry.first) + ":" + number(entry.second);
    }
    return result;
}
std::string items(const std::string &prefix, const std::vector<std::pair<std::string, std::string>> &values) {
    std::string result = prefix;
    for (const auto &entry : values) {
        if (!result.empty())
            result += " ";
        result += entry.first + "=" + entry.second;
    }
    return result;
}
Lines board_lines(const std::vector<int> &columns) {
    Lines out;
    for (int column : columns) {
        std::string row(columns.size(), '.');
        row[column - 1] = 'Q';
        out.push_back(row);
    }
    return out;
}
void write_lines(const std::string &name, const Lines &lines) {
    std::ofstream out("output/" + name, std::ios::binary);
    for (const std::string &line : lines)
        out << line << '\n';
}
void write_paragraphs(const std::string &name, const std::vector<Lines> &paragraphs) {
    Lines out;
    for (const Lines &paragraph : paragraphs) {
        if (!out.empty())
            out.push_back("");
        out.insert(out.end(), paragraph.begin(), paragraph.end());
    }
    write_lines(name, out);
}
