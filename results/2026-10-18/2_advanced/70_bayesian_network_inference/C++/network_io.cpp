#include "bayes.hpp"
Names split(const std::string &text, char delimiter) {
    Names out;
    std::istringstream row(text);
    std::string field;
    while (std::getline(row, field, delimiter))
        out.push_back(field);
    return out;
}
static Lines read_lines(const std::string &path) {
    std::ifstream input(path);
    Lines out;
    std::string text;
    while (std::getline(input, text))
        out.push_back(text);
    return out;
}
static int variable_id(const Network &network, const std::string &name) {
    return int(std::find(network.names.begin(), network.names.end(), name) - network.names.begin());
}
Input read_inputs() {
    Input out;
    Lines definitions;
    for (const std::string &text : read_lines("input/network.txt"))
        if (!text.empty() && text[0] != '#')
            definitions.push_back(text);
    Network &network = out.network;
    for (int i = 0; i < int(definitions.size());) {
        Names row = split(definitions[i++]);
        if (row[0] == "VARIABLE") {
            network.names.push_back(row[1]);
            network.states.emplace_back(row.begin() + 2, row.end());
            network.parents.emplace_back();
            network.expert.push_back({});
        } else if (row[0] == "PARENTS") {
            int variable = variable_id(network, row[1]);
            for (int j = 2; j < int(row.size()); ++j)
                network.parents[variable].push_back(variable_id(network, row[j]));
        } else {
            int variable = variable_id(network, row[1]), rows = 1;
            for (int parent : network.parents[variable])
                rows *= int(network.states[parent].size());
            CPT values;
            for (int r = 0; r < rows; ++r) {
                std::vector<double> probabilities;
                for (const std::string &number : split(definitions[i++]))
                    probabilities.push_back(std::stod(number));
                values.push_back(probabilities);
            }
            network.expert[variable] = values;
        }
    }
    Lines samples = read_lines("input/samples.csv");
    Vars columns;
    for (const std::string &name : split(samples[0], ','))
        columns.push_back(variable_id(network, name));
    for (int row = 1; row < int(samples.size()); ++row) {
        Names values = split(samples[row], ',');
        Assignment sample{};
        for (int c = 0; c < int(columns.size()); ++c) {
            int variable = columns[c];
            sample[variable] = int(std::find(network.states[variable].begin(),
                                             network.states[variable].end(), values[c]) -
                                   network.states[variable].begin());
        }
        out.samples.push_back(sample);
    }
    out.queries = read_lines("input/queries.txt");
    out.settings = read_lines("input/params.txt");
    return out;
}
