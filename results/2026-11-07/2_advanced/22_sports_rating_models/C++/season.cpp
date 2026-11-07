#include "ratings.hpp"
#include <fstream>
#include <stdexcept>

static Lines readLines(const std::string& name) { std::ifstream file("input/" + name, std::ios::binary); if (!file) throw std::runtime_error("cannot read " + name); Lines lines; std::string line; while (std::getline(file, line)) lines.push_back(line); if (file.bad()) throw std::runtime_error("cannot read " + name); return lines; }
static Lines split(const std::string& line, char separator) { Lines result; std::size_t start = 0; for (std::size_t i = 0; i < line.size(); ++i) if (line[i] == separator) { result.push_back(line.substr(start, i - start)); start = i + 1; } result.push_back(line.substr(start)); return result; }
Season readSeason() {
    Season season; Lines teams = readLines("teams.csv"); std::map<std::string, int> indices;
    for (std::size_t i = 1; i < teams.size(); ++i) { Lines fields = split(teams[i], ','); indices[fields[0]] = static_cast<int>(season.teams.size()); season.teams.push_back({fields[0], fields[1]}); }
    Lines matches = readLines("matches.csv");
    for (std::size_t i = 1; i < matches.size(); ++i) { Lines fields = split(matches[i], ','); season.matches.push_back({std::stoi(fields[0]), indices.at(fields[1]), indices.at(fields[2]), std::stoi(fields[3]), std::stoi(fields[4])}); }
    std::stable_sort(season.matches.begin(), season.matches.end(), [](const Match& first, const Match& second) { return first.round < second.round; });
    std::map<std::string, Lines> values;
    for (const std::string& line : readLines("params.txt")) { Lines fields = split(line, ' '); values[fields[0]] = Lines(fields.begin() + 1, fields.end()); }
    Settings& s = season.settings;
    s.winPoints = std::stoll(values.at("WIN_POINTS")[0]); s.drawPoints = std::stoll(values.at("DRAW_POINTS")[0]); s.formLength = std::stoi(values.at("FORM_LENGTH")[0]); s.closeMargin = std::stoll(values.at("CLOSE_MARGIN")[0]); s.exponent = std::stod(values.at("PYTHAGOREAN_EXPONENT")[0]);
    s.eloK = std::stoll(values.at("ELO_K")[0]); s.eloHome = std::stoll(values.at("ELO_HOME")[0]); s.eloInitial = std::stoll(values.at("ELO_INITIAL")[0]);
    for (const std::string& value : values.at("ELO_GRID_K")) s.gridK.push_back(std::stoll(value));
    for (const std::string& value : values.at("ELO_GRID_HOME")) s.gridHome.push_back(std::stoll(value));
    s.btIterations = std::stoll(values.at("BT_ITERATIONS")[0]); s.odIterations = std::stoll(values.at("OD_ITERATIONS")[0]); s.linkIterations = std::stoll(values.at("LINK_ITERATIONS")[0]); s.holdoutRound = std::stoi(values.at("HOLDOUT_ROUND")[0]); s.upsets = std::stoll(values.at("UPSETS")[0]); s.bins = std::stoi(values.at("CALIBRATION_BINS")[0]); s.simulations = std::stoi(values.at("SIMULATIONS")[0]); s.seed = std::stoll(values.at("SIM_SEED")[0]); s.top = std::stoi(values.at("TOP_POSITIONS")[0]); s.bottom = std::stoi(values.at("BOTTOM_POSITIONS")[0]);
    return season;
}
Matches matchesBefore(const Matches& matches, int round) { Matches result; for (const Match& match : matches) if (match.round < round) result.push_back(match); return result; }
