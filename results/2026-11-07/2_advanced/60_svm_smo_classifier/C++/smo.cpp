#include "classifier.hpp"
class Trainer {
    Model model;
    const Params &params;
    Field errors;
    bool nonbound(int i) const { return model.alpha[i] > 0 && model.alpha[i] < model.c; }
    double snap(double value) const {
        return value < 0.00000001 ? 0 : value > model.c - 0.00000001 ? model.c : value;
    }
    bool take(int i1, int i2) {
        if (i1 == i2)
            return false;
        const double alpha1 = model.alpha[i1], alpha2 = model.alpha[i2], e1 = errors[i1],
                     e2 = errors[i2];
        const int y1 = model.data[i1].label, y2 = model.data[i2].label;
        const double lo = y1 != y2 ? std::max(0.0, alpha2 - alpha1)
                                   : std::max(0.0, alpha2 + alpha1 - model.c),
                     hi = y1 != y2 ? std::min(model.c, model.c + alpha2 - alpha1)
                                   : std::min(model.c, alpha2 + alpha1);
        if (lo == hi)
            return false;
        const double k11 = model.matrix[i1][i1], k12 = model.matrix[i1][i2],
                     k22 = model.matrix[i2][i2], eta = k11 + k22 - 2 * k12;
        if (eta <= 0)
            return false;
        double a2 = alpha2 + y2 * (e1 - e2) / eta;
        int clipping = 0;
        if (a2 < lo) {
            a2 = lo;
            clipping = 1;
        } else if (a2 > hi) {
            a2 = hi;
            clipping = 2;
        }
        a2 = snap(a2);
        if (std::abs(a2 - alpha2) < params.epsilon * (a2 + alpha2 + params.epsilon))
            return false;
        const double a1 = snap(alpha1 + y1 * y2 * (alpha2 - a2)), t1 = y1 * (a1 - alpha1),
                     t2 = y2 * (a2 - alpha2), b1 = e1 + t1 * k11 + t2 * k12 + model.b,
                     b2 = e2 + t1 * k12 + t2 * k22 + model.b;
        const double threshold = a1 > 0 && a1 < model.c   ? b1
                                 : a2 > 0 && a2 < model.c ? b2
                                                          : (b1 + b2) / 2,
                     delta = threshold - model.b;
        for (int i = 0; i < int(errors.size()); ++i)
            errors[i] = errors[i] + (t1 * model.matrix[i1][i] + t2 * model.matrix[i2][i] - delta);
        if (a1 > 0 && a1 < model.c)
            errors[i1] = 0;
        if (a2 > 0 && a2 < model.c)
            errors[i2] = 0;
        model.alpha[i1] = a1;
        model.alpha[i2] = a2;
        model.b = threshold;
        ++model.steps;
        ++model.clipping[clipping];
        return true;
    }
    int examine(int i2) {
        ++model.examined;
        const double r2 = errors[i2] * model.data[i2].label;
        if (!((r2 < -params.tolerance && model.alpha[i2] < model.c) ||
              (r2 > params.tolerance && model.alpha[i2] > 0)))
            return 0;
        int best = -1;
        double distance = -1;
        for (int i = 0; i < int(errors.size()); ++i)
            if (i != i2 && nonbound(i)) {
                const double value = std::abs(errors[i] - errors[i2]);
                if (value > distance) {
                    best = i;
                    distance = value;
                }
            }
        if (best >= 0 && take(best, i2)) {
            ++model.choices[0];
            return 1;
        }
        for (int i = 0; i < int(errors.size()); ++i)
            if (nonbound(i) && take(i, i2)) {
                ++model.choices[1];
                return 1;
            }
        for (int i = 0; i < int(errors.size()); ++i)
            if (take(i, i2)) {
                ++model.choices[2];
                return 1;
            }
        return 0;
    }

  public:
    Trainer(const std::vector<Example> &data, const Kernel &kernel, Matrix matrix, double c,
            const Params &settings)
        : params(settings), errors(data.size()) {
        model.data = data;
        model.kernel = kernel;
        model.matrix = std::move(matrix);
        model.c = c;
        model.alpha.resize(data.size());
        for (int i = 0; i < int(data.size()); ++i)
            errors[i] = -data[i].label;
    }
    Model run() {
        bool all = true;
        while (true) {
            const int before = model.examined;
            int changed = 0;
            for (int i = 0; i < int(errors.size()); ++i)
                if (all || nonbound(i))
                    changed += examine(i);
            if (all)
                ++model.full;
            else
                ++model.nonbound;
            model.passes.push_back(
                {all, model.examined - before, changed, all ? model.alpha : Field{}});
            if (all && changed == 0) {
                model.converged = true;
                break;
            }
            if (int(model.passes.size()) == params.max_passes)
                break;
            if (all)
                all = false;
            else if (changed == 0)
                all = true;
        }
        return std::move(model);
    }
};
Model train(const std::vector<Example> &data, const Kernel &kernel, Matrix matrix, double c,
            const Params &params) {
    return Trainer(data, kernel, std::move(matrix), c, params).run();
}
double Model::decision(Point point) const {
    double out = 0;
    for (int i = 0; i < int(alpha.size()); ++i)
        if (alpha[i] > 0)
            out += alpha[i] * data[i].label * kernel_value(kernel, data[i].point, point);
    return out - b;
}
Field Model::training_decisions() const {
    Field out(alpha.size());
    for (int i = 0; i < int(alpha.size()); ++i) {
        for (int j = 0; j < int(alpha.size()); ++j)
            if (alpha[j] > 0)
                out[i] += alpha[j] * data[j].label * matrix[i][j];
        out[i] -= b;
    }
    return out;
}
