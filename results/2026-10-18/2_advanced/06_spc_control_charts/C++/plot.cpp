#include "spc.hpp"
#include <algorithm>
#include <cmath>

static void place(std::string& band, double position, char symbol) {
    band[static_cast<int>(std::clamp(position,0.0,60.0))] = symbol;
}

static std::string framed(double center) {
    std::string band(61,'.');
    place(band,0,':'); place(band,60,':'); place(band,center,'|');
    return band;
}

std::string limitsBand(Limits limits, double value, bool signalled) {
    double span = limits.ucl - limits.lcl;
    std::string band = framed(std::floor(60 * ((limits.cl - limits.lcl) / span) + 0.5));
    place(band,std::floor(60 * ((value - limits.lcl) / span) + 0.5),signalled ? '*' : 'o');
    return band;
}

std::string cusumBand(double upper, double lower, double threshold, bool upperSignal, bool lowerSignal) {
    std::string band = framed(30);
    if (lower > 0) place(band,30 - std::min(30.0,std::floor(30 * (lower / threshold) + 0.5)),lowerSignal ? '*' : '-');
    if (upper > 0) place(band,30 + std::min(30.0,std::floor(30 * (upper / threshold) + 0.5)),upperSignal ? '*' : '+');
    return band;
}

std::string widthBand(double scale, double width, double value, double center, bool signalled) {
    std::string band(61,'.');
    double edge = std::min(30.0,std::floor(30 * (width / scale) + 0.5));
    place(band,30,'|'); place(band,30 - edge,':'); place(band,30 + edge,':');
    double deviation = (value - center) / scale;
    place(band,30 + std::floor(30 * deviation + 0.5),signalled ? '*' : 'o');
    return band;
}

std::string standardBand(double z, bool ok) {
    std::string band = framed(30);
    place(band,30 + std::floor(10 * z + 0.5),ok ? 'o' : '*');
    return band;
}
