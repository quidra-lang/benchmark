#include "classifier.h"

typedef struct Allocation { struct Allocation *next; max_align_t alignment; } Allocation;
static Allocation *allocations;
static void release_all(void) {
    while (allocations) { Allocation *next = allocations->next; free(allocations); allocations = next; }
}
void *allocate(size_t bytes) {
    static bool registered;
    if (!registered) { atexit(release_all); registered = true; }
    Allocation *block = calloc(1, sizeof(*block) + bytes);
    if (!block) exit(EXIT_FAILURE);
    block->next = allocations;
    allocations = block;
    return block + 1;
}
void *temporary(size_t count, size_t size) {
    void *result = calloc(count ? count : 1, size);
    if (!result) exit(EXIT_FAILURE);
    return result;
}
static char *formatted(const char *pattern, va_list arguments) {
    va_list copy;
    va_copy(copy, arguments);
    int length = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    if (length < 0) exit(EXIT_FAILURE);
    char *result = allocate((size_t)length + 1);
    vsnprintf(result, (size_t)length + 1, pattern, arguments);
    return result;
}
char *format(const char *pattern, ...) {
    va_list arguments;
    va_start(arguments, pattern);
    char *result = formatted(pattern, arguments);
    va_end(arguments);
    return result;
}
void text_add(Text *text, const char *pattern, ...) {
    va_list arguments;
    va_start(arguments, pattern);
    char *part = formatted(pattern, arguments);
    va_end(arguments);
    size_t length = strlen(part);
    if (text->size + length + 1 > text->capacity) {
        size_t capacity = text->capacity ? 2 * text->capacity : 64;
        while (capacity < text->size + length + 1) capacity *= 2;
        char *data = allocate(capacity);
        if (text->size) memcpy(data, text->data, text->size);
        text->data = data;
        text->capacity = capacity;
    }
    memcpy(text->data + text->size, part, length + 1);
    text->size += length;
}
void add_line(Lines *lines, const char *pattern, ...) {
    va_list arguments;
    va_start(arguments, pattern);
    char *line = formatted(pattern, arguments);
    va_end(arguments);
    if (lines->count == lines->capacity) {
        int capacity = lines->capacity ? 2 * lines->capacity : 32;
        char **items = allocate((size_t)capacity * sizeof(*items));
        if (lines->count) memcpy(items, lines->items, (size_t)lines->count * sizeof(*items));
        lines->items = items;
        lines->capacity = capacity;
    }
    lines->items[lines->count++] = line;
}
void paragraph(Lines *target, Lines source) {
    if (target->count) add_line(target, "");
    for (int i = 0; i < source.count; ++i) add_line(target, "%s", source.items[i]);
}
Lines read_lines(const char *name) {
    FILE *file = fopen(format("input/%s", name), "rb");
    if (!file) exit(EXIT_FAILURE);
    Lines lines = {0};
    char buffer[4096];
    while (fgets(buffer, sizeof(buffer), file)) {
        size_t size = strlen(buffer);
        if (size && buffer[size - 1] == '\n') buffer[--size] = '\0';
        add_line(&lines, "%s", buffer);
    }
    if (ferror(file)) exit(EXIT_FAILURE);
    fclose(file);
    return lines;
}
Lines split_text(const char *text, char separator) {
    Lines result = {0};
    size_t start = 0;
    for (size_t i = 0;; ++i) if (!text[i] || text[i] == separator) {
        char *part = allocate(i - start + 1);
        memcpy(part, text + start, i - start);
        add_line(&result, "%s", part);
        if (!text[i]) break;
        start = i + 1;
    }
    return result;
}
static void write_lines(const char *name, Lines lines) {
    if (mkdir("output", 0777) && errno != EEXIST) exit(EXIT_FAILURE);
    FILE *file = fopen(format("output/%s", name), "wb");
    if (!file) exit(EXIT_FAILURE);
    for (int i = 0; i < lines.count; ++i) if (fprintf(file, "%s\n", lines.items[i]) < 0) exit(EXIT_FAILURE);
    if (fclose(file)) exit(EXIT_FAILURE);
}

static const char *model_names[] = {"multinomial", "bernoulli", "complement", "rocchio", "vote"};
typedef struct {
    int alphas[10], alpha_count, min_df, features, top, curve[10], curve_count, sizes[10], size_count;
    int thresholds[9], threshold_count, lengths[9], length_count, iterations, weight, resamples;
    Integer seed;
    bool bigrams;
} Settings;
typedef struct { bool bigrams, trained; Vocabulary vocabulary; TrainingCounts counts; Rocchio rocchio; NaiveBayes models[3]; } Training;
typedef struct { int predictions[1500], fold_correct[5]; Evaluation evaluation; } CrossValidationRun;
typedef struct { int train, validate, candidates, vocabulary; } FoldSummary;
typedef struct {
    Settings settings;
    char *classes[8]; int class_count;
    Document training[1500], tests[500], unlabelled[1000];
    int train_count, test_count, unlabelled_count, labelled[500], truths[500], labelled_count;
    CrossValidationRun cv[3][10], rocchio_cv;
    int selected[3]; FoldSummary folds[5];
    Training final;
    Encoded test_sequences[500];
    Prediction predictions[5][500];
    bool correct[5][500];
} Experiment;

