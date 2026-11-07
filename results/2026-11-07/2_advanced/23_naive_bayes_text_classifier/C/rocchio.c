#include "classifier.h"

typedef struct { int term, frequency; double value; } Component;
static int component_order(const void *a, const void *b) { return ((const Component *)a)->term - ((const Component *)b)->term; }
static double vector(const Rocchio *model, const Encoded *sequence, Component *components) {
    for (int i = 0; i < sequence->distinct; ++i) components[i] = (Component){sequence->first[i], sequence->frequencies[i], 0};
    if (sequence->distinct > 1) qsort(components, (size_t)sequence->distinct, sizeof(Component), component_order);
    double squares = 0;
    for (int i = 0; i < sequence->distinct; ++i) {
        components[i].value = components[i].frequency * model->idf[components[i].term];
        squares += components[i].value * components[i].value;
    }
    return sqrt(squares);
}
Rocchio train_rocchio(const Encoded *sequences, Document *const *documents, int count, int classes, const Vocabulary *vocabulary) {
    Rocchio model = {0};
    model.classes = classes;
    model.size = vocabulary->size;
    model.idf = temporary((size_t)model.size, sizeof(double));
    model.centroids = temporary((size_t)classes * model.size, sizeof(double));
    int class_sizes[8] = {0};
    for (int term = 0; term < model.size; ++term) model.idf[term] = log((double)count / vocabulary->frequencies[term]);
    for (int i = 0; i < count; ++i) {
        int label = documents[i]->label;
        ++class_sizes[label];
        Component components[600];
        double length = vector(&model, &sequences[i], components);
        if (length > 0) for (int j = 0; j < sequences[i].distinct; ++j) model.centroids[label * model.size + components[j].term] += components[j].value / length;
    }
    for (int label = 0; label < classes; ++label) {
        double squares = 0;
        for (int term = 0; term < model.size; ++term) {
            double *value = &model.centroids[label * model.size + term];
            *value /= class_sizes[label];
            squares += *value * *value;
        }
        model.lengths[label] = sqrt(squares);
    }
    return model;
}
Prediction predict_rocchio(const Rocchio *model, const Encoded *sequence) {
    Component components[600];
    double length = vector(model, sequence, components);
    Prediction prediction = {0};
    for (int label = 0; label < model->classes; ++label) {
        double similarity = 0;
        if (length > 0 && model->lengths[label] > 0) {
            double product = 0;
            for (int i = 0; i < sequence->distinct; ++i) product += components[i].value * model->centroids[label * model->size + components[i].term];
            similarity = product / (length * model->lengths[label]);
        }
        prediction.scores[label] = similarity;
        int position = label;
        while (position && similarity > prediction.scores[prediction.ranking[position - 1]]) { prediction.ranking[position] = prediction.ranking[position - 1]; --position; }
        prediction.ranking[position] = label;
    }
    prediction.label = prediction.ranking[0];
    prediction.score = prediction.scores[prediction.label];
    return prediction;
}
void free_rocchio(Rocchio *model) { free(model->idf); free(model->centroids); }
