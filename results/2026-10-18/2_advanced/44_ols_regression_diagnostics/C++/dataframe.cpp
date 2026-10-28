#include "regression.hpp"
static Lines read_lines(const std::string &path) {
    std::ifstream file(path);
    Lines out;
    std::string line;
    while (std::getline(file, line))
        out.push_back(line);
    return out;
}
static Lines split(const std::string &line, char delimiter) {
    Lines out;
    std::istringstream stream(line);
    std::string field;
    while (std::getline(stream, field, delimiter))
        out.push_back(field);
    return out;
}
Input read_input() {
    Input out;
    const Lines lines = read_lines("input/data.csv");
    out.data.names = split(lines[0], ',');
    out.data.categorical.resize(out.data.names.size());
    for (std::size_t i = 1; i < lines.size(); ++i) {
        const Lines fields = split(lines[i], ',');
        Record record(fields.size());
        for (std::size_t j = 0; j < fields.size(); ++j) {
            if (fields[j] == "NA")
                continue;
            record[j].missing = false;
            if (fields[j][0] >= 'A' && fields[j][0] <= 'Z') {
                record[j].label = fields[j];
                out.data.categorical[j] = true;
            } else
                record[j].number = std::stod(fields[j]);
        }
        out.data.rows.push_back(record);
    }
    out.prediction.names = out.data.names;
    out.prediction.categorical = out.data.categorical;
    const Lines predict = read_lines("input/predict.csv");
    const Lines header = split(predict[0], ',');
    std::vector<int> mapping;
    for (const std::string &name : header)
        mapping.push_back(std::find(out.data.names.begin(), out.data.names.end(), name) -
                          out.data.names.begin());
    for (std::size_t i = 1; i < predict.size(); ++i) {
        const Lines fields = split(predict[i], ',');
        Record record(out.data.names.size());
        for (std::size_t j = 0; j < fields.size(); ++j) {
            if (fields[j] == "NA")
                continue;
            Cell &cell = record[mapping[j]];
            cell.missing = false;
            if (out.data.categorical[mapping[j]])
                cell.label = fields[j];
            else
                cell.number = std::stod(fields[j]);
        }
        out.prediction.rows.push_back(record);
    }
    out.formulas = read_lines("input/model.txt");
    for (const std::string &line : read_lines("input/params.txt")) {
        const Lines fields = split(line, ' ');
        const std::string &key = fields[0];
        const double value = std::stod(fields[1]);
        if (key == "RANK_TOL")
            out.params.rank_tol = value;
        else if (key == "ALPHA_REMOVE")
            out.params.alpha = value;
        else if (key == "CONFIDENCE")
            out.params.confidence = value;
        else if (key == "LEVERAGE")
            out.params.leverage = value;
        else if (key == "STUDENTIZED")
            out.params.studentized = value;
        else if (key == "COOK")
            out.params.cook = value;
        else if (key == "DFFITS")
            out.params.dffits = value;
        else if (key == "VIF")
            out.params.vif = value;
        else if (key == "DURBIN_WATSON")
            out.params.durbin = value;
        else if (key == "BREUSCH_PAGAN")
            out.params.breusch = value;
        else if (key == "NORMALITY")
            out.params.normality = value;
        else if (key == "BEST_SUBSETS")
            out.params.best_subsets = int(value);
        else if (key == "PLOT") {
            out.params.plot_width = int(value);
            out.params.plot_height = std::stoi(fields[2]);
            out.params.plot_limit = std::stod(fields[3]);
        }
    }
    return out;
}
