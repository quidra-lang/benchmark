#include "audio.hpp"
#include <algorithm>
#include <cstdlib>

Samples envelope(const Samples& samples, Integer attack, Integer release) {
    Samples levels; Integer level = 0;
    for (Integer sample : samples) {
        Integer magnitude = std::min<Integer>(std::abs(sample),32767), coefficient = magnitude > level ? attack : release;
        level += rdiv((magnitude - level) * coefficient,32768); levels.push_back(level);
    }
    return levels;
}
Processed normalize(const Samples& samples, Integer target) {
    Integer sourcePeak = peak(samples); Samples output = samples;
    if (sourcePeak) for (Integer& sample : output) sample = rdiv(sample * target,sourcePeak); return {output,sourcePeak};
}
Processed gate(const Samples& samples, Integer threshold, Integer hold) {
    Samples output; Integer last = -20001, muted = 0;
    for (Integer j = 0; j < static_cast<Integer>(samples.size()); ++j) {
        if (std::abs(samples[j]) >= threshold) last = j;
        bool open = j - last <= hold; output.push_back(open ? samples[j] : 0); muted += !open;
    }
    return {output,muted};
}
Compressed compress(const Samples& samples, Integer threshold, Integer ratioNumerator, Integer ratioDenominator, Integer attack, Integer release) {
    Samples levels = envelope(samples,attack,release), output; Integer gain = 32768, minimum = 32768, reduced = 0;
    for (int j = 0; j < static_cast<int>(samples.size()); ++j) {
        Integer e = levels[j], target = 32768;
        if (e > threshold) { Integer desired = threshold + rdiv((e - threshold) * ratioDenominator,ratioNumerator); target = rdiv(desired * 32768,e); }
        gain = target < gain ? target : gain + rdiv((target - gain) * release,32768);
        minimum = std::min(minimum,gain); reduced += gain < 32768; output.push_back(rdiv(samples[j] * gain,32768));
    }
    return {output,minimum,reduced};
}
