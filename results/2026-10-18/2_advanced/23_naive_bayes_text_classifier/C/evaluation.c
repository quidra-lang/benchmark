#include "classifier.h"

char *real_text(double value) {
    char *text = format("%.4f", value);
    return !strcmp(text, "-0.0000") ? text + 1 : text;
}
double decimal_value(double value) { return strtod(real_text(value), NULL); }
char *proportion_text(Integer numerator, Integer denominator) {
    return format("%lld/%lld %s", numerator, denominator, real_text((double)numerator / (double)denominator));
}
char *fraction_text(Integer numerator, Integer denominator) {
    if (!denominator) return "- -";
    Integer first = numerator, second = denominator;
    while (second) { Integer remainder = first % second; first = second; second = remainder; }
    return proportion_text(numerator / first, denominator / first);
}
static int support(const Evaluation *evaluation, int label) {
    int total = 0;
    for (int i = 0; i < evaluation->classes; ++i) total += evaluation->matrix[label][i];
    return total;
}
static int predicted_count(const Evaluation *evaluation, int label) {
    int total = 0;
    for (int i = 0; i < evaluation->classes; ++i) total += evaluation->matrix[i][label];
    return total;
}
Evaluation evaluate(int classes, const int *truths, const int *predictions, int count) {
    Evaluation evaluation = {0};
    evaluation.classes = classes;
    evaluation.total = count;
    for (int i = 0; i < count; ++i) ++evaluation.matrix[truths[i]][predictions[i]];
    int scored = 0;
    double sum = 0;
    for (int label = 0; label < classes; ++label) {
        int hits = evaluation.matrix[label][label];
        evaluation.correct += hits;
        int denominator = support(&evaluation, label) + predicted_count(&evaluation, label);
        if (denominator) { sum += (double)(2 * hits) / denominator; ++scored; }
    }
    evaluation.micro_f1 = (double)evaluation.correct / count;
    evaluation.macro_f1 = sum / scored;
    return evaluation;
}
Lines evaluation_lines(const Evaluation *evaluation, char *const *names) {
    Lines lines = {0};
    Text header = {0};
    text_add(&header, "true\\predicted");
    for (int label = 0; label < evaluation->classes; ++label) text_add(&header, " %s", names[label]);
    add_line(&lines, "%s", header.data);
    for (int label = 0; label < evaluation->classes; ++label) {
        Text row = {0};
        text_add(&row, "%s", names[label]);
        for (int other = 0; other < evaluation->classes; ++other) text_add(&row, " %d", evaluation->matrix[label][other]);
        add_line(&lines, "%s", row.data);
    }
    for (int label = 0; label < evaluation->classes; ++label) {
        int hits = evaluation->matrix[label][label], actual = support(evaluation, label), predicted = predicted_count(evaluation, label);
        add_line(&lines, "class %s precision %s recall %s f1 %s support %d", names[label], fraction_text(hits, predicted), fraction_text(hits, actual), fraction_text(2 * hits, predicted + actual), actual);
    }
    add_line(&lines, "micro_f1 %s macro_f1 %s", real_text(evaluation->micro_f1), real_text(evaluation->macro_f1));
    return lines;
}
