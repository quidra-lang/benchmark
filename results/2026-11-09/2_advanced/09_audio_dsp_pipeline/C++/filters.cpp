#include "audio.hpp"
#include <algorithm>

Processed fir(const Samples& samples, Integer divisor, const Samples& taps) {
    ClipCounter clips; Samples output;
    for (Integer n = 0; n < static_cast<Integer>(samples.size()); ++n) {
        Integer total = 0; for (Integer k = 0; k < std::min<Integer>(taps.size(),n + 1); ++k) total += taps[k] * samples[n - k];
        output.push_back(clips.saturate(floorDiv(total,divisor)));
    }
    return {output,clips.count};
}
Processed biquad(const Samples& samples, const Samples& coefficients) {
    Samples signal = samples; ClipCounter clips;
    for (int section = 0; section < static_cast<int>(coefficients.size()); section += 5) {
        Integer u1 = 0, u2 = 0, v1 = 0, v2 = 0; Samples output;
        for (Integer u : signal) {
            Integer value = coefficients[section] * u + coefficients[section + 1] * u1 + coefficients[section + 2] * u2 - coefficients[section + 3] * v1 - coefficients[section + 4] * v2;
            Integer v = clips.saturate(floorDiv(value,16384)); output.push_back(v); u2 = u1; u1 = u; v2 = v1; v1 = v;
        }
        signal = output;
    }
    return {signal,clips.count};
}
Samples movingAverage(const Samples& samples, Integer width) {
    Samples output; Integer total = 0;
    for (Integer n = 0; n < static_cast<Integer>(samples.size()); ++n) { total += samples[n]; if (n >= width) total -= samples[n - width]; output.push_back(rdiv(total,width)); } return output;
}
Processed dcBlock(const Samples& samples, Integer numerator, Integer denominator) {
    ClipCounter clips; Samples output; Integer previousInput = 0, previousOutput = 0;
    for (Integer input : samples) { previousOutput = clips.saturate(input - previousInput + rdiv(numerator * previousOutput,denominator)); previousInput = input; output.push_back(previousOutput); } return {output,clips.count};
}
