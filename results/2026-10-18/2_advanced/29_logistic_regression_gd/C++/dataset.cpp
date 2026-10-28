#include "regression.hpp"
static std::vector<std::string> split(const std::string &text, char delimiter) {
    std::istringstream input(text);
    std::vector<std::string> values;
    std::string value;
    while (std::getline(input, value, delimiter))
        values.push_back(value);
    return values;
}
Table read_table(const std::string &name) {
    std::ifstream input("input/" + name);
    std::string line;
    std::getline(input, line);
    const std::vector<std::string> header = split(line, ',');
    Table data;
    data.names.assign(header.begin() + 1, header.end() - 1);
    while (std::getline(input, line)) {
        const std::vector<std::string> fields = split(line, ',');
        Row row{fields[0], {}, std::stoi(fields.back())};
        for (std::size_t i = 1; i + 1 < fields.size(); ++i)
            row.values.push_back(std::stod(fields[i]));
        data.rows.push_back(std::move(row));
    }
    return data;
}
Params read_params() {
    Params p;
    std::ifstream input("input/params.txt");
    std::string line, key;
    std::getline(input, line);
    std::istringstream(line) >> key >> p.positive;
    std::getline(input, line);
    std::istringstream(line) >> key >> p.degree;
    std::getline(input, line);
    std::istringstream(line) >> key >> p.threshold;
    std::getline(input, line);
    std::istringstream values(line);
    values >> key;
    double value;
    while (values >> value)
        p.lambdas.push_back(value);
    input >> key >> p.gd_rate >> p.gd_iterations >> key >> p.sgd_rate >> p.batch >> p.epochs >> p.sgd_seed >>
        key >> p.softmax_rate >> p.softmax_iterations >> p.softmax_lambda;
    input >> key >> p.bootstrap >> p.bootstrap_seed >> key >> p.permutations >> p.permutation_seed >> key >>
        p.width >> p.height >> key >> p.fp_cost >> p.fn_cost;
    return p;
}
std::vector<Feature> features(const std::vector<std::string> &names, int degree) {
    std::vector<Feature> result;
    std::vector<int> tuple;
    std::function<void(int, int)> visit = [&](int remaining, int first) {
        if (!remaining) {
            std::string name;
            for (int index : tuple) {
                if (!name.empty())
                    name += '*';
                name += names[index];
            }
            result.push_back({tuple, name});
            return;
        }
        for (int index = first; index < int(names.size()); ++index) {
            tuple.push_back(index);
            visit(remaining - 1, index);
            tuple.pop_back();
        }
    };
    for (int size = 1; size <= degree; ++size)
        visit(size, 0);
    return result;
}
Vector expand(const Vector &values, const std::vector<Feature> &terms) {
    Vector result;
    for (const Feature &feature : terms) {
        double value = values[feature.indices[0]];
        for (std::size_t i = 1; i < feature.indices.size(); ++i)
            value *= values[feature.indices[i]];
        result.push_back(value);
    }
    return result;
}
Matrix expanded(const std::vector<Row> &rows, const std::vector<Feature> &terms) {
    Matrix result;
    for (const Row &row : rows)
        result.push_back(expand(row.values, terms));
    return result;
}
Statistics statistics(const Matrix &data, int count) {
    Statistics result{Vector(count), Vector(count)};
    for (int j = 0; j < count; ++j) {
        double total = 0;
        for (const Vector &row : data)
            total += row[j];
        result.mean[j] = total / double(data.size());
        double squares = 0;
        for (const Vector &row : data) {
            const double delta = row[j] - result.mean[j];
            squares += delta * delta;
        }
        result.deviation[j] = std::sqrt(squares / double(data.size() - 1));
    }
    return result;
}
Vector standardize_point(const Vector &row, const Statistics &stats, int count) {
    Vector result(count + 1, 1);
    for (int j = 0; j < count; ++j)
        result[j + 1] = (row[j] - stats.mean[j]) / stats.deviation[j];
    return result;
}
Matrix standardize(const Matrix &rows, const Statistics &stats, int count) {
    Matrix result;
    for (const Vector &row : rows)
        result.push_back(standardize_point(row, stats, count));
    return result;
}
std::vector<int> labels(const std::vector<Row> &rows, int positive) {
    std::vector<int> result;
    for (const Row &row : rows)
        result.push_back(positive < 0 ? row.label : int(row.label == positive));
    return result;
}
