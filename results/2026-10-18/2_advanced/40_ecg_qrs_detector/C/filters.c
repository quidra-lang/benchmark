#include "ecg.h"
static Integer at(const Integer *values, int index) {
    return index < 0 ? 0 : values[index];
}
Signals *filter(const Input *input) {
    Signals *out = calloc(1, sizeof(Signals));
    out->count = input->count;
    Integer *c = calloc((size_t)input->count, sizeof(Integer));
    Integer highpass_sum = 0, square_sum = 0;
    for (int n = 0; n < input->count; ++n) {
        c[n] = 2 * at(c, n - 1) - at(c, n - 2) + input->ecg[n] - 2 * at(input->ecg, n - 6) +
               at(input->ecg, n - 12);
        out->lowpass[n] = floor_div(c[n], 32);
        highpass_sum += out->lowpass[n] - at(out->lowpass, n - 32);
        out->bandpass[n] = at(out->lowpass, n - 16) - floor_div(highpass_sum, 32);
        out->derivative[n] = floor_div(2 * out->bandpass[n] + at(out->bandpass, n - 1) -
                                           at(out->bandpass, n - 3) - 2 * at(out->bandpass, n - 4),
                                       8);
        out->squared[n] = out->derivative[n] * out->derivative[n];
        square_sum += out->squared[n] - at(out->squared, n - 30);
        out->integrated[n] = floor_div(square_sum, 30);
    }
    free(c);
    return out;
}
