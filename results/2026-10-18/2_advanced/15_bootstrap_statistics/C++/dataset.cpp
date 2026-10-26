#include "statistics.hpp"
#include <fstream>
#include <stdexcept>

static Lines readLines(const std::string& name) {
    std::ifstream file("input/" + name, std::ios::binary);
    if (!file) throw std::runtime_error("cannot read " + name);
    Lines result;
    std::string line;
    while (std::getline(file, line)) result.push_back(line);
    if (file.bad()) throw std::runtime_error("cannot read " + name);
    return result;
}
static Lines split(const std::string& line, char separator) {
    std::istringstream stream(line);
    Lines result;
    std::string part;
    while (std::getline(stream, part, separator)) result.push_back(part);
    return result;
}
static Integer hundredths(const std::string& value) {
    std::size_t point = value.find('.');
    if (point == std::string::npos) return 100 * std::stoll(value);
    std::string fraction = value.substr(point + 1);
    fraction.append(2 - fraction.size(), '0');
    return 100 * std::stoll(value.substr(0, point)) + std::stoll(fraction);
}
Dataset loadDataset() {
    Dataset data;
    std::map<std::string, int> groups;
    Lines samples = readLines("samples.csv");
    for (std::size_t i = 1; i < samples.size(); ++i) {
        Lines fields = split(samples[i], ',');
        if (!groups.count(fields[0])) {
            groups[fields[0]] = static_cast<int>(data.groups.size());
            data.groups.push_back({fields[0], {}});
        }
        data.groups[groups.at(fields[0])].values.push_back(hundredths(fields[1]));
    }
    Lines paired = readLines("paired.csv");
    for (std::size_t i = 1; i < paired.size(); ++i) {
        Lines fields = split(paired[i], ',');
        Integer before = hundredths(fields[1]), after = hundredths(fields[2]);
        data.before.push_back(before);
        data.after.push_back(after);
        data.differences.push_back(after - before);
    }
    Lines parameters = readLines("params.txt");
    std::vector<Sample> settings;
    for (std::size_t i = 0; i < parameters.size(); ++i) {
        Lines fields = split(parameters[i], ' ');
        if (fields[0] == "compare") data.pairs.emplace_back(groups.at(fields[1]), groups.at(fields[2]));
        else {
            Sample values;
            for (std::size_t j = 1; j < fields.size(); ++j) values.push_back(std::stoll(fields[j]));
            settings.push_back(values);
        }
    }
    data.settings = {settings[0][0], static_cast<int>(settings[1][0]), static_cast<int>(settings[2][0]), static_cast<int>(settings[3][0]), static_cast<int>(settings[4][0]), static_cast<int>(settings[5][0]), static_cast<int>(settings[5][1]), static_cast<int>(settings[6][0])};
    return data;
}