static int hundredths(const char *text) {
    const char *dot = strchr(text, '.');
    return atoi(text) * 100 + atoi(dot + 1);
}
static char *hundredths_text(int value) { return format("%d.%02d", value / 100, value % 100); }
static int string_order(const void *first, const void *second) { return strcmp(*(char *const *)first, *(char *const *)second); }
static int class_index(const Experiment *experiment, const char *name) {
    for (int i = 0; i < experiment->class_count; ++i) if (!strcmp(experiment->classes[i], name)) return i;
    return -1;
}
static Experiment *load_experiment(void) {
    Experiment *experiment = allocate(sizeof(*experiment));
    Settings *settings = &experiment->settings;
    Lines parameters = read_lines("params.txt");
    for (int line = 0; line < parameters.count; ++line) {
        Lines fields = split_text(parameters.items[line], ' ');
        int value = atoi(fields.items[1]);
        switch (line) {
            case 0: for (int i = 1; i < fields.count; ++i) settings->alphas[settings->alpha_count++] = hundredths(fields.items[i]); break;
            case 1: settings->min_df = value; break;
            case 2: settings->features = value; break;
            case 3: settings->bigrams = !strcmp(fields.items[1], "yes"); break;
            case 4: settings->top = value; break;
            case 5: for (int i = 1; i < fields.count; ++i) settings->curve[settings->curve_count++] = atoi(fields.items[i]); break;
            case 6: for (int i = 1; i < fields.count; ++i) settings->sizes[settings->size_count++] = atoi(fields.items[i]); break;
            case 7: for (int i = 1; i < fields.count; ++i) settings->thresholds[settings->threshold_count++] = hundredths(fields.items[i]); break;
            case 8: for (int i = 1; i < fields.count; ++i) settings->lengths[settings->length_count++] = atoi(fields.items[i]); break;
            case 9: settings->iterations = value; break;
            case 10: settings->weight = hundredths(fields.items[1]); break;
            case 11: settings->resamples = value; settings->seed = strtoll(fields.items[2], NULL, 10); break;
        }
    }
    Lines stopwords = read_lines("stopwords.txt"), training = read_lines("train.txt");
    for (int i = 0; i < training.count; ++i) {
        Lines fields = split_text(training.items[i], '\t');
        if (class_index(experiment, fields.items[0]) < 0) experiment->classes[experiment->class_count++] = fields.items[0];
    }
    qsort(experiment->classes, (size_t)experiment->class_count, sizeof(char *), string_order);
    for (int i = 0; i < training.count; ++i) {
        Lines fields = split_text(training.items[i], '\t');
        experiment->training[experiment->train_count++] = (Document){format("%d", i + 1), class_index(experiment, fields.items[0]), tokenize(fields.items[1], stopwords)};
    }
    Lines tests = read_lines("test.txt");
    for (int i = 0; i < tests.count; ++i) {
        Lines fields = split_text(tests.items[i], '\t');
        int label = !strcmp(fields.items[1], "?") ? -1 : class_index(experiment, fields.items[1]);
        experiment->tests[experiment->test_count++] = (Document){fields.items[0], label, tokenize(fields.items[2], stopwords)};
        if (label >= 0) {
            experiment->labelled[experiment->labelled_count] = i;
            experiment->truths[experiment->labelled_count++] = label;
        }
    }
    Lines unlabelled = read_lines("unlabelled.txt");
    for (int i = 0; i < unlabelled.count; ++i) experiment->unlabelled[experiment->unlabelled_count++] = (Document){format("%d", i + 1), -1, tokenize(unlabelled.items[i], stopwords)};
    return experiment;
}
static Training make_training(const Experiment *experiment, Document *const *documents, int count, bool bigrams, int size) {
    Training training = {0};
    training.bigrams = bigrams;
    training.vocabulary = build_vocabulary(documents, count, bigrams, experiment->class_count, experiment->settings.min_df, size);
    Encoded *sequences = temporary((size_t)count, sizeof(*sequences));
    for (int i = 0; i < count; ++i) sequences[i] = encode(&training.vocabulary, token_terms(&documents[i]->tokens, bigrams));
    training.counts = training_counts(sequences, documents, count, experiment->class_count, training.vocabulary.size);
    training.rocchio = train_rocchio(sequences, documents, count, experiment->class_count, &training.vocabulary);
    for (int i = 0; i < count; ++i) free_encoded(&sequences[i]);
    free(sequences);
    return training;
}
static void train_selected(const Experiment *experiment, Training *training) {
    for (int kind = 0; kind < 3; ++kind) training->models[kind] = train_model(kind, &training->counts, experiment->settings.alphas[experiment->selected[kind]]);
    training->trained = true;
}
static void free_training(Training *training) {
    if (training->trained) for (int kind = 0; kind < 3; ++kind) free_model(&training->models[kind]);
    free_rocchio(&training->rocchio);
    free_counts(&training->counts);
    free_vocabulary(&training->vocabulary);
}
static Prediction classify(const Training *training, int kind, const Encoded *sequence) {
    return kind == 3 ? predict_rocchio(&training->rocchio, sequence) : predict_nb(&training->models[kind], sequence);
}
static CrossValidationRun *selected_run(Experiment *experiment, int model) { return model == 3 ? &experiment->rocchio_cv : &experiment->cv[model][experiment->selected[model]]; }
static char *alpha_text(const Experiment *experiment, int model) { return model < 3 ? hundredths_text(experiment->settings.alphas[experiment->selected[model]]) : "-"; }
static void summarize_cv(const Experiment *experiment, CrossValidationRun *run) {
    int truths[1500];
    for (int i = 0; i < experiment->train_count; ++i) {
        truths[i] = experiment->training[i].label;
        run->fold_correct[i % 5] += truths[i] == run->predictions[i];
    }
    run->evaluation = evaluate(experiment->class_count, truths, run->predictions, experiment->train_count);
}
static void cross_validate(Experiment *experiment) {
    for (int fold = 0; fold < 5; ++fold) {
        Document *documents[1500];
        int count = 0, held[1500], held_count = 0;
        for (int i = 0; i < experiment->train_count; ++i) {
            if (i % 5 == fold) held[held_count++] = i;
            else documents[count++] = &experiment->training[i];
        }
        Training training = make_training(experiment, documents, count, experiment->settings.bigrams, experiment->settings.features);
        experiment->folds[fold] = (FoldSummary){count, held_count, training.vocabulary.candidate_count, training.vocabulary.size};
        Encoded *sequences = temporary((size_t)held_count, sizeof(*sequences));
        for (int i = 0; i < held_count; ++i) sequences[i] = encode(&training.vocabulary, token_terms(&experiment->training[held[i]].tokens, training.bigrams));
        for (int kind = 0; kind < 3; ++kind) for (int alpha = 0; alpha < experiment->settings.alpha_count; ++alpha) {
            NaiveBayes model = train_model(kind, &training.counts, experiment->settings.alphas[alpha]);
            for (int i = 0; i < held_count; ++i) experiment->cv[kind][alpha].predictions[held[i]] = predict_nb(&model, &sequences[i]).label;
            free_model(&model);
        }
        for (int i = 0; i < held_count; ++i) experiment->rocchio_cv.predictions[held[i]] = predict_rocchio(&training.rocchio, &sequences[i]).label;
        for (int i = 0; i < held_count; ++i) free_encoded(&sequences[i]);
        free(sequences);
        free_training(&training);
    }
    for (int kind = 0; kind < 3; ++kind) {
        for (int alpha = 0; alpha < experiment->settings.alpha_count; ++alpha) summarize_cv(experiment, &experiment->cv[kind][alpha]);
        for (int alpha = 1; alpha < experiment->settings.alpha_count; ++alpha) if (decimal_value(experiment->cv[kind][alpha].evaluation.macro_f1) > decimal_value(experiment->cv[kind][experiment->selected[kind]].evaluation.macro_f1)) experiment->selected[kind] = alpha;
    }
    summarize_cv(experiment, &experiment->rocchio_cv);
}
static void train_final(Experiment *experiment) {
    Document *documents[1500];
    for (int i = 0; i < experiment->train_count; ++i) documents[i] = &experiment->training[i];
    experiment->final = make_training(experiment, documents, experiment->train_count, experiment->settings.bigrams, experiment->settings.features);
    train_selected(experiment, &experiment->final);
    for (int i = 0; i < experiment->test_count; ++i) {
        Encoded sequence = encode(&experiment->final.vocabulary, token_terms(&experiment->tests[i].tokens, experiment->settings.bigrams));
        experiment->test_sequences[i] = sequence;
        int votes[8] = {0};
        for (int model = 0; model < 4; ++model) {
            experiment->predictions[model][i] = classify(&experiment->final, model, &sequence);
            ++votes[experiment->predictions[model][i].label];
        }
        Prediction vote = {0};
        vote.label = experiment->predictions[0][i].label;
        for (int model = 0; model < 4; ++model) {
            int label = experiment->predictions[model][i].label;
            if (votes[label] > votes[vote.label]) vote.label = label;
        }
        vote.score = votes[vote.label] / 4.0;
        experiment->predictions[4][i] = vote;
    }
    for (int model = 0; model < 5; ++model) for (int i = 0; i < experiment->labelled_count; ++i) experiment->correct[model][i] = experiment->predictions[model][experiment->labelled[i]].label == experiment->truths[i];
}

