#include "hmm.hpp"
static Rows read(const std::string &name) {
    std::ifstream input("input/" + name);
    Rows out;
    std::string line;
    while (std::getline(input, line)) {
        std::istringstream stream(line);
        Lines fields;
        std::string field;
        while (stream >> field)
            fields.push_back(field);
        out.push_back(std::move(fields));
    }
    return out;
}
void normalize(double *values, int count) {
    double sum = 0;
    for (int i = 0; i < count; ++i)
        sum += values[i];
    for (int i = 0; i < count; ++i)
        values[i] /= sum;
}
Input load() {
    Input out;
    const Rows rows = read("model.txt");
    Model &model = out.model;
    model.name = "INITIAL";
    for (std::size_t i = 1; i < rows[0].size(); ++i)
        model.states += rows[0][i];
    for (std::size_t i = 1; i < rows[1].size(); ++i)
        model.symbols += rows[1][i];
    model.missing = rows[2][1][0];
    for (int i = 0; i < model.k(); ++i)
        model.initial[i] = std::stod(rows[3][i + 1]);
    normalize(model.initial.data(), model.k());
    for (int i = 0; i < model.k(); ++i) {
        for (int j = 0; j < model.k(); ++j)
            model.transition[i][j] = std::stod(rows[4 + i][j + 2]);
        normalize(model.transition[i].data(), model.k());
        for (int j = 0; j < model.m(); ++j)
            model.emission[i][j] = std::stod(rows[4 + model.k() + i][j + 2]);
        normalize(model.emission[i].data(), model.m());
    }
    out.sequences = read("sequences.txt");
    out.labeled = read("labeled.txt");
    out.parameters = read("params.txt");
    return out;
}
std::string real(double value, int places) {
    I factor = 1;
    for (int i = 0; i < places; ++i)
        factor *= 10;
    I amount = I(std::floor(std::abs(value) * factor + 0.5));
    std::ostringstream out;
    if (value < 0 && amount)
        out << '-';
    out << amount / factor << '.' << std::setfill('0') << std::setw(places) << amount % factor;
    return out.str();
}
Lines model_lines(const Model &model) {
    Lines out{"MODEL " + model.name};
    std::string states = "STATES", symbols = "SYMBOLS", initial = "INITIAL";
    for (char state : model.states)
        states += " " + std::string(1, state);
    for (char symbol : model.symbols)
        symbols += " " + std::string(1, symbol);
    for (int i = 0; i < model.k(); ++i)
        initial += " " + real(model.initial[i]);
    out.push_back(states);
    out.push_back(symbols);
    out.push_back("MISSING " + std::string(1, model.missing));
    out.push_back(initial);
    for (int i = 0; i < model.k(); ++i) {
        std::string row = "TRANSITION " + std::string(1, model.states[i]);
        for (int j = 0; j < model.k(); ++j)
            row += " " + real(model.transition[i][j]);
        out.push_back(row);
    }
    for (int i = 0; i < model.k(); ++i) {
        std::string row = "EMISSION " + std::string(1, model.states[i]);
        for (int j = 0; j < model.m(); ++j)
            row += " " + real(model.emission[i][j]);
        out.push_back(row);
    }
    return out;
}
void save(const std::string &name, const Lines &lines) {
    std::ofstream out("output/" + name);
    for (const std::string &line : lines)
        out << line << '\n';
}
