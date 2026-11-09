#include "seismic.hpp"
void load(std::vector<Station> &stations, Params &p) {
    std::ifstream geometry("input/stations.csv");
    std::string line;
    std::getline(geometry, line);
    while (std::getline(geometry, line)) {
        std::replace(line.begin(), line.end(), ',', ' ');
        std::istringstream row(line);
        Station s;
        row >> s.code >> s.x >> s.y >> s.elevation;
        stations.push_back(std::move(s));
    }
    std::ifstream waves("input/waveforms.txt");
    for (Station &s : stations) {
        std::string marker, code;
        int count;
        waves >> marker >> code >> s.start >> count;
        s.samples.resize(count);
        for (I &value : s.samples)
            waves >> value;
    }
    std::ifstream parameters("input/params.txt");
    std::string key;
    parameters >> key >> p.sw >> key >> p.lw >> key >> p.on_p >> p.on_q >> key >> p.off_p >> p.off_q >> key >>
        p.min_duration >> key >> p.noise >> key >> p.aw >> key >> p.clip >> key >> p.window >> key >>
        p.minimum >> key >> p.velocity;
    for (auto *range : {&p.gx, &p.gy, &p.gz}) {
        parameters >> key;
        for (I &value : *range)
            parameters >> value;
    }
    parameters >> key >> p.limit;
    for (auto *limits : {&p.qa, &p.qb}) {
        parameters >> key;
        for (double &value : *limits)
            parameters >> value;
    }
    parameters >> key;
    for (double &value : p.cluster)
        parameters >> value;
    for (auto *coefficients : {&p.local, &p.duration}) {
        parameters >> key;
        for (double &value : *coefficients)
            parameters >> value;
    }
    parameters >> key;
    for (I &value : p.area)
        parameters >> value;
    for (auto *size : {&p.map_size, &p.section}) {
        parameters >> key;
        for (I &value : *size)
            parameters >> value;
    }
    parameters >> key;
    for (I &value : p.timeline)
        parameters >> value;
}
