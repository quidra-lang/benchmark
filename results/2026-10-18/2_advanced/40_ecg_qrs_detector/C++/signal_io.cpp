#include "ecg.hpp"
Input read_input() {
    Input out;
    std::ifstream ecg("input/ecg.csv");
    std::string line;
    std::getline(ecg, line);
    while (std::getline(ecg, line))
        out.ecg.push_back(std::stoll(line.substr(line.find(',') + 1)));
    std::ifstream annotations("input/annotations.csv");
    std::getline(annotations, line);
    while (std::getline(annotations, line)) {
        const std::size_t comma = line.find(',');
        out.annotations.push_back({std::stoi(line.substr(0, comma)), line[comma + 1], -1});
    }
    std::ifstream params("input/params.txt");
    Integer *fields[] = {
        &out.params.refractory_ms,     &out.params.twave_ms,     &out.params.searchback_percent,
        &out.params.premature_percent, &out.params.qrs_width_ms, &out.params.match_ms,
        &out.params.pause_ms,          &out.params.brady_ms,     &out.params.tachy_ms,
        &out.params.excerpt_ms,        &out.params.segment_ms,   &out.params.strip_start_ms,
        &out.params.strip_ms,          &out.params.strip_rows,   &out.params.chart_rows,
        &out.params.poincare_size};
    std::string key;
    for (Integer *field : fields)
        params >> key >> *field;
    return out;
}
void write_lines(const std::string &name, const Lines &lines) {
    std::ofstream out("output/" + name, std::ios::binary);
    for (const std::string &line : lines)
        out << line << '\n';
}