static void extend(Lines *target, Lines source) {
    for (int i = 0; i < source.count; ++i) add_line(target, "%s", source.items[i]);
}
static char *class_counts_text(const Experiment *experiment, const int *counts) {
    Text text = {0};
    for (int label = 0; label < experiment->class_count; ++label) text_add(&text, "%s%s %d", label ? " " : "", experiment->classes[label], counts[label]);
    return text.data;
}
static Lines vocabulary_lines(const Experiment *experiment) {
    const Vocabulary *vocabulary = &experiment->final.vocabulary;
    Lines lines = {0};
    add_line(&lines, "documents %d terms %d candidates %d vocabulary %d", experiment->train_count, vocabulary->term_count, vocabulary->candidate_count, vocabulary->size);
    for (int i = 0; i < vocabulary->size; ++i) {
        RankedTerm entry = vocabulary->ranking[i];
        add_line(&lines, "%d %s %d %s %s", i + 1, term_name(entry.term), entry.frequency, real_text(entry.score), experiment->classes[entry.best_class]);
    }
    return lines;
}
static Lines cv_lines(const Experiment *experiment) {
    Lines lines = {0};
    add_line(&lines, "model,alpha,correct,accuracy,macro_f1,selected");
    for (int kind = 0; kind < 3; ++kind) for (int alpha = 0; alpha < experiment->settings.alpha_count; ++alpha) {
        const Evaluation *evaluation = &experiment->cv[kind][alpha].evaluation;
        add_line(&lines, "%s,%s,%d,%s,%s,%s", model_names[kind], hundredths_text(experiment->settings.alphas[alpha]), evaluation->correct, real_text(evaluation->micro_f1), real_text(evaluation->macro_f1), experiment->selected[kind] == alpha ? "yes" : "no");
    }
    const Evaluation *evaluation = &experiment->rocchio_cv.evaluation;
    add_line(&lines, "rocchio,-,%d,%s,%s,yes", evaluation->correct, real_text(evaluation->micro_f1), real_text(evaluation->macro_f1));
    return lines;
}
static Lines prediction_lines(const Experiment *experiment) {
    Lines lines = {0};
    add_line(&lines, "id,model,label,score");
    for (int i = 0; i < experiment->test_count; ++i) for (int model = 0; model < 5; ++model) {
        Prediction prediction = experiment->predictions[model][i];
        add_line(&lines, "%s,%s,%s,%s", experiment->tests[i].name, model_names[model], experiment->classes[prediction.label], real_text(prediction.score));
    }
    return lines;
}
static void study_evaluations(const Experiment *experiment, const Training *training, Evaluation *evaluations) {
    Encoded *sequences = temporary((size_t)experiment->labelled_count, sizeof(*sequences));
    for (int i = 0; i < experiment->labelled_count; ++i) sequences[i] = encode(&training->vocabulary, token_terms(&experiment->tests[experiment->labelled[i]].tokens, training->bigrams));
    for (int model = 0; model < 4; ++model) {
        int predictions[500];
        for (int i = 0; i < experiment->labelled_count; ++i) predictions[i] = classify(training, model, &sequences[i]).label;
        evaluations[model] = evaluate(experiment->class_count, experiment->truths, predictions, experiment->labelled_count);
    }
    for (int i = 0; i < experiment->labelled_count; ++i) free_encoded(&sequences[i]);
    free(sequences);
}
static Lines curve_lines(const Experiment *experiment) {
    Lines lines = {0};
    add_line(&lines, "size,vocabulary,model,correct,accuracy,macro_f1");
    Document *documents[1500];
    for (int i = 0; i < experiment->train_count; ++i) documents[i] = (Document *)&experiment->training[i];
    for (int i = 0; i < experiment->settings.curve_count; ++i) {
        int size = experiment->settings.curve[i];
        Training training = make_training(experiment, documents, size, experiment->settings.bigrams, experiment->settings.features);
        train_selected(experiment, &training);
        Evaluation evaluations[4];
        study_evaluations(experiment, &training, evaluations);
        for (int model = 0; model < 4; ++model) add_line(&lines, "%d,%d,%s,%d,%s,%s", size, training.vocabulary.size, model_names[model], evaluations[model].correct, real_text(evaluations[model].micro_f1), real_text(evaluations[model].macro_f1));
        free_training(&training);
    }
    return lines;
}
static Lines feature_lines(const Experiment *experiment) {
    Lines lines = {0};
    add_line(&lines, "terms,features,vocabulary,model,correct,accuracy,macro_f1");
    Document *documents[1500];
    for (int i = 0; i < experiment->train_count; ++i) documents[i] = (Document *)&experiment->training[i];
    for (int bigrams = 0; bigrams < 2; ++bigrams) for (int i = 0; i < experiment->settings.size_count; ++i) {
        int size = experiment->settings.sizes[i];
        Training training = make_training(experiment, documents, experiment->train_count, bigrams != 0, size);
        train_selected(experiment, &training);
        Evaluation evaluations[4];
        study_evaluations(experiment, &training, evaluations);
        for (int model = 0; model < 4; ++model) add_line(&lines, "%s,%d,%d,%s,%d,%s,%s", bigrams ? "bigrams" : "unigrams", size, training.vocabulary.size, model_names[model], evaluations[model].correct, real_text(evaluations[model].micro_f1), real_text(evaluations[model].macro_f1));
        free_training(&training);
    }
    return lines;
}

