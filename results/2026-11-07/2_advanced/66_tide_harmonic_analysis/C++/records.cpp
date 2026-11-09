#include "tides.hpp"
int civil_day(int year, int month, int day) {
    year -= month <= 2;
    int era = (year >= 0 ? year : year - 399) / 400, yoe = year - era * 400,
        doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1,
        doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146097 + doe;
}
static std::array<int, 3> civil(int days) {
    int era = (days >= 0 ? days : days - 146096) / 146097, doe = days - era * 146097,
        yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365, year = yoe + era * 400,
        doy = doe - (365 * yoe + yoe / 4 - yoe / 100), mp = (5 * doy + 2) / 153,
        day = doy - (153 * mp + 2) / 5 + 1, month = mp + (mp < 10 ? 3 : -9);
    year += month <= 2;
    return {year, month, day};
}
I parse_minutes(const std::string &value) {
    int year = std::stoi(value.substr(0, 4)), month = std::stoi(value.substr(5, 2)),
        day = std::stoi(value.substr(8, 2)), hour = std::stoi(value.substr(11, 2)),
        minute = std::stoi(value.substr(14, 2));
    return I(civil_day(year, month, day)) * 1440 + hour * 60 + minute;
}
int hour(const std::string &value, int epoch_day) {
    return int((parse_minutes(value) - I(epoch_day) * 1440) / 60);
}
std::string date(int day, int epoch_day) {
    const auto parts = civil(day + epoch_day);
    std::ostringstream out;
    out << std::setfill('0') << std::setw(4) << parts[0] << '-' << std::setw(2) << parts[1] << '-'
        << std::setw(2) << parts[2];
    return out.str();
}
std::string datetime(int minutes, int epoch_day) {
    int day = minutes / 1440, remaining = minutes % 1440;
    std::ostringstream out;
    out << date(day, epoch_day) << ' ' << std::setfill('0') << std::setw(2) << remaining / 60 << ':'
        << std::setw(2) << remaining % 60;
    return out.str();
}
Input read_inputs() {
    Input out;
    Params &p = out.params;
    std::ifstream settings("input/params.txt");
    std::string text;
    while (std::getline(settings, text)) {
        std::istringstream row(text);
        std::string key;
        row >> key;
        if (key == "epoch")
            p.epoch_day = int(parse_minutes(text.substr(6)) / 1440);
        else if (key == "station") {
            Station station;
            row >> station.code;
            std::getline(row, station.name);
            station.name.erase(0, 1);
            out.stations.push_back(station);
        } else if (key == "reference")
            row >> p.reference;
        else if (key == "flat_run")
            row >> p.flat_run;
        else if (key == "spike")
            row >> p.spike_window >> p.spike_count >> p.spike_factor >> p.spike_minimum;
        else if (key == "rayleigh")
            row >> p.rayleigh;
        else if (key == "snr_min")
            row >> p.snr;
        else if (key == "top_residuals")
            row >> p.top;
        else if (key == "surge")
            row >> p.surge >> p.surge_hours;
        else if (key == "predict") {
            p.start = hour(text.substr(8, 16), p.epoch_day);
            p.length = std::stoi(text.substr(25));
        } else if (key == "grid_minutes")
            row >> p.grid;
        else if (key == "min_range")
            row >> p.min_range;
        else if (key == "correlation_lag")
            row >> p.lag;
        else if (key == "plot")
            row >> p.plot >> p.plot_hours >> p.plot_top >> p.plot_bottom >> p.plot_step;
    }
    std::ifstream constituents("input/constituents.txt");
    int count;
    constituents >> count;
    for (int i = 0; i < count; ++i) {
        Constituent item;
        constituents >> item.name >> item.speed;
        out.constituents.push_back(item);
    }
    std::ifstream observations("input/observations.csv");
    std::getline(observations, text);
    while (std::getline(observations, text)) {
        int comma = int(text.find(',')), last = int(text.rfind(','));
        std::string code = text.substr(0, comma), value = text.substr(last + 1);
        Station &station =
            *std::find_if(out.stations.begin(), out.stations.end(),
                          [&](const Station &station) { return station.code == code; });
        int t = hour(text.substr(comma + 1, last - comma - 1), p.epoch_day);
        if (value == "NA")
            station.observations[t] = std::nullopt;
        else {
            bool negative = value[0] == '-';
            std::string magnitude = negative ? value.substr(1) : value;
            int dot = int(magnitude.find('.'));
            I milli =
                1000 * std::stoll(magnitude.substr(0, dot)) + std::stoll(magnitude.substr(dot + 1));
            station.observations[t] = negative ? -milli : milli;
        }
    }
    return out;
}
