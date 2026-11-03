#include "knn.hpp"
#include <fstream>
#include <sstream>

static Lines split(const std::string& text, char separator) {
    Lines fields; std::string value; std::istringstream stream(text);
    while (std::getline(stream,value,separator)) fields.push_back(value);
    if (!text.empty() && text.back() == separator) fields.push_back(""); return fields;
}
static std::pair<Lines, std::vector<Row>> readRows(const std::string& name) {
    std::ifstream file("input/" + name); std::string line; std::getline(file,line); Lines header = split(line,',');
    Lines features(header.begin() + 1,header.end() - 2); std::vector<Row> rows;
    while (std::getline(file,line)) {
        Lines fields = split(line,','); Row row{fields[0],{},fields[fields.size() - 2],std::nullopt};
        for (int j = 1; j <= static_cast<int>(features.size()); ++j) row.values.push_back(std::stod(fields[j]));
        if (!fields.back().empty()) row.target = std::stod(fields.back()); rows.push_back(row);
    }
    return {features,rows};
}
Dataset readDataset() {
    auto training = readRows("train.csv"), testing = readRows("test.csv");
    std::ifstream file("input/params.txt"); std::string line; std::map<std::string, Lines> entries;
    while (std::getline(file,line)) { Lines fields = split(line,' '); entries[fields[0]] = Lines(fields.begin() + 1,fields.end()); }
    Settings s; s.scalings = entries.at("SCALINGS"); s.metrics = entries.at("METRICS"); s.weightings = entries.at("WEIGHTINGS");
    for (const std::string& value : entries.at("K_VALUES")) s.ks.push_back(std::stoi(value));
    for (const std::string& value : entries.at("CURVE")) s.curve.push_back(std::stoi(value));
    for (const std::string& value : entries.at("BINS")) s.bins.push_back(std::stod(value));
    s.folds = std::stoi(entries.at("FOLDS")[0]); s.editK = std::stoi(entries.at("EDIT_K")[0]); s.top = std::stoi(entries.at("TOP")[0]);
    return {training.first,training.second,testing.second,s};
}
