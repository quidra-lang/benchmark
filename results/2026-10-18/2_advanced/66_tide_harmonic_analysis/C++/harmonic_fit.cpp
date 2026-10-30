#include "tides.hpp"
static constexpr double pi = 3.141592653589793;
double angle(double speed, double time) {
    double degrees = speed * time, reduced = degrees - 360 * std::floor(degrees / 360);
    return reduced * pi / 180;
}
Vector regressors(const Vector &speeds, double time) {
    Vector out{1};
    for (double speed : speeds) {
        double theta = angle(speed, time);
        out.push_back(std::cos(theta));
        out.push_back(std::sin(theta));
    }
    return out;
}
Model fit(const std::vector<Sample> &samples, const Vector &speeds) {
    int size = 2 * int(speeds.size()) + 1;
    Matrix augmented(size, Vector(2 * size + 1, 0));
    for (const Sample &sample : samples) {
        Vector x = regressors(speeds, sample.time);
        for (int i = 0; i < size; ++i) {
            augmented[i][size] += x[i] * sample.value;
            for (int j = 0; j < size; ++j)
                augmented[i][j] += x[i] * x[j];
        }
    }
    for (int i = 0; i < size; ++i)
        augmented[i][size + 1 + i] = 1;
    for (int column = 0; column < size; ++column) {
        int pivot = column;
        for (int i = column + 1; i < size; ++i)
            if (std::abs(augmented[i][column]) > std::abs(augmented[pivot][column]))
                pivot = i;
        if (pivot != column)
            std::swap(augmented[pivot], augmented[column]);
        for (int i = column + 1; i < size; ++i) {
            double factor = augmented[i][column] / augmented[column][column];
            for (int c = column; c <= 2 * size; ++c)
                augmented[i][c] = augmented[i][c] - factor * augmented[column][c];
        }
    }
    Model out;
    out.speeds = speeds;
    out.inverse.assign(size, Vector(size));
    for (int c = size; c <= 2 * size; ++c) {
        Vector solution(size);
        for (int i = size - 1; i >= 0; --i) {
            double sum = augmented[i][c];
            for (int j = i + 1; j < size; ++j)
                sum = sum - augmented[i][j] * solution[j];
            solution[i] = sum / augmented[i][i];
        }
        if (c == size)
            out.coefficients = solution;
        else
            for (int i = 0; i < size; ++i)
                out.inverse[i][c - size - 1] = solution[i];
    }
    for (int k = 0; k < int(speeds.size()); ++k) {
        double a = out.coefficients[2 * k + 1], b = out.coefficients[2 * k + 2];
        out.amplitudes.push_back(std::sqrt(a * a + b * b));
        double phase = std::atan2(b, a) * 180 / pi;
        if (phase < 0)
            phase += 360;
        out.phases.push_back(phase);
    }
    return out;
}
