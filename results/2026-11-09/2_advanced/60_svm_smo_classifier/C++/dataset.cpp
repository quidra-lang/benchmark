#include "classifier.hpp"
static std::vector<std::string> split(const std::string &text, char delimiter) {
    std::vector<std::string> out;
    std::istringstream row(text);
    std::string field;
    while (std::getline(row, field, delimiter))
        out.push_back(field);
    return out;
}
static std::vector<Example> read_data(const std::string &path) {
    std::ifstream input(path);
    std::string text;
    std::getline(input, text);
    std::vector<Example> out;
    while (std::getline(input, text)) {
        const auto fields = split(text, ',');
        out.push_back(
            {fields[0], {std::stod(fields[1]), std::stod(fields[2])}, std::stoi(fields[3])});
    }
    return out;
}
Input load() {
    Input out;
    out.train = read_data("input/train.csv");
    out.test = read_data("input/test.csv");
    std::ifstream multi("input/multiclass.csv");
    std::string text;
    std::getline(multi, text);
    while (std::getline(multi, text)) {
        const auto fields = split(text, ',');
        Example e{fields[0], {std::stod(fields[1]), std::stod(fields[2])}, std::stoi(fields[3])};
        (fields[4] == "train" ? out.multi_train : out.multi_test).push_back(e);
    }
    std::ifstream settings("input/params.txt");
    Params &p = out.params;
    while (std::getline(settings, text)) {
        std::istringstream row(text);
        std::string key;
        row >> key;
        if (key == "C_GRID") {
            double c;
            while (row >> c)
                p.c_grid.push_back(c);
        } else if (key == "KERNEL") {
            Kernel k;
            row >> k.name >> k.kind;
            if (k.kind == "poly")
                row >> k.degree >> k.gamma >> k.coef0;
            else if (k.kind == "rbf")
                row >> k.gamma;
            p.kernels.push_back(k);
        } else if (key == "TOLERANCE")
            row >> p.tolerance;
        else if (key == "EPS")
            row >> p.epsilon;
        else if (key == "MAX_PASSES")
            row >> p.max_passes;
        else if (key == "FOLDS")
            row >> p.folds;
        else if (key == "LEARNING_CURVE") {
            int q;
            while (row >> q)
                p.learning.push_back(q);
        } else if (key == "NEWTON_ITERATIONS")
            row >> p.newton_iterations;
        else if (key == "MULTICLASS")
            row >> p.multi_name >> p.multi_c;
        else if (key == "PEGASOS")
            row >> p.lambda >> p.pegasos_iterations >> p.seed;
        else if (key == "PLOT_X")
            row >> p.x_min >> p.x_max;
        else if (key == "PLOT_Y")
            row >> p.y_min >> p.y_max;
        else if (key == "PLOT_SIZE")
            row >> p.width >> p.height;
    }
    return out;
}
