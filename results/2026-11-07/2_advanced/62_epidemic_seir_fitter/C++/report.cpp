#include "epidemic.hpp"
std::string real(double value, int digits) {
    std::ostringstream out;
    out << std::fixed << std::setprecision(digits) << value;
    std::string text = out.str();
    if (text[0] == '-' && text.find_first_not_of("0.", 1) == std::string::npos)
        text.erase(text.begin());
    return text;
}
Lines curve_plot(const std::vector<I> &cases, const Field &fitted) {
    const int days = int(cases.size());
    const I maximum = *std::max_element(cases.begin(), cases.end());
    const int width = int(std::to_string(maximum).size());
    std::array<int, 70> observed{}, predicted{}, day{};
    for (int x = 0; x < 70; ++x) {
        day[x] = 1 + x * (days - 1) / 69;
        observed[x] = std::min(19, int(20 * cases[day[x] - 1] / maximum));
        predicted[x] = std::min(19, int(std::floor(20 * fitted[day[x] - 1] / double(maximum))));
    }
    Lines out;
    line(out, "plot observed o fitted * both # days 1 ", days, " max ", maximum);
    for (int y = 19; y >= 0; --y) {
        std::ostringstream row;
        row << std::setw(width) << maximum * y / 20 << " |";
        for (int x = 0; x < 70; ++x)
            row << (observed[x] == y ? (predicted[x] == y ? '#' : 'o')
                                     : (predicted[x] == y ? '*' : '.'));
        out.push_back(row.str());
    }
    std::string axis(width + 1, ' ');
    axis += '+';
    for (int x = 0; x < 70; ++x)
        axis += x % 10 == 0 ? '+' : '-';
    out.push_back(axis);
    std::string labels(70, ' ');
    for (int x = 0; x <= 60; x += 10) {
        const std::string text = std::to_string(day[x]);
        labels.replace(std::size_t(x), text.size(), text);
    }
    while (!labels.empty() && labels.back() == ' ')
        labels.pop_back();
    out.push_back(std::string(width + 2, ' ') + labels);
    return out;
}
