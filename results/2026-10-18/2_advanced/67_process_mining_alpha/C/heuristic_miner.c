#include "mining.h"
Fraction dependency(const Counts *counts, int a, int b) {
    I forward = counts->values[a][b], backward = counts->values[b][a];
    return ratio(forward - backward, forward + backward + 1);
}
Fraction loop_measure(I count) { return ratio(count, count + 1); }
Fraction split_measure(const Counts *counts, int a, int b, int c) {
    return ratio(counts->values[b][c] + counts->values[c][b],
                 counts->values[a][b] + counts->values[a][c] + 1);
}
Fraction join_measure(const Counts *counts, int a, int b, int c) {
    return ratio(counts->values[b][c] + counts->values[c][b],
                 counts->values[b][a] + counts->values[c][a] + 1);
}
