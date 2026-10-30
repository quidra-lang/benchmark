#include "classifier.hpp"
#include <filesystem>
int sign(double value) { return value > 0 ? 1 : -1; }
std::vector<Fold> folds(int count, int k) {
    std::vector<Fold> out(k);
    for (int fold = 0; fold < k; ++fold)
        for (int i = 0; i < count; ++i)
            (i % k == fold ? out[fold].test : out[fold].train).push_back(i);
    return out;
}
Evaluation evaluate(const std::vector<Example> &data, const Field &values) {
    Evaluation out;
    for (int i = 0; i < int(data.size()); ++i) {
        const bool positive = sign(values[i]) == 1;
        if (data[i].label == 1) {
            if (positive)
                ++out.tp;
            else
                ++out.fn;
        } else {
            if (positive)
                ++out.fp;
            else
                ++out.tn;
        }
    }
    return out;
}
double auc(const std::vector<Example> &data, const Field &values) {
    double out = 0;
    int positive = 0, negative = 0;
    for (const Example &example : data) {
        positive += example.label == 1;
        negative += example.label == -1;
    }
    for (int i = 0; i < int(data.size()); ++i)
        if (data[i].label == 1)
            for (int j = 0; j < int(data.size()); ++j)
                if (data[j].label == -1)
                    out += values[i] > values[j] ? 1 : values[i] == values[j] ? 0.5 : 0;
    return out / (positive * negative);
}
std::string real(double value, int digits) {
    std::ostringstream out;
    out << std::fixed << std::setprecision(digits) << value;
    std::string text = out.str();
    if (text[0] == '-' && text.find_first_not_of("0.", 1) == std::string::npos)
        text.erase(text.begin());
    return text;
}
std::string ratio(int numerator, int denominator) {
    return denominator ? real(double(numerator) / denominator, 4) : "-";
}
void save(const std::string &name, const Lines &lines) {
    std::filesystem::create_directories("output");
    std::ofstream output("output/" + name);
    for (const std::string &line : lines)
        output << line << '\n';
}

Confusion confusion_matrix(const std::vector<Example> &data,
                           const std::vector<MultiPrediction> &predictions, bool rest) {
    Confusion out{};
    for (int i = 0; i < int(data.size()); ++i)
        ++out[data[i].label - 1][(rest ? predictions[i].ovr : predictions[i].ovo) - 1];
    return out;
}
