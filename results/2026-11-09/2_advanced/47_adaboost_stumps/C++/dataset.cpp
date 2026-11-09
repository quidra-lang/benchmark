#include "boosting.hpp"
static Lines split(const std::string &text, char delimiter) {
    Lines out;
    std::istringstream stream(text);
    std::string field;
    while (std::getline(stream, field, delimiter))
        out.push_back(field);
    return out;
}
static Rows read_binary(const std::string &path, Lines *names) {
    std::ifstream file(path);
    std::string line;
    std::getline(file, line);
    const Lines header = split(line, ',');
    if (names)
        names->assign(header.begin() + 1, header.end() - 1);
    Rows out;
    while (std::getline(file, line)) {
        const Lines fields = split(line, ',');
        Row row;
        row.id = fields[0];
        row.label = std::stoi(fields.back());
        for (std::size_t j = 1; j + 1 < fields.size(); ++j)
            row.values.push_back(std::stod(fields[j]));
        out.push_back(std::move(row));
    }
    return out;
}
Input read_input() {
    Input out;
    out.train = read_binary("input/train.csv", &out.names);
    out.test = read_binary("input/test.csv", nullptr);
    std::ifstream multi("input/multiclass.csv");
    std::string line;
    std::getline(multi, line);
    const Lines header = split(line, ',');
    out.multi_names.assign(header.begin() + 1, header.end() - 2);
    while (std::getline(multi, line)) {
        const Lines fields = split(line, ',');
        Row row;
        row.id = fields[0];
        row.label = std::stoi(fields[fields.size() - 2]);
        for (std::size_t j = 1; j + 2 < fields.size(); ++j)
            row.values.push_back(std::stod(fields[j]));
        (fields.back() == "train" ? out.multi_train : out.multi_test).push_back(std::move(row));
    }
    std::ifstream params("input/params.txt");
    Params &p = out.params;
    while (std::getline(params, line)) {
        std::istringstream fields(line);
        std::string key;
        fields >> key;
        if (key == "ROUNDS")
            fields >> p.rounds;
        else if (key == "VARIANTS") {
            std::string value;
            while (fields >> value)
                p.variants.push_back(value);
        } else if (key == "BINS")
            fields >> p.bins;
        else if (key == "SMOOTHING")
            fields >> p.smoothing;
        else if (key == "CONVERGENCE")
            fields >> p.convergence;
        else if (key == "CLIP")
            fields >> p.clip;
        else if (key == "FOLDS")
            fields >> p.folds;
        else if (key == "CLASSES")
            fields >> p.classes;
        else if (key == "SAMME_ROUNDS")
            fields >> p.samme_rounds;
        else if (key == "PERMUTATION")
            fields >> p.permutations >> p.permutation_seed;
        else if (key == "BOOTSTRAP")
            fields >> p.bootstrap >> p.bootstrap_seed;
        else if (key == "NOISE") {
            fields >> p.noise_seed;
            int value;
            while (fields >> value)
                p.noise.push_back(value);
        } else if (key == "SIZES") {
            int value;
            while (fields >> value)
                p.sizes.push_back(value);
        } else {
            double value;
            while (fields >> value)
                (key == "MARGINS" ? p.margins : p.shrinkage).push_back(value);
        }
    }
    return out;
}
