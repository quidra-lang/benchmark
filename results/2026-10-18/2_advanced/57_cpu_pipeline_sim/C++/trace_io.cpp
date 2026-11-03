#include "simulator.hpp"
Input read_inputs() {
    Input out;
    std::ifstream trace("input/trace.txt");
    std::string text;
    while (std::getline(trace, text))
        out.trace.push_back(text);
    std::ifstream config("input/config.txt");
    while (std::getline(config, text)) {
        std::istringstream row(text);
        std::string key;
        row >> key;
        if (key == "BTB")
            row >> out.config.btb;
        else if (key == "RAS")
            row >> out.config.ras;
        else if (key == "PREDICTOR") {
            Predictor p;
            row >> p.name >> p.scheme;
            for (int &value : p.parameters)
                row >> value;
            out.config.predictors.push_back(p);
        } else if (key == "VARIANT") {
            Variant v;
            std::string forward, stage;
            row >> v.name >> forward >> stage >> v.latency;
            v.forwarding = forward == "ON";
            v.id = stage == "ID";
            out.config.variants.push_back(v);
        } else if (key == "PRIMARY")
            row >> out.config.primary_variant >> out.config.primary_predictor;
        else if (key == "WINDOW")
            row >> out.config.start >> out.config.end;
        else if (key == "TOP")
            row >> out.config.top;
        else if (key == "INTERVAL")
            row >> out.config.interval;
    }
    return out;
}
std::optional<I> parse_hex(const std::string &text) {
    if (text.size() != 8)
        return {};
    I out = 0;
    for (char value : text) {
        if (!((value >= '0' && value <= '9') || (value >= 'a' && value <= 'f')))
            return {};
        out = 16 * out + (value <= '9' ? value - '0' : value - 'a' + 10);
    }
    return out;
}
int parse_register(const std::string &text) {
    if (text == "-")
        return -1;
    if (text.size() < 2 || text.size() > 3 || text[0] != 'r' ||
        (text.size() == 3 && text[1] == '0'))
        return -2;
    int out = 0;
    for (std::size_t i = 1; i < text.size(); ++i) {
        if (text[i] < '0' || text[i] > '9')
            return -2;
        out = 10 * out + text[i] - '0';
    }
    return out <= 31 ? out : -2;
}
