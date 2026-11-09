#include "spc.hpp"
#include <fstream>
#include <sstream>

Constants controlConstants(int size) {
    static const std::array<Constants, 9> rows{{
        {1.880,2.659,0,3.267,0,3.267,1.128,0.7979},
        {1.023,1.954,0,2.568,0,2.574,1.693,0.8862},
        {0.729,1.628,0,2.266,0,2.282,2.059,0.9213},
        {0.577,1.427,0,2.089,0,2.114,2.326,0.9400},
        {0.483,1.287,0.030,1.970,0,2.004,2.534,0.9515},
        {0.419,1.182,0.118,1.882,0.076,1.924,2.704,0.9594},
        {0.373,1.099,0.185,1.815,0.136,1.864,2.847,0.9650},
        {0.337,1.032,0.239,1.761,0.184,1.816,2.970,0.9693},
        {0.308,0.975,0.284,1.716,0.223,1.777,3.078,0.9727}
    }};
    return rows.at(size - 2);
}

Dataset readDataset() {
    Dataset data;
    Settings& s = data.settings;
    std::map<std::string, std::string> fields;
    std::ifstream spec("input/spec.txt");
    std::string line, name, value;
    const Lines charts{"XBAR_R","R","XBAR_S","S","I","MR","STD"};
    while (std::getline(spec, line)) {
        std::istringstream row(line);
        row >> name >> value;
        if (name == "rules") {
            int chart = 0;
            while (charts[chart] != value) ++chart;
            int rule;
            while (row >> rule) s.rules[chart].push_back(rule);
        } else fields[name] = value;
    }
    s.characteristic = fields.at("characteristic");
    s.lsl = std::stoi(fields.at("lsl")); s.usl = std::stoi(fields.at("usl"));
    s.target = std::stoi(fields.at("target")); s.size = std::stoi(fields.at("subgroup_size"));
    s.phase1 = std::stoi(fields.at("phase1_subgroups")); s.passes = std::stoi(fields.at("max_passes"));
    s.span = std::stoi(fields.at("ma_span")); s.gap = std::stoi(fields.at("event_gap"));
    s.bin = std::stoi(fields.at("histogram_bin")); s.window = std::stoi(fields.at("rolling_window"));
    s.step = std::stoi(fields.at("rolling_step")); s.cusumK = std::stod(fields.at("cusum_k"));
    s.cusumH = std::stod(fields.at("cusum_h")); s.weight = std::stod(fields.at("ewma_lambda"));
    s.ewmaL = std::stod(fields.at("ewma_l")); s.ciZ = std::stod(fields.at("ci_z"));
    std::ifstream measurements("input/measurements.csv");
    std::getline(measurements, line);
    while (std::getline(measurements, line)) data.values.push_back(std::stoll(line.substr(line.rfind(',') + 1)));
    std::ifstream attributes("input/attributes.csv");
    std::getline(attributes, line);
    while (std::getline(attributes, line)) {
        for (char& c : line) if (c == ',') c = ' ';
        std::istringstream row(line);
        Lot lot;
        row >> lot.number >> lot.inspected >> lot.defectives >> lot.defects;
        data.lots.push_back(lot);
    }
    return data;
}
