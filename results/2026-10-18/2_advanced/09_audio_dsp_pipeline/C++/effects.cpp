#include "audio.hpp"
#include <algorithm>

Processed gain(const Samples& samples, Integer numerator, Integer denominator) {
    ClipCounter clips; Samples output; for (Integer sample : samples) output.push_back(clips.saturate(rdiv(sample * numerator,denominator))); return {output,clips.count};
}
Processed mix(const std::vector<Samples>& tracks, const Samples& weights, Integer denominator) {
    std::size_t length = 0; for (const Samples& track : tracks) length = std::max(length,track.size());
    ClipCounter clips; Samples output;
    for (std::size_t j = 0; j < length; ++j) {
        Integer total = 0; for (std::size_t k = 0; k < tracks.size(); ++k) if (j < tracks[k].size()) total += weights[k] * tracks[k][j];
        output.push_back(clips.saturate(rdiv(total,denominator)));
    }
    return {output,clips.count};
}
Samples delay(const Samples& samples, Integer count) { Samples result(count); result.insert(result.end(),samples.begin(),samples.end()); return result; }
Processed echo(const Samples& samples, Integer length, Integer numerator, Integer denominator, Integer tail) {
    Samples output = samples; output.resize(samples.size() + tail); ClipCounter clips;
    for (Integer j = length; j < static_cast<Integer>(output.size()); ++j) output[j] = clips.saturate(output[j] + rdiv(numerator * output[j - length],denominator));
    return {output,clips.count};
}
Integer resampledLength(Integer length, Integer oldRate, Integer newRate) { return (length - 1) * newRate / oldRate + 1; }
Samples resample(const Samples& samples, Integer oldRate, Integer newRate) {
    Samples output;
    for (Integer j = 0; j < resampledLength(samples.size(),oldRate,newRate); ++j) {
        Integer position = j * oldRate / newRate, fraction = j * oldRate % newRate, value = samples[position];
        if (fraction) value += rdiv((samples[position + 1] - value) * fraction,newRate); output.push_back(value);
    }
    return output;
}
Samples fade(const Samples& samples, Integer fadeIn, Integer fadeOut) {
    Samples result = samples; Integer length = samples.size();
    for (Integer j = 0; j < fadeIn; ++j) result[j] = rdiv(result[j] * j,fadeIn);
    for (Integer j = length - fadeOut; j < length; ++j) result[j] = rdiv(result[j] * (length - 1 - j),fadeOut); return result;
}
