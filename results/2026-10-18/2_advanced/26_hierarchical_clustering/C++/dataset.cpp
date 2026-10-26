#include "clustering.hpp"

static Lines readLines(const std::string& path) {
    std::ifstream input(path, std::ios::binary);
    Lines lines;
    std::string line;
    while (std::getline(input, line)) lines.push_back(line);
    return lines;
}
static Lines split(const std::string& line, char separator) {
    Lines fields;
    std::istringstream input(line);
    std::string field;
    while (std::getline(input, field, separator)) fields.push_back(field);
    return fields;
}
Dataset readDataset() {
    Dataset data;
    Lines lines = readLines("input/data.csv");
    Lines header = split(lines[0], ',');
    data.features.assign(header.begin() + 2, header.end());
    for (std::size_t index = 1; index < lines.size(); ++index) {
        Lines fields = split(lines[index], ',');
        data.ids.push_back(fields[0]); data.labels.push_back(fields[1]);
        Values row;
        for (std::size_t feature = 2; feature < fields.size(); ++feature) row.push_back(std::stod(fields[feature]));
        data.raw.push_back(std::move(row));
    }
    std::map<std::string, Lines> entries;
    for (const std::string& line : readLines("input/params.txt")) { Lines fields = split(line, ' '); entries[fields[0]] = Lines(fields.begin() + 1, fields.end()); }
    Settings& settings = data.settings;
    settings.distance = entries.at("DISTANCE")[0]; settings.standardize = entries.at("STANDARDIZE")[0];
    settings.linkages = entries.at("LINKAGES");
    for (const std::string& value : entries.at("CUT_HEIGHTS")) settings.cutHeights.push_back(std::stod(value));
    for (const std::string& value : entries.at("CUT_K")) settings.cutCounts.push_back(std::stoi(value));
    settings.inconsistencyDepthText = entries.at("INCONSISTENCY")[0];
    settings.inconsistencyDepth = settings.inconsistencyDepthText.size() > 3 ? 120 : std::min<Integer>(120, std::stoll(settings.inconsistencyDepthText));
    settings.inconsistencyCount = std::stoi(entries.at("INCONSISTENCY")[1]);
    settings.gapMaxK = std::stoi(entries.at("GAP_MAX_K")[0]); settings.listSize = std::stoi(entries.at("LIST_SIZE")[0]); settings.width = std::stoi(entries.at("DENDROGRAM_WIDTH")[0]);
    settings.compareLinkage = entries.at("COMPARE_LINKAGE")[0];
    settings.replicates = std::stoi(entries.at("SUBSAMPLES")[0]); settings.percent = std::stoi(entries.at("SUBSAMPLES")[1]); settings.seed = std::stoll(entries.at("SUBSAMPLES")[2]);
    settings.refineIterations = std::stoi(entries.at("REFINE_ITERATIONS")[0]);
    return data;
}
void writeLines(const std::string& name, const Lines& lines) {
    std::ofstream output("output/" + name, std::ios::binary);
    for (const std::string& line : lines) output << line << '\n';
}
