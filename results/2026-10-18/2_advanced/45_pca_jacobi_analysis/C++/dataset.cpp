#include "analysis.hpp"
static Lines split(const std::string &text, char delimiter) {
    Lines out;
    std::istringstream stream(text);
    std::string field;
    while (std::getline(stream, field, delimiter))
        out.push_back(field);
    return out;
}
static std::vector<Sample> read_data(const std::string &path, Lines *names) {
    std::ifstream file(path);
    std::string line;
    std::getline(file, line);
    if (names) {
        *names = split(line, ',');
        names->erase(names->begin());
    }
    std::vector<Sample> out;
    while (std::getline(file, line)) {
        const Lines fields = split(line, ',');
        Sample row;
        row.id = fields[0];
        for (std::size_t j = 1; j < fields.size(); ++j)
            row.values.push_back(fields[j] == "NA" ? std::nullopt
                                                   : std::optional<double>(std::stod(fields[j])));
        out.push_back(std::move(row));
    }
    return out;
}
Input read_input() {
    Input out;
    out.data = read_data("input/data.csv", &out.names);
    out.supplementary = read_data("input/supplementary.csv", nullptr);
    std::ifstream file("input/params.txt");
    std::string key;
    Params &p = out.params;
    file >> key >> p.missing >> key >> p.scaling >> key >> p.components >> key >> p.cumulative >> key >>
        p.repetitions >> p.seed >> key >> p.t2 >> key >> p.spe >> key >> p.cycles >> key >> p.top >> key >>
        p.scree >> key >> p.bw >> p.bh >> key >> p.radius >> key >> p.dw >> p.dh;
    return out;
}
