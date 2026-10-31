#include "classifier.hpp"
Multi train_multi(const Input &input, const Kernel &kernel) {
    Multi out;
    const Matrix matrix = kernel_matrix(kernel, input.multi_train);
    for (int k = 1; k <= 3; ++k) {
        std::vector<Example> data = input.multi_train;
        for (Example &example : data)
            example.label = example.label == k ? 1 : -1;
        out.rest[k - 1] = train(data, kernel, matrix, input.params.multi_c, input.params);
    }
    const std::array<std::array<int, 2>, 3> pairs{{{1, 2}, {1, 3}, {2, 3}}};
    for (int k = 0; k < 3; ++k) {
        std::vector<Example> data;
        Ids indices;
        for (int i = 0; i < int(input.multi_train.size()); ++i) {
            Example example = input.multi_train[i];
            if (example.label != pairs[k][0] && example.label != pairs[k][1])
                continue;
            example.label = example.label == pairs[k][0] ? 1 : -1;
            data.push_back(example);
            indices.push_back(i);
        }
        Matrix selected(indices.size(), Field(indices.size()));
        for (int i = 0; i < int(indices.size()); ++i)
            for (int j = 0; j < int(indices.size()); ++j)
                selected[i][j] = matrix[indices[i]][indices[j]];
        out.pairs[k] = train(data, kernel, selected, input.params.multi_c, input.params);
    }
    return out;
}
MultiPrediction classify(const Multi &models, Point point) {
    MultiPrediction out;
    for (int k = 0; k < 3; ++k) {
        out.rest[k] = models.rest[k].decision(point);
        if (out.rest[k] > out.rest[out.ovr - 1])
            out.ovr = k + 1;
    }
    const std::array<std::array<int, 2>, 3> pairs{{{0, 1}, {0, 2}, {1, 2}}};
    for (int k = 0; k < 3; ++k) {
        const auto pair = pairs[k];
        const double value = models.pairs[k].decision(point);
        out.pairs[k] = value;
        ++out.votes[value > 0 ? pair[0] : pair[1]];
        out.scores[pair[0]] += value;
        out.scores[pair[1]] -= value;
    }
    const int maximum = *std::max_element(out.votes.begin(), out.votes.end());
    int tied = 0;
    out.ovo = 0;
    for (int k = 0; k < 3; ++k)
        if (out.votes[k] == maximum) {
            ++tied;
            if (out.ovo == 0 || out.scores[k] > out.scores[out.ovo - 1])
                out.ovo = k + 1;
        }
    out.tie = tied > 1;
    return out;
}
