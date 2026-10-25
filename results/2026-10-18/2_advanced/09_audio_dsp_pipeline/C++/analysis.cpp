#include "audio.hpp"
#include <numeric>

Integer energy(const Samples& samples) { Integer total = 0; for (Integer sample : samples) total += sample * sample; return total; }
static Integer isqrt(Integer value) {
    Integer low = 0, high = value;
    while (low < high) { Integer middle = low + (high - low + 1) / 2; if (middle <= value / middle) low = middle; else high = middle - 1; } return low;
}
Integer rms(const Samples& samples) { return isqrt(energy(samples) / static_cast<Integer>(samples.size())); }
Integer zeroCrossings(const Samples& samples) { Integer count = 0; for (int j = 1; j < static_cast<int>(samples.size()); ++j) count += (samples[j] < 0) != (samples[j - 1] < 0); return count; }
Integer clipped(const Samples& samples) { Integer count = 0; for (Integer sample : samples) count += sample == -32768 || sample == 32767; return count; }
std::string crestFraction(const Samples& samples) {
    Integer denominator = energy(samples); if (!denominator) return "none";
    Integer p = peak(samples), numerator = p * p * static_cast<Integer>(samples.size()), divisor = std::gcd(numerator,denominator);
    return std::to_string(numerator / divisor) + "/" + std::to_string(denominator / divisor);
}
Integer autocorrelation(const Samples& samples, Integer lag) { Integer total = 0; for (Integer j = 0; j + lag < static_cast<Integer>(samples.size()); ++j) total += samples[j] * samples[j + lag]; return total; }
std::optional<Integer> pitchLag(const Samples& samples, Integer low, Integer high) {
    Integer best = low, value = autocorrelation(samples,low);
    for (Integer lag = low + 1; lag <= high; ++lag) { Integer current = autocorrelation(samples,lag); if (current > value) { value = current; best = lag; } }
    return value > 0 ? std::optional<Integer>(best) : std::nullopt;
}
