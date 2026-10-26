#include "cart.hpp"
#include <fstream>
#include <stdexcept>

static Lines readLines(const std::string& path) {
    std::ifstream file(path, std::ios::binary);
    if (!file) throw std::runtime_error("cannot read " + path);
    Lines result;
    std::string line;
    while (std::getline(file, line)) result.push_back(line);
    if (file.bad()) throw std::runtime_error("cannot read " + path);
    return result;
}
static Lines split(const std::string& value, char separator) {
    Lines result;
    std::istringstream stream(value);
    std::string part;
    while (std::getline(stream, part, separator)) result.push_back(part);
    return result;
}
static int position(const Lines& values, const std::string& name) {
    return static_cast<int>(std::find(values.begin(), values.end(), name) - values.begin());
}
static std::vector<Row> readRows(const std::string& name, const Dataset& data) {
    Lines lines = readLines("input/" + name + ".csv");
    std::vector<Row> result;
    for (std::size_t i = 1; i < lines.size(); ++i) {
        Lines fields = split(lines[i], ',');
        Row row{fields.front(), {}, position(data.classes, fields.back())};
        for (std::size_t a = 0; a < data.attributes.size(); ++a) {
            const Attribute& attribute = data.attributes[a];
            const std::string& field = fields[a + 1];
            row.values.push_back(field == "?" ? -1 : attribute.integer ? std::stoll(field) : position(attribute.values, field));
        }
        result.push_back(std::move(row));
    }
    return result;
}
Dataset loadDataset() {
    Dataset data;
    for (const std::string& line : readLines("input/schema.txt")) {
        Lines fields = split(line, ' ');
        if (fields[0] == "ATTRIBUTE") data.attributes.push_back({fields[1], fields[2] == "INT", Lines(fields.begin() + 3, fields.end())});
        else {
            data.target = fields[1];
            data.classes.assign(fields.begin() + 2, fields.end());
        }
    }
    std::vector<Counts> settings;
    for (const std::string& line : readLines("input/params.txt")) {
        Lines fields = split(line, ' ');
        Counts values;
        for (std::size_t i = 1; i < fields.size(); ++i) values.push_back(std::stoll(fields[i]));
        settings.push_back(std::move(values));
    }
    data.settings = {static_cast<int>(settings[0][0]), static_cast<int>(settings[1][0]), static_cast<int>(settings[2][0]), static_cast<int>(settings[3][0]),
                     static_cast<int>(settings[4][0]), static_cast<int>(settings[6][0]), static_cast<int>(settings[8][0]), settings[7][0], settings[9][0], {}};
    for (Integer value : settings[5]) data.settings.curve.push_back(static_cast<int>(value));
    data.train = readRows("train", data);
    data.validation = readRows("validation", data);
    data.test = readRows("test", data);
    return data;
}
Rows rowPointers(const std::vector<Row>& rows) {
    Rows result;
    for (const Row& row : rows) result.push_back(&row);
    return result;
}
