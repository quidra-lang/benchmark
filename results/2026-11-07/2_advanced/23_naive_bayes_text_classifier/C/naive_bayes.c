#include "classifier.h"

TrainingCounts training_counts(const Encoded *sequences, Document *const *documents, int count, int classes, int size) {
    TrainingCounts counts = {0};
    counts.classes = classes;
    counts.size = size;
    counts.document_total = count;
    counts.occurrences = temporary((size_t)classes * size, sizeof(Integer));
    counts.containing = temporary((size_t)classes * size, sizeof(Integer));
    counts.term_totals = temporary((size_t)size, sizeof(Integer));
    for (int i = 0; i < count; ++i) {
        int label = documents[i]->label;
        ++counts.documents[label];
        const Encoded *sequence = &sequences[i];
        for (int j = 0; j < sequence->count; ++j) ++counts.occurrences[label * size + sequence->terms[j]];
        for (int j = 0; j < sequence->distinct; ++j) ++counts.containing[label * size + sequence->first[j]];
    }
    for (int label = 0; label < classes; ++label) for (int term = 0; term < size; ++term) {
        Integer value = counts.occurrences[label * size + term];
        counts.totals[label] += value;
        counts.term_totals[term] += value;
    }
    for (int label = 0; label < classes; ++label) counts.total += counts.totals[label];
    return counts;
}
void free_counts(TrainingCounts *counts) {
    free(counts->occurrences);
    free(counts->containing);
    free(counts->term_totals);
}
double smoothed_log(Integer count, Integer total, int alpha, int outcomes) {
    Integer numerator = 100 * count + alpha, denominator = 100 * total + (Integer)alpha * outcomes;
    return log((double)numerator / (double)denominator);
}
NaiveBayes train_model(int kind, const TrainingCounts *counts, int alpha) {
    NaiveBayes model = {0};
    model.kind = kind;
    model.classes = counts->classes;
    model.size = counts->size;
    model.weights = temporary((size_t)model.classes * model.size, sizeof(double));
    for (int label = 0; label < model.classes; ++label) {
        model.priors[label] = log((double)counts->documents[label] / counts->document_total);
        for (int term = 0; term < model.size; ++term) {
            int index = label * model.size + term;
            if (kind == 0) model.weights[index] = smoothed_log(counts->occurrences[index], counts->totals[label], alpha, model.size);
            else if (kind == 1) {
                Integer present_count = counts->containing[index], documents = counts->documents[label];
                double present = smoothed_log(present_count, documents, alpha, 2);
                double absent = smoothed_log(documents - present_count, documents, alpha, 2);
                model.base[label] += absent;
                model.weights[index] = present - absent;
            } else model.weights[index] = -smoothed_log(counts->term_totals[term] - counts->occurrences[index], counts->total - counts->totals[label], alpha, model.size);
        }
    }
    return model;
}
void free_model(NaiveBayes *model) { free(model->weights); }
Prediction posterior(const double *scores, int classes) {
    Prediction result = {0};
    for (int label = 0; label < classes; ++label) {
        result.scores[label] = scores[label];
        int position = label;
        while (position && scores[label] > scores[result.ranking[position - 1]]) { result.ranking[position] = result.ranking[position - 1]; --position; }
        result.ranking[position] = label;
    }
    result.label = result.ranking[0];
    for (int label = 0; label < classes; ++label) {
        result.probabilities[label] = exp(scores[label] - scores[result.label]);
        result.normalizer += result.probabilities[label];
    }
    for (int label = 0; label < classes; ++label) result.probabilities[label] /= result.normalizer;
    result.score = result.probabilities[result.label];
    result.margin = scores[result.label] - scores[result.ranking[1]];
    return result;
}
Prediction predict_nb(const NaiveBayes *model, const Encoded *sequence) {
    double scores[8];
    const int *terms = model->kind == 1 ? sequence->first : sequence->terms;
    int count = model->kind == 1 ? sequence->distinct : sequence->count;
    for (int label = 0; label < model->classes; ++label) {
        double score = model->base[label];
        for (int i = 0; i < count; ++i) score += model->weights[label * model->size + terms[i]];
        scores[label] = score + model->priors[label];
    }
    return posterior(scores, model->classes);
}
