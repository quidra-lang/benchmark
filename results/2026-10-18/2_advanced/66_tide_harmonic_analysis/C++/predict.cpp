#include "tides.hpp"
double prediction(const Model &model, double time) {
    double out = model.coefficients[0];
    for (int k = 0; k < int(model.speeds.size()); ++k) {
        double theta = angle(model.speeds[k], time);
        out += model.coefficients[2 * k + 1] * std::cos(theta) +
               model.coefficients[2 * k + 2] * std::sin(theta);
    }
    return out;
}
std::vector<Extremum> extrema(const Model &model, int start, int length, int grid) {
    int count = length * 60 / grid;
    Vector values(count + 1);
    for (int j = 0; j <= count; ++j)
        values[j] = prediction(model, double(60 * start + j * grid) / 60);
    std::vector<Extremum> out;
    for (int j = 1; j < count; ++j) {
        bool high = values[j - 1] < values[j] && values[j] > values[j + 1],
             low = values[j - 1] > values[j] && values[j] < values[j + 1];
        if (!high && !low)
            continue;
        double delta = (values[j - 1] - values[j + 1]) /
                       (2 * (values[j - 1] - 2 * values[j] + values[j + 1])),
               mu = 60 * start + j * grid + delta * grid,
               height = values[j] - (values[j - 1] - values[j + 1]) * delta / 4;
        out.push_back({high, mu, height, 0, {}});
    }
    return out;
}
