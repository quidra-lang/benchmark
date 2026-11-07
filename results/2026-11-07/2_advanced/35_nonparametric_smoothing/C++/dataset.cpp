#include "smoothing.hpp"
static Lines split(const std::string &text, char delimiter) {
    Lines result;
    std::size_t first = 0;
    for (std::size_t i = 0; i <= text.size(); ++i)
        if (i == text.size() || text[i] == delimiter) {
            result.push_back(text.substr(first, i - first));
            first = i + 1;
        }
    return result;
}
static Lines read(const std::string &path) {
    std::ifstream in(path);
    Lines out;
    std::string line;
    while (std::getline(in, line))
        out.push_back(line);
    return out;
}
int hundredths(const std::string &text) {
    std::string digits;
    for (char c : text)
        if (c != '.')
            digits += c;
    return std::stoi(digits);
}
Input read_input() {
    Input out;
    const Lines lines = read("input/series.csv");
    for (std::size_t i = 1; i < lines.size(); ++i) {
        const Lines fields = split(lines[i], ',');
        auto found = std::find_if(out.series.begin(), out.series.end(),
                                  [&](const Series &s) { return s.name == fields[0]; });
        if (found == out.series.end()) {
            out.series.push_back({fields[0], {}});
            found = out.series.end() - 1;
        }
        found->data.x.push_back(hundredths(fields[1]));
        found->data.y.push_back(hundredths(fields[2]));
    }
    for (Series &series : out.series) {
        Data sorted;
        std::vector<std::size_t> order(series.data.x.size());
        std::iota(order.begin(), order.end(), 0);
        std::sort(order.begin(), order.end(),
                  [&](std::size_t a, std::size_t b) { return series.data.x[a] < series.data.x[b]; });
        for (std::size_t i : order) {
            sorted.x.push_back(series.data.x[i]);
            sorted.y.push_back(series.data.y[i]);
            sorted.real_x.push_back(double(series.data.x[i]) / 100);
            sorted.real_y.push_back(double(series.data.y[i]) / 100);
        }
        series.data = std::move(sorted);
    }
    const Lines tests = read("input/test_points.csv");
    for (std::size_t i = 1; i < tests.size(); ++i) {
        const Lines fields = split(tests[i], ',');
        out.tests.push_back({fields[0], hundredths(fields[1])});
    }
    const Lines params = read("input/params.txt");
    for (std::size_t i = 0; i < params.size(); ++i) {
        out.params.rows[i] = split(params[i], ' ');
        out.params.rows[i].erase(out.params.rows[i].begin());
    }
    return out;
}