typedef struct { int term, count; } Occurrence;
static int occurrence_order(const void *a, const void *b) {
    const Occurrence *first = a, *second = b;
    return first->count != second->count ? second->count - first->count : strcmp(term_name(first->term), term_name(second->term));
}
static Lines data_part(const Experiment *experiment) {
    const Vocabulary *vocabulary = &experiment->final.vocabulary;
    Lines lines = {0};
    add_line(&lines, "documents train %d test %d labelled %d unlabelled %d classes %d", experiment->train_count, experiment->test_count, experiment->labelled_count, experiment->unlabelled_count, experiment->class_count);
    int train_counts[8] = {0}, test_counts[8] = {0};
    for (int i = 0; i < experiment->train_count; ++i) ++train_counts[experiment->training[i].label];
    for (int i = 0; i < experiment->labelled_count; ++i) ++test_counts[experiment->truths[i]];
    for (int label = 0; label < experiment->class_count; ++label) add_line(&lines, "class %s train %d test %d", experiment->classes[label], train_counts[label], test_counts[label]);
    int raw = 0, stopped = 0, short_words = 0, kept = 0, bigrams = 0, distinct_words = 0, distinct_bigrams = 0;
    bool *seen = temporary((size_t)term_count(), sizeof(bool));
    for (int i = 0; i < experiment->train_count; ++i) {
        Tokens tokens = experiment->training[i].tokens;
        raw += tokens.raw_count; stopped += tokens.stopword_count; short_words += tokens.short_count; kept += tokens.words.count;
        if (experiment->settings.bigrams) bigrams += tokens.bigram_terms.count - tokens.words.count;
        Terms terms = token_terms(&tokens, experiment->settings.bigrams);
        for (int j = 0; j < terms.count; ++j) seen[terms.items[j]] = true;
    }
    for (int term = 0; term < term_count(); ++term) if (seen[term]) {
        if (strchr(term_name(term), '_')) ++distinct_bigrams; else ++distinct_words;
    }
    free(seen);
    add_line(&lines, "train_tokens raw %d stopwords %d short %d unigrams %d bigrams %d", raw, stopped, short_words, kept, bigrams);
    add_line(&lines, "train_terms unigrams %d bigrams %d candidates %d vocabulary %d", distinct_words, distinct_bigrams, vocabulary->candidate_count, vocabulary->size);
    int total = 0, inside = 0;
    int *counts = temporary((size_t)term_count(), sizeof(int));
    for (int i = 0; i < experiment->test_count; ++i) {
        total += token_terms(&experiment->tests[i].tokens, experiment->settings.bigrams).count;
        inside += experiment->test_sequences[i].count;
        Terms words = experiment->tests[i].tokens.words;
        for (int j = 0; j < words.count; ++j) if (vocabulary->map[words.items[j]] < 0) ++counts[words.items[j]];
    }
    add_line(&lines, "test_terms total %d in_vocabulary %d", total, inside);
    Occurrence *oov = temporary((size_t)term_count(), sizeof(*oov));
    int oov_count = 0;
    for (int term = 0; term < term_count(); ++term) if (counts[term]) oov[oov_count++] = (Occurrence){term, counts[term]};
    if (oov_count > 1) qsort(oov, (size_t)oov_count, sizeof(*oov), occurrence_order);
    Text line = {0};
    text_add(&line, "test_oov");
    for (int i = 0; i < oov_count && i < experiment->settings.top; ++i) text_add(&line, " %s %d", term_name(oov[i].term), oov[i].count);
    add_line(&lines, "%s", line.data);
    free(counts); free(oov);
    return lines;
}
static Lines folds_part(const Experiment *experiment) {
    Lines lines = {0};
    add_line(&lines, "folds 5");
    for (int i = 0; i < 5; ++i) {
        FoldSummary fold = experiment->folds[i];
        add_line(&lines, "fold %d train %d validate %d candidates %d vocabulary %d", i + 1, fold.train, fold.validate, fold.candidates, fold.vocabulary);
    }
    return lines;
}
static Lines selection_part(Experiment *experiment) {
    Lines lines = {0};
    add_line(&lines, "selection");
    for (int model = 0; model < 4; ++model) {
        CrossValidationRun *run = selected_run(experiment, model);
        add_line(&lines, "%s alpha %s correct %s macro_f1 %s folds %d %d %d %d %d", model_names[model], alpha_text(experiment, model), proportion_text(run->evaluation.correct, run->evaluation.total), real_text(run->evaluation.macro_f1), run->fold_correct[0], run->fold_correct[1], run->fold_correct[2], run->fold_correct[3], run->fold_correct[4]);
    }
    return lines;
}
static Lines cross_validation_part(Experiment *experiment, int model) {
    Lines lines = {0};
    add_line(&lines, "cross_validation %s alpha %s", model_names[model], alpha_text(experiment, model));
    extend(&lines, evaluation_lines(&selected_run(experiment, model)->evaluation, experiment->classes));
    return lines;
}
static Lines test_part(const Experiment *experiment, int model) {
    int predictions[500], top_two = 0;
    for (int i = 0; i < experiment->labelled_count; ++i) {
        Prediction prediction = experiment->predictions[model][experiment->labelled[i]];
        predictions[i] = prediction.label;
        top_two += experiment->truths[i] == prediction.ranking[0] || experiment->truths[i] == prediction.ranking[1];
    }
    Evaluation evaluation = evaluate(experiment->class_count, experiment->truths, predictions, experiment->labelled_count);
    Lines lines = {0};
    add_line(&lines, "test %s alpha %s", model_names[model], alpha_text(experiment, model));
    add_line(&lines, "labelled %d correct %s", evaluation.total, proportion_text(evaluation.correct, evaluation.total));
    if (model < 4) add_line(&lines, "top2 %s", proportion_text(top_two, evaluation.total));
    extend(&lines, evaluation_lines(&evaluation, experiment->classes));
    return lines;
}
static Lines probability_part(const Experiment *experiment, int model) {
    Settings settings = experiment->settings;
    int bin_rows[10] = {0}, bin_correct[10] = {0}, accepted[9] = {0}, accepted_correct[9] = {0};
    double bin_sums[10] = {0}, loss = 0, brier = 0;
    for (int i = 0; i < experiment->labelled_count; ++i) {
        Prediction prediction = experiment->predictions[model][experiment->labelled[i]];
        int truth = experiment->truths[i];
        bool correct = experiment->correct[model][i];
        loss += log(prediction.normalizer) - (prediction.scores[truth] - prediction.scores[prediction.label]);
        double squares = 0;
        for (int label = 0; label < experiment->class_count; ++label) { double difference = prediction.probabilities[label] - (label == truth ? 1.0 : 0.0); squares += difference * difference; }
        brier += squares;
        int bucket = 0;
        for (int j = 0; j < settings.threshold_count; ++j) if (prediction.score >= settings.thresholds[j] / 100.0) {
            ++bucket; ++accepted[j]; accepted_correct[j] += correct;
        }
        ++bin_rows[bucket]; bin_correct[bucket] += correct; bin_sums[bucket] += prediction.score;
    }
    Lines lines = {0};
    add_line(&lines, "probability %s alpha %s", model_names[model], alpha_text(experiment, model));
    add_line(&lines, "log_loss %s brier %s", real_text(loss / experiment->labelled_count), real_text(brier / experiment->labelled_count));
    for (int bucket = 0; bucket <= settings.threshold_count; ++bucket) {
        int bound = bucket ? settings.thresholds[bucket - 1] : 0, count = bin_rows[bucket];
        if (!count) add_line(&lines, "bin %s rows 0", hundredths_text(bound));
        else add_line(&lines, "bin %s rows %d correct %s mean %s", hundredths_text(bound), count, proportion_text(bin_correct[bucket], count), real_text(bin_sums[bucket] / count));
    }
    for (int i = 0; i < settings.threshold_count; ++i) add_line(&lines, "threshold %s covered %s correct %s", hundredths_text(settings.thresholds[i]), proportion_text(accepted[i], experiment->labelled_count), accepted[i] ? proportion_text(accepted_correct[i], accepted[i]) : "-");
    return lines;
}

