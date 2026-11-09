#include "trainer.hpp"
#include <filesystem>
std::string real(double value, int digits) {
    std::ostringstream out;
    out << std::fixed << std::setprecision(digits) << value;
    std::string text = out.str();
    if (text[0] == '-' && text.find_first_not_of("0.", 1) == std::string::npos)
        text.erase(text.begin());
    return text;
}
std::string ratio(std::int64_t numerator, std::int64_t denominator) {
    if (denominator == 0)
        return "-";
    const std::int64_t q = (20000 * numerator + denominator) / (2 * denominator);
    std::ostringstream out;
    out << q / 10000 << '.' << std::setfill('0') << std::setw(4) << q % 10000;
    return out.str();
}
int prediction(const Field &scores) {
    return int(std::max_element(scores.begin(), scores.end()) - scores.begin());
}
int second_class(const Field &scores, int first) {
    int out = first == 0 ? 1 : 0;
    for (int k = 0; k < int(scores.size()); ++k)
        if (k != first && scores[k] > scores[out])
            out = k;
    return out;
}
Counts confusion(const std::vector<Image> &images, const Ids &predictions, int classes) {
    Counts out(classes, Ids(classes));
    for (int i = 0; i < int(images.size()); ++i)
        ++out[images[i].label][predictions[i]];
    return out;
}
ClassStats class_stats(const Counts &matrix, int label) {
    ClassStats out{0, 0, matrix[label][label]};
    for (int k = 0; k < int(matrix.size()); ++k) {
        out.support += matrix[label][k];
        out.predicted += matrix[k][label];
    }
    return out;
}
Lines level_maps(const std::vector<Ids> &levels, int width, int height) {
    Lines out;
    for (int r = 0; r < height; ++r) {
        std::string row;
        for (const Ids &map : levels) {
            if (!row.empty())
                row += ' ';
            for (int c = 0; c < width; ++c)
                row += char('0' + map[r * width + c]);
        }
        out.push_back(row);
    }
    return out;
}
Lines image_lines(const Image &image, int width, int height) {
    Lines out;
    for (int r = 0; r < height; ++r) {
        std::string row;
        for (int c = 0; c < width; ++c)
            row += image.pixels[r * width + c] == '1' ? '#' : '.';
        out.push_back(row);
    }
    return out;
}
void save(const std::string &name, const Lines &lines) {
    std::filesystem::create_directories("output");
    std::ofstream output("output/" + name);
    for (const std::string &line : lines)
        output << line << '\n';
}
