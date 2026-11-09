#include "audio.hpp"
#include <algorithm>
#include <fstream>
#include <sstream>

Integer floorDiv(Integer numerator, Integer denominator) {
    Integer quotient = numerator / denominator, remainder = numerator % denominator;
    return quotient - (remainder != 0 && (remainder < 0) != (denominator < 0));
}
Integer rdiv(Integer numerator, Integer denominator) { return floorDiv(2 * numerator + denominator,2 * denominator); }
Integer ClipCounter::saturate(Integer value) { Integer limited = std::clamp<Integer>(value,-32768,32767); count += limited != value; return limited; }
Integer peak(const Samples& samples) { Integer result = 0; for (Integer value : samples) result = std::max(result,value < 0 ? -value : value); return result; }
std::vector<SignalPtr> readSignals() {
    std::ifstream file("input/signals.txt"); std::string command, name; Integer rate, count;
    std::vector<SignalPtr> signals;
    while (file >> command >> name >> rate >> count) {
        Samples samples(count); for (Integer& sample : samples) file >> sample;
        signals.push_back(std::make_shared<const Signal>(Signal{name,rate,samples,"input",{}}));
    }
    return signals;
}
Lines formatSignal(const Signal& signal) {
    Lines lines{"SIGNAL " + signal.name + " " + std::to_string(signal.rate) + " " + std::to_string(signal.samples.size())};
    for (int start = 0; start < static_cast<int>(signal.samples.size()); start += 16) {
        std::ostringstream row;
        for (int j = start; j < std::min<int>(start + 16,signal.samples.size()); ++j) { if (j > start) row << ' '; row << signal.samples[j]; } lines.push_back(row.str());
    }
    return lines;
}
Samples impulse(Integer count, Integer position, Integer amplitude) { Samples result(count); result[position] = amplitude; return result; }
Samples step(Integer count, Integer position, Integer amplitude) { Samples result(count); std::fill(result.begin() + position,result.end(),amplitude); return result; }
Samples noise(Integer count, Integer seed) {
    Samples result; for (Integer j = 0; j < count; ++j) { seed = 48271 * seed % 2147483647; result.push_back(seed % 65536 - 32768); } return result;
}