static Lines lengths_part(const Experiment *experiment) {
    int rows[10] = {0}, correct[5][10] = {{0}};
    for (int i = 0; i < experiment->labelled_count; ++i) {
        int length = experiment->test_sequences[experiment->labelled[i]].count, bucket = 0;
        for (int j = 0; j < experiment->settings.length_count; ++j) bucket += length >= experiment->settings.lengths[j];
        ++rows[bucket];
        for (int model = 0; model < 5; ++model) correct[model][bucket] += experiment->correct[model][i];
    }
    Lines lines = {0};
    add_line(&lines, "lengths");
    for (int bucket = 0; bucket <= experiment->settings.length_count; ++bucket) {
        Text line = {0};
        text_add(&line, "length %d rows %d", bucket ? experiment->settings.lengths[bucket - 1] : 0, rows[bucket]);
        if (rows[bucket]) for (int model = 0; model < 5; ++model) text_add(&line, " %s %s", model_names[model], proportion_text(correct[model][bucket], rows[bucket]));
        add_line(&lines, "%s", line.data);
    }
    return lines;
}
static Lines comparison_part(const Experiment *experiment) {
    Lines lines = {0};
    add_line(&lines, "comparison");
    for (int first = 0; first < 4; ++first) for (int second = first + 1; second < 4; ++second) {
        int agree = 0, b = 0, c = 0;
        for (int i = 0; i < experiment->test_count; ++i) agree += experiment->predictions[first][i].label == experiment->predictions[second][i].label;
        for (int i = 0; i < experiment->labelled_count; ++i) {
            b += experiment->correct[first][i] && !experiment->correct[second][i];
            c += experiment->correct[second][i] && !experiment->correct[first][i];
        }
        int difference = abs(b - c) - 1;
        if (difference < 0) difference = 0;
        add_line(&lines, "%s %s agree %s b %d c %d statistic %s", model_names[first], model_names[second], proportion_text(agree, experiment->test_count), b, c, fraction_text((Integer)difference * difference, b + c ? b + c : 1));
    }
    int errors[5] = {0};
    for (int i = 0; i < experiment->labelled_count; ++i) {
        int wrong = 0;
        for (int model = 0; model < 4; ++model) wrong += !experiment->correct[model][i];
        ++errors[wrong];
    }
    add_line(&lines, "errors 0 %d 1 %d 2 %d 3 %d 4 %d", errors[0], errors[1], errors[2], errors[3], errors[4]);
    return lines;
}
static int integer_order(const void *first, const void *second) { return *(const int *)first - *(const int *)second; }
static Lines bootstrap_part(const Experiment *experiment) {
    int resamples = experiment->settings.resamples, count = experiment->labelled_count;
    int *totals = temporary((size_t)5 * resamples, sizeof(int));
    Integer state = experiment->settings.seed;
    for (int sample = 0; sample < resamples; ++sample) {
        for (int i = 0; i < count; ++i) {
            state = 48271 * state % 2147483647;
            int chosen = (int)(state % count);
            for (int model = 0; model < 5; ++model) totals[model * resamples + sample] += experiment->correct[model][chosen];
        }
    }
    Lines lines = {0};
    add_line(&lines, "bootstrap resamples %d seed %lld", resamples, experiment->settings.seed);
    int *ordered = temporary((size_t)resamples, sizeof(int)), rank = resamples / 40;
    for (int model = 0; model < 5; ++model) {
        memcpy(ordered, totals + model * resamples, (size_t)resamples * sizeof(int));
        qsort(ordered, (size_t)resamples, sizeof(int), integer_order);
        Integer sum = 0;
        for (int i = 0; i < resamples; ++i) sum += ordered[i];
        add_line(&lines, "%s mean %s low %s high %s", model_names[model], real_text((double)sum / ((Integer)resamples * count)), proportion_text(ordered[rank], count), proportion_text(ordered[resamples - 1 - rank], count));
    }
    for (int first = 0; first < 4; ++first) for (int second = first + 1; second < 4; ++second) {
        int wins = 0, ties = 0, losses = 0;
        for (int i = 0; i < resamples; ++i) {
            int one = totals[first * resamples + i], other = totals[second * resamples + i];
            wins += one > other; ties += one == other; losses += one < other;
        }
        add_line(&lines, "pair %s %s wins %d ties %d losses %d", model_names[first], model_names[second], wins, ties, losses);
    }
    free(ordered); free(totals);
    return lines;
}
static Lines hard_part(Experiment *experiment) {
    int hard[1500], count = 0, class_counts[8] = {0};
    for (int i = 0; i < experiment->train_count; ++i) {
        bool all_wrong = true;
        for (int model = 0; model < 4; ++model) all_wrong &= selected_run(experiment, model)->predictions[i] != experiment->training[i].label;
        if (all_wrong) { hard[count++] = i; ++class_counts[experiment->training[i].label]; }
    }
    Lines lines = {0};
    add_line(&lines, "hard_documents %d %s", count, class_counts_text(experiment, class_counts));
    for (int i = 0; i < count && i < experiment->settings.top; ++i) {
        int document = hard[i];
        Text line = {0};
        text_add(&line, "%s true %s predicted", experiment->training[document].name, experiment->classes[experiment->training[document].label]);
        for (int model = 0; model < 4; ++model) text_add(&line, " %s", experiment->classes[selected_run(experiment, model)->predictions[document]]);
        add_line(&lines, "%s", line.data);
    }
    return lines;
}
static Lines uncertain_part(const Experiment *experiment) {
    int order[500];
    for (int i = 0; i < experiment->test_count; ++i) {
        int position = i;
        while (position && decimal_value(experiment->predictions[0][i].margin) < decimal_value(experiment->predictions[0][order[position - 1]].margin)) { order[position] = order[position - 1]; --position; }
        order[position] = i;
    }
    int shown = experiment->settings.top < experiment->test_count ? experiment->settings.top : experiment->test_count;
    Lines lines = {0};
    add_line(&lines, "uncertain multinomial %d", shown);
    for (int i = 0; i < shown; ++i) {
        int index = order[i];
        Document document = experiment->tests[index];
        Prediction prediction = experiment->predictions[0][index];
        add_line(&lines, "%s predicted %s runner_up %s margin %s posterior %s true %s", document.name, experiment->classes[prediction.label], experiment->classes[prediction.ranking[1]], real_text(prediction.margin), real_text(prediction.score), document.label < 0 ? "?" : experiment->classes[document.label]);
    }
    return lines;
}
typedef struct { Integer numerator, denominator; int term; } Ratio;
static int ratio_order(const void *a, const void *b) {
    const Ratio *first = a, *second = b;
    Integer left = first->numerator * second->denominator, right = second->numerator * first->denominator;
    return left != right ? left > right ? -1 : 1 : first->term - second->term;
}
static Lines misclassified_part(const Experiment *experiment) {
    int count = 0;
    for (int i = 0; i < experiment->labelled_count; ++i) count += !experiment->correct[0][i];
    Lines lines = {0};
    add_line(&lines, "misclassified multinomial %d", count);
    const TrainingCounts *counts = &experiment->final.counts;
    int alpha = experiment->settings.alphas[experiment->selected[0]], size = counts->size;
    for (int i = 0; i < experiment->labelled_count; ++i) {
        if (experiment->correct[0][i]) continue;
        int index = experiment->labelled[i], truth = experiment->truths[i];
        Prediction prediction = experiment->predictions[0][index];
        add_line(&lines, "%s true %s predicted %s posterior %s", experiment->tests[index].name, experiment->classes[truth], experiment->classes[prediction.label], real_text(prediction.score));
        const Encoded *sequence = &experiment->test_sequences[index];
        Ratio entries[600];
        for (int j = 0; j < sequence->distinct; ++j) {
            int term = sequence->first[j];
            entries[j] = (Ratio){100 * counts->occurrences[prediction.label * size + term] + alpha, 100 * counts->occurrences[truth * size + term] + alpha, term};
        }
        if (sequence->distinct > 1) qsort(entries, (size_t)sequence->distinct, sizeof(Ratio), ratio_order);
        for (int j = 0; j < sequence->distinct && j < 3; ++j) {
            int term = entries[j].term, frequency = 0;
            for (int k = 0; k < sequence->distinct; ++k) if (sequence->first[k] == term) frequency = sequence->frequencies[k];
            double *weights = experiment->final.models[0].weights;
            add_line(&lines, "  %s count %d evidence %s", term_name(experiment->final.vocabulary.terms[term]), frequency, real_text(weights[prediction.label * size + term] - weights[truth * size + term]));
        }
    }
    return lines;
}
static NaiveBayes maximization(const Experiment *experiment, const Prediction *posteriors, const Encoded *sequences) {
    const TrainingCounts *counts = &experiment->final.counts;
    int size = counts->size, classes = counts->classes, alpha = experiment->settings.alphas[experiment->selected[0]];
    double *occurrences = temporary((size_t)classes * size, sizeof(double)), documents[8];
    for (int label = 0; label < classes; ++label) {
        documents[label] = counts->documents[label];
        for (int term = 0; term < size; ++term) occurrences[label * size + term] = (double)counts->occurrences[label * size + term];
    }
    double weight = experiment->settings.weight / 100.0;
    for (int i = 0; i < experiment->unlabelled_count; ++i) for (int label = 0; label < classes; ++label) {
        double share = weight * posteriors[i].probabilities[label];
        documents[label] += share;
        for (int j = 0; j < sequences[i].distinct; ++j) occurrences[label * size + sequences[i].first[j]] += share * sequences[i].frequencies[j];
    }
    NaiveBayes model = {0};
    model.classes = classes;
    model.size = size;
    model.weights = temporary((size_t)classes * size, sizeof(double));
    double scale = experiment->train_count + ((Integer)experiment->settings.weight * experiment->unlabelled_count) / 100.0;
    for (int label = 0; label < classes; ++label) {
        double total = 0;
        for (int term = 0; term < size; ++term) total += occurrences[label * size + term];
        for (int term = 0; term < size; ++term) model.weights[label * size + term] = log((100 * occurrences[label * size + term] + alpha) / (100 * total + (Integer)alpha * size));
        model.priors[label] = log(documents[label] / scale);
    }
    free(occurrences);
    return model;
}
static Lines semi_supervised_part(const Experiment *experiment) {
    int count = experiment->unlabelled_count;
    Encoded *sequences = temporary((size_t)count, sizeof(*sequences));
    Prediction *posteriors = temporary((size_t)count, sizeof(*posteriors));
    int *previous = temporary((size_t)count, sizeof(int));
    for (int i = 0; i < count; ++i) sequences[i] = encode(&experiment->final.vocabulary, token_terms(&experiment->unlabelled[i].tokens, experiment->settings.bigrams));
    NaiveBayes model = experiment->final.models[0];
    Lines lines = {0};
    add_line(&lines, "semi_supervised multinomial alpha %s weight %s unlabelled %d", alpha_text(experiment, 0), hundredths_text(experiment->settings.weight), count);
    for (int iteration = 0; iteration <= experiment->settings.iterations; ++iteration) {
        int assigned[8] = {0}, changed = 0;
        for (int i = 0; i < count; ++i) {
            posteriors[i] = predict_nb(&model, &sequences[i]);
            int label = posteriors[i].label;
            ++assigned[label];
            if (iteration) changed += previous[i] != label;
            previous[i] = label;
        }
        int predicted[500];
        for (int i = 0; i < experiment->labelled_count; ++i) predicted[i] = predict_nb(&model, &experiment->test_sequences[experiment->labelled[i]]).label;
        Evaluation evaluation = evaluate(experiment->class_count, experiment->truths, predicted, experiment->labelled_count);
        add_line(&lines, "iteration %d correct %s macro_f1 %s changed %s assigned %s", iteration, proportion_text(evaluation.correct, evaluation.total), real_text(evaluation.macro_f1), iteration ? format("%d", changed) : "-", class_counts_text(experiment, assigned));
        if (iteration < experiment->settings.iterations) {
            NaiveBayes next = maximization(experiment, posteriors, sequences);
            if (iteration) free_model(&model);
            model = next;
        }
    }
    free_model(&model);
    for (int i = 0; i < count; ++i) free_encoded(&sequences[i]);
    free(sequences); free(posteriors); free(previous);
    return lines;
}
static Lines metrics_lines(Experiment *experiment) {
    Lines lines = {0};
    paragraph(&lines, data_part(experiment));
    paragraph(&lines, folds_part(experiment));
    paragraph(&lines, selection_part(experiment));
    for (int model = 0; model < 4; ++model) paragraph(&lines, cross_validation_part(experiment, model));
    for (int model = 0; model < 5; ++model) paragraph(&lines, test_part(experiment, model));
    for (int model = 0; model < 3; ++model) paragraph(&lines, probability_part(experiment, model));
    paragraph(&lines, lengths_part(experiment));
    paragraph(&lines, comparison_part(experiment));
    paragraph(&lines, bootstrap_part(experiment));
    paragraph(&lines, hard_part(experiment));
    paragraph(&lines, uncertain_part(experiment));
    paragraph(&lines, misclassified_part(experiment));
    paragraph(&lines, semi_supervised_part(experiment));
    return lines;
}
static Lines top_feature_lines(const Experiment *experiment) {
    const TrainingCounts *counts = &experiment->final.counts;
    int size = counts->size;
    Lines lines = {0};
    Ratio *entries = temporary((size_t)size, sizeof(*entries));
    Integer *term_totals = temporary((size_t)size, sizeof(Integer));
    for (int kind = 0; kind < 2; ++kind) {
        int alpha = experiment->settings.alphas[experiment->selected[kind]], outcomes = kind ? 2 : size;
        const Integer *table = kind ? counts->containing : counts->occurrences;
        for (int term = 0; term < size; ++term) {
            term_totals[term] = 0;
            for (int label = 0; label < counts->classes; ++label) term_totals[term] += table[label * size + term];
        }
        Lines heading = {0};
        add_line(&heading, "model %s alpha %s vocabulary %d top %d", model_names[kind], alpha_text(experiment, kind), size, experiment->settings.top);
        paragraph(&lines, heading);
        for (int label = 0; label < counts->classes; ++label) {
            Integer total = kind ? counts->documents[label] : counts->totals[label], other = (kind ? counts->document_total : counts->total) - total;
            Lines section = {0};
            add_line(&section, "class %s total %lld other %lld", experiment->classes[label], total, other);
            for (int term = 0; term < size; ++term) entries[term] = (Ratio){100 * table[label * size + term] + alpha, 100 * (term_totals[term] - table[label * size + term]) + alpha, term};
            if (size > 1) qsort(entries, (size_t)size, sizeof(*entries), ratio_order);
            for (int rank = 0; rank < size && rank < experiment->settings.top; ++rank) {
                int term = entries[rank].term;
                Integer count = table[label * size + term], other_count = term_totals[term] - count;
                double odds = smoothed_log(count, total, alpha, outcomes) - smoothed_log(other_count, other, alpha, outcomes);
                add_line(&section, "%d %s %lld %lld %s", rank + 1, term_name(experiment->final.vocabulary.terms[term]), count, other_count, real_text(odds));
            }
            paragraph(&lines, section);
        }
    }
    free(entries); free(term_totals);
    return lines;
}

int main(void) {
    Experiment *experiment = load_experiment();
    cross_validate(experiment);
    train_final(experiment);
    write_lines("vocabulary.txt", vocabulary_lines(experiment));
    write_lines("cv_results.csv", cv_lines(experiment));
    write_lines("predictions.csv", prediction_lines(experiment));
    write_lines("learning_curve.csv", curve_lines(experiment));
    write_lines("feature_study.csv", feature_lines(experiment));
    write_lines("metrics.txt", metrics_lines(experiment));
    write_lines("top_features.txt", top_feature_lines(experiment));
    for (int i = 0; i < experiment->test_count; ++i) free_encoded(&experiment->test_sequences[i]);
    free_training(&experiment->final);
    return 0;
}
