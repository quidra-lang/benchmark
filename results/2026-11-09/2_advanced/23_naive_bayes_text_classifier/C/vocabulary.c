#include "classifier.h"

static double chi_square(Integer with_term, Integer frequency, Integer class_size, Integer total) {
    Integer others_with = frequency - with_term, without = class_size - with_term, others_without = total - class_size - others_with;
    Integer difference = with_term * others_without - others_with * without;
    Integer numerator = total * difference * difference;
    Integer denominator = frequency * (total - frequency) * class_size * (total - class_size);
    return denominator ? (double)numerator / (double)denominator : 0;
}
static int ranked_order(const void *a, const void *b) {
    const RankedTerm *first = a, *second = b;
    if (first->score != second->score) return first->score > second->score ? -1 : 1;
    return strcmp(term_name(first->term), term_name(second->term));
}
static int term_order(const void *a, const void *b) { return strcmp(term_name(*(const int *)a), term_name(*(const int *)b)); }
Vocabulary build_vocabulary(Document *const *documents, int count, bool bigrams, int classes, int min_df, int size) {
    Vocabulary vocabulary = {0};
    int total_terms = term_count(), class_sizes[8] = {0};
    int *frequencies = temporary((size_t)total_terms * classes, sizeof(int));
    int *seen = temporary((size_t)total_terms, sizeof(int));
    for (int i = 0; i < count; ++i) {
        int label = documents[i]->label;
        ++class_sizes[label];
        Terms terms = token_terms(&documents[i]->tokens, bigrams);
        for (int j = 0; j < terms.count; ++j) {
            int term = terms.items[j];
            if (seen[term] == i + 1) continue;
            seen[term] = i + 1;
            ++frequencies[term * classes + label];
        }
    }
    vocabulary.ranking = temporary((size_t)total_terms, sizeof(RankedTerm));
    for (int term = 0; term < total_terms; ++term) {
        int frequency = 0;
        for (int label = 0; label < classes; ++label) frequency += frequencies[term * classes + label];
        vocabulary.term_count += frequency > 0;
        if (frequency < min_df) continue;
        RankedTerm entry = {term, frequency, 0, chi_square(frequencies[term * classes], frequency, class_sizes[0], count)};
        for (int label = 1; label < classes; ++label) {
            double score = chi_square(frequencies[term * classes + label], frequency, class_sizes[label], count);
            if (score > entry.score) { entry.score = score; entry.best_class = label; }
        }
        vocabulary.ranking[vocabulary.candidate_count++] = entry;
    }
    if (vocabulary.candidate_count > 1) qsort(vocabulary.ranking, (size_t)vocabulary.candidate_count, sizeof(RankedTerm), ranked_order);
    vocabulary.size = size > 0 && vocabulary.candidate_count > size ? size : vocabulary.candidate_count;
    vocabulary.terms = temporary((size_t)vocabulary.size, sizeof(int));
    vocabulary.frequencies = temporary((size_t)vocabulary.size, sizeof(int));
    vocabulary.map = temporary((size_t)total_terms, sizeof(int));
    for (int i = 0; i < total_terms; ++i) vocabulary.map[i] = -1;
    for (int i = 0; i < vocabulary.size; ++i) vocabulary.terms[i] = vocabulary.ranking[i].term;
    if (vocabulary.size > 1) qsort(vocabulary.terms, (size_t)vocabulary.size, sizeof(int), term_order);
    for (int i = 0; i < vocabulary.size; ++i) {
        int term = vocabulary.terms[i];
        vocabulary.map[term] = i;
        for (int label = 0; label < classes; ++label) vocabulary.frequencies[i] += frequencies[term * classes + label];
    }
    free(frequencies);
    free(seen);
    return vocabulary;
}
void free_vocabulary(Vocabulary *vocabulary) {
    free(vocabulary->terms);
    free(vocabulary->frequencies);
    free(vocabulary->map);
    free(vocabulary->ranking);
}
Encoded encode(const Vocabulary *vocabulary, Terms terms) {
    Encoded sequence = {0};
    sequence.terms = temporary((size_t)terms.count * 3, sizeof(int));
    sequence.first = sequence.terms + terms.count;
    sequence.frequencies = sequence.first + terms.count;
    int buckets[2048] = {0};
    for (int i = 0; i < terms.count; ++i) {
        int term = vocabulary->map[terms.items[i]];
        if (term < 0) continue;
        sequence.terms[sequence.count++] = term;
        unsigned int position = (unsigned int)term * 2654435761u % 2048;
        while (buckets[position] && sequence.first[buckets[position] - 1] != term) position = (position + 1) % 2048;
        if (!buckets[position]) {
            sequence.first[sequence.distinct] = term;
            buckets[position] = ++sequence.distinct;
        }
        ++sequence.frequencies[buckets[position] - 1];
    }
    return sequence;
}
void free_encoded(Encoded *sequence) { free(sequence->terms); }
