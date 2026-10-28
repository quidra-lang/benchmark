#include "forecasting.hpp"
static std::vector<std::string> split(const std::string &line, char separator) {
    std::istringstream input(line);
    std::string word;
    std::vector<std::string> result;
    while (std::getline(input, word, separator))
        result.push_back(word);
    return result;
}
Input read_input() {
    Input input;
    std::ifstream params("input/params.txt");
    std::string line;
    std::vector<std::vector<std::string>> fields;
    while (std::getline(params, line)) {
        auto words = split(line, ' ');
        fields.emplace_back(words.begin() + 1, words.end());
    }
    Params &p = input.params;
    p.season = std::stoi(fields[0][0]);
    p.holdout = std::stoi(fields[1][0]);
    p.horizon = std::stoi(fields[2][0]);
    p.cv_start = std::stoi(fields[3][0]);
    p.combo = std::stoi(fields[4][0]);
    for (int row = 5; row <= 8; ++row) {
        Vector *values = row == 5 ? &p.alpha : row == 6 ? &p.beta : row == 7 ? &p.gamma : &p.phi;
        for (const std::string &text : fields[row])
            values->push_back(std::stod(text));
    }
    p.max_ar = std::stoi(fields[9][0]);
    p.max_lag = std::stoi(fields[10][0]);
    for (const std::string &text : fields[11])
        p.ljung_box.push_back(std::stoi(text));
    p.outlier = std::stod(fields[12][0]);
    p.z80 = std::stod(fields[13][0]);
    p.z95 = std::stod(fields[13][1]);
    std::ifstream series("input/series.csv");
    std::getline(series, line);
    while (std::getline(series, line)) {
        const auto values = split(line, ',');
        if (input.series.empty() || input.series.back().name != values[0])
            input.series.push_back({values[0]});
        Series &item = input.series.back();
        item.periods.push_back(values[1]);
        item.missing.push_back(values[2] == "NA");
        item.raw.push_back(values[2] == "NA" ? 0 : std::stod(values[2]));
    }
    std::ifstream events("input/events.csv");
    std::getline(events, line);
    while (std::getline(events, line)) {
        const auto values = split(line, ',');
        input.events[{values[0], values[1]}] = values[2];
    }
    std::ifstream inventory("input/inventory.csv");
    std::getline(inventory, line);
    while (std::getline(inventory, line)) {
        const auto values = split(line, ',');
        input.inventory[values[0]] = {std::stoll(values[1]), std::stoi(values[2]), std::stoi(values[3]),
                                      std::stod(values[4])};
    }
    return input;
}
std::string next_month(const std::string &period) {
    int year = std::stoi(period.substr(0, 4)), month = std::stoi(period.substr(5, 2));
    if (++month == 13) {
        month = 1;
        ++year;
    }
    std::ostringstream text;
    text << std::setw(4) << std::setfill('0') << year << '-' << std::setw(2) << month;
    return text.str();
}
std::string real(double value) {
    std::ostringstream text;
    text << std::fixed << std::setprecision(4) << value;
    return text.str() == "-0.0000" ? "0.0000" : text.str();
}
void write_lines(std::ostream &out, const std::vector<std::string> &lines) {
    for (const std::string &line : lines)
        out << line << '\n';
}
