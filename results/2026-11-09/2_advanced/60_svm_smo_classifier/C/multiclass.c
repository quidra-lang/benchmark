#include "classifier.h"
Multi *train_multi(const Input *input, Kernel kernel) {
    Multi *out = allocate(1, sizeof(Multi));
    int n = input->multi_train_count;
    double *matrix = kernel_matrix(kernel, input->multi_train, n);
    for (int k = 1; k <= 3; ++k) {
        Example *data = allocate((size_t)n, sizeof(Example));
        memcpy(data, input->multi_train, (size_t)n * sizeof(Example));
        for (int i = 0; i < n; ++i)
            data[i].label = data[i].label == k ? 1 : -1;
        out->rest[k - 1] = train(data, n, kernel, matrix, input->params.multi_c, &input->params);
    }
    const int pairs[3][2] = {{1, 2}, {1, 3}, {2, 3}};
    for (int k = 0; k < 3; ++k) {
        Example *data = allocate((size_t)n, sizeof(Example));
        int indices[150], count = 0;
        for (int i = 0; i < n; ++i)
            if (input->multi_train[i].label == pairs[k][0] ||
                input->multi_train[i].label == pairs[k][1]) {
                data[count] = input->multi_train[i];
                data[count].label = data[count].label == pairs[k][0] ? 1 : -1;
                indices[count++] = i;
            }
        double *selected = allocate((size_t)count * count, sizeof(double));
        for (int i = 0; i < count; ++i)
            for (int j = 0; j < count; ++j)
                selected[i * count + j] = matrix[indices[i] * n + indices[j]];
        out->pairs[k] = train(data, count, kernel, selected, input->params.multi_c, &input->params);
    }
    return out;
}
MultiPrediction classify(const Multi *models, const double *point) {
    MultiPrediction out = {0};
    out.ovr = 1;
    for (int k = 0; k < 3; ++k) {
        out.rest[k] = decision(&models->rest[k], point);
        if (out.rest[k] > out.rest[out.ovr - 1])
            out.ovr = k + 1;
    }
    const int pairs[3][2] = {{0, 1}, {0, 2}, {1, 2}};
    for (int k = 0; k < 3; ++k) {
        int a = pairs[k][0], b = pairs[k][1];
        double value = decision(&models->pairs[k], point);
        out.pairs[k] = value;
        ++out.votes[value > 0 ? a : b];
        out.scores[a] += value;
        out.scores[b] -= value;
    }
    int maximum = out.votes[0], tied = 0;
    for (int k = 1; k < 3; ++k)
        if (out.votes[k] > maximum)
            maximum = out.votes[k];
    for (int k = 0; k < 3; ++k)
        if (out.votes[k] == maximum) {
            ++tied;
            if (out.ovo == 0 || out.scores[k] > out.scores[out.ovo - 1])
                out.ovo = k + 1;
        }
    out.tie = tied > 1;
    return out;
}
