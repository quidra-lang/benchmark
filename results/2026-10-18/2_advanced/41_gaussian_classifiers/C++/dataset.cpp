#include "gaussian.hpp"
static Lines read_lines(const std::string &path) {
    std::ifstream input(path);
    Lines out;
    std::string line;
    while (std::getline(input, line))
        out.push_back(line);
    return out;
}
static Lines split(const std::string &line, char delimiter) {
    Lines out;
    std::istringstream input(line);
    std::string value;
    while (std::getline(input, value, delimiter))
        out.push_back(value);
    return out;
}
Dataset read_dataset() {
    Dataset out;
    const Lines training = read_lines("input/train.csv");
    const Lines header = split(training[0], ',');
    out.features.assign(header.begin() + 1, header.end() - 1);
    for (std::size_t i = 1; i < training.size(); ++i)
        out.classes.push_back(split(training[i], ',').back());
    std::sort(out.classes.begin(), out.classes.end());
    out.classes.erase(std::unique(out.classes.begin(), out.classes.end()), out.classes.end());
    auto rows = [&](const Lines &lines) {
        Rows result;
        for (std::size_t i = 1; i < lines.size(); ++i) {
            const Lines fields = split(lines[i], ',');
            Row row;
            row.id = std::stoi(fields[0]);
            for (std::size_t j = 0; j < out.features.size(); ++j)
                row.values[j] = std::stod(fields[j + 1]);
            row.label =
                std::lower_bound(out.classes.begin(), out.classes.end(), fields.back()) - out.classes.begin();
            result.push_back(row);
        }
        return result;
    };
    out.train = rows(training);
    out.test = rows(read_lines("input/test.csv"));
    const Lines costs = read_lines("input/costs.csv");
    const Lines cost_header = split(costs[0], ',');
    for (std::size_t i = 1; i < costs.size(); ++i) {
        const Lines fields = split(costs[i], ',');
        const int actual = std::find(out.classes.begin(), out.classes.end(), fields[0]) - out.classes.begin();
        for (std::size_t j = 1; j < fields.size(); ++j) {
            const int decision =
                std::find(out.classes.begin(), out.classes.end(), cost_header[j]) - out.classes.begin();
            out.costs[actual][decision] = std::stod(fields[j]);
        }
    }
    auto feature = [&](const std::string &name) {
        return int(std::find(out.features.begin(), out.features.end(), name) - out.features.begin());
    };
    for (const std::string &line : read_lines("input/params.txt")) {
        const Lines fields = split(line, ' ');
        const std::string &name = fields[0];
        auto doubles = [&]() {
            std::vector<double> values;
            for (std::size_t i = 1; i < fields.size(); ++i)
                values.push_back(std::stod(fields[i]));
            return values;
        };
        if (name == "PRIOR")
            out.params.empirical = fields[1] == "empirical";
        else if (name == "VAR_SMOOTHING")
            out.params.smoothing = std::stod(fields[1]);
        else if (name == "SMOOTHING_GRID")
            out.params.smoothing_grid = doubles();
        else if (name == "QDA_GAMMA")
            out.params.gamma = std::stod(fields[1]);
        else if (name == "GAMMA_GRID")
            out.params.gamma_grid = doubles();
        else if (name == "CV_FOLDS")
            out.params.folds = std::stoi(fields[1]);
        else if (name == "CALIBRATION_EDGES")
            out.params.calibration = doubles();
        else if (name == "REJECT_THRESHOLDS")
            out.params.reject = doubles();
        else if (name == "CURVE")
            for (std::size_t i = 1; i < fields.size(); ++i)
                out.params.curve.push_back(std::stoi(fields[i]));
        else if (name == "OUTLIER_THRESHOLD")
            out.params.outlier = std::stod(fields[1]);
        else if (name == "BOOTSTRAP") {
            out.params.bootstrap = std::stoi(fields[1]);
            out.params.seed = std::stoll(fields[2]);
        } else if (name == "MAP_SIZE") {
            out.params.map_width = std::stoi(fields[1]);
            out.params.map_height = std::stoi(fields[2]);
        } else if (name == "PLOT_SIZE") {
            out.params.plot_width = std::stoi(fields[1]);
            out.params.plot_height = std::stoi(fields[2]);
        } else if (name == "SUBSET") {
            Subset subset;
            subset.name = fields[1];
            for (std::size_t i = 2; i < fields.size(); ++i)
                subset.features.push_back(feature(fields[i]));
            out.params.subsets.push_back(subset);
        } else if (name == "PAIR")
            out.params.pairs.push_back({feature(fields[1]), feature(fields[2])});
    }
    return out;
}
