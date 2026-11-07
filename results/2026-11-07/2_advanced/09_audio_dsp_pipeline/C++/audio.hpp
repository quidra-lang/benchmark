#pragma once
#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <vector>

using Integer = std::int64_t;
using Samples = std::vector<Integer>;
using Lines = std::vector<std::string>;
struct Signal;
using SignalPtr = std::shared_ptr<const Signal>;
struct Signal { std::string name; Integer rate; Samples samples; std::string origin; std::vector<SignalPtr> ingredients; };
Integer floorDiv(Integer numerator, Integer denominator);
Integer rdiv(Integer numerator, Integer denominator);
struct ClipCounter { Integer count = 0; Integer saturate(Integer value); };
Integer peak(const Samples& samples);
std::vector<SignalPtr> readSignals();
Lines formatSignal(const Signal& signal);
Samples impulse(Integer count, Integer position, Integer amplitude);
Samples step(Integer count, Integer position, Integer amplitude);
Samples noise(Integer count, Integer seed);
struct Processed { Samples samples; Integer count; };
Processed gain(const Samples& samples, Integer numerator, Integer denominator);
Processed mix(const std::vector<Samples>& tracks, const Samples& weights, Integer denominator);
Samples delay(const Samples& samples, Integer count);
Processed echo(const Samples& samples, Integer delay, Integer numerator, Integer denominator, Integer tail);
Integer resampledLength(Integer length, Integer oldRate, Integer newRate);
Samples resample(const Samples& samples, Integer oldRate, Integer newRate);
Samples fade(const Samples& samples, Integer fadeIn, Integer fadeOut);
Processed fir(const Samples& samples, Integer divisor, const Samples& taps);
Processed biquad(const Samples& samples, const Samples& coefficients);
Samples movingAverage(const Samples& samples, Integer width);
Processed dcBlock(const Samples& samples, Integer numerator, Integer denominator);
Samples envelope(const Samples& samples, Integer attack, Integer release);
Processed normalize(const Samples& samples, Integer target);
Processed gate(const Samples& samples, Integer threshold, Integer hold);
struct Compressed { Samples samples; Integer minGain, reduced; };
Compressed compress(const Samples& samples, Integer threshold, Integer ratioNumerator, Integer ratioDenominator, Integer attack, Integer release);
Integer energy(const Samples& samples);
Integer rms(const Samples& samples);
Integer zeroCrossings(const Samples& samples);
Integer clipped(const Samples& samples);
std::string crestFraction(const Samples& samples);
Integer autocorrelation(const Samples& samples, Integer lag);
std::optional<Integer> pitchLag(const Samples& samples, Integer low, Integer high);
