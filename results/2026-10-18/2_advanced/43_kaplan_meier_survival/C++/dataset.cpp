#include "survival.hpp"
static Lines read_lines(const std::string &path) {
    std::ifstream file(path);
    Lines lines;
    std::string line;
    while (std::getline(file, line))
        lines.push_back(line);
    return lines;
}
static Lines split(const std::string &line, char delimiter) {
    Lines out;
    std::istringstream stream(line);
    std::string field;
    while (std::getline(stream, field, delimiter))
        out.push_back(field);
    return out;
}
Dataset read_dataset() {
    Dataset out;
    const Lines lines = read_lines("input/params.txt");
    for (const std::string &line : lines) {
        const Lines fields = split(line, ' ');
        const std::string &key = fields[0];
        if (key == "GROUPS")
            out.params.groups.assign(fields.begin() + 1, fields.end());
        else if (key == "REPORT_TIMES")
            for (std::size_t i = 1; i < fields.size(); ++i)
                out.params.report_times.push_back(std::stoi(fields[i]));
        else if (key == "TAU")
            out.params.tau = std::stoi(fields[1]);
        else if (key == "LIFE_TABLE") {
            out.params.life_width = std::stoi(fields[1]);
            out.params.life_intervals = std::stoi(fields[2]);
        } else if (key == "STRATA")
            out.params.strata = fields[1];
        else if (key == "SUBGROUPS")
            out.params.subgroups.assign(fields.begin() + 1, fields.end());
        else if (key == "LANDMARK")
            out.params.landmark = std::stoi(fields[1]);
        else if (key == "COX")
            out.params.covariates.assign(fields.begin() + 1, fields.end());
        else if (key == "RESIDUALS")
            out.params.residuals = std::stoi(fields[1]);
        else if (key == "PLOT") {
            out.params.plot_width = std::stoi(fields[1]);
            out.params.plot_height = std::stoi(fields[2]);
            out.params.plot_time = std::stoi(fields[3]);
            out.params.plot_divisions = std::stoi(fields[4]);
        }
    }
    const Lines subjects = read_lines("input/subjects.csv");
    for (std::size_t i = 1; i < subjects.size(); ++i) {
        const Lines fields = split(subjects[i], ',');
        const int group = std::find(out.params.groups.begin(), out.params.groups.end(), fields[1]) -
                          out.params.groups.begin();
        out.subjects.push_back({std::stoi(fields[0]), group, std::stoi(fields[2]), std::stoi(fields[3]),
                                std::stoi(fields[4]), std::stoi(fields[6]), fields[5][0]});
    }
    std::sort(out.subjects.begin(), out.subjects.end(),
              [](const Subject &a, const Subject &b) { return a.id < b.id; });
    return out;
}
