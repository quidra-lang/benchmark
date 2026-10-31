#include "analyzer.hpp"
Input load() {
    Input out;
    std::ifstream signal("input/signal.csv");
    std::string line;
    std::getline(signal, line);
    std::replace(line.begin(), line.end(), ',', ' ');
    std::istringstream header(line);
    int count;
    header >> out.fs >> count;
    for (int i = 0; i < count; ++i) {
        std::getline(signal, line);
        std::replace(line.begin(), line.end(), ',', ' ');
        std::istringstream row(line);
        double x, y;
        row >> x >> y;
        out.signal[0].push_back(x);
        out.signal[1].push_back(y);
    }
    std::ifstream settings("input/params.txt");
    std::vector<Lines> rows;
    while (std::getline(settings, line)) {
        std::istringstream fields(line);
        Lines row;
        std::string field;
        while (fields >> field)
            row.push_back(field);
        rows.push_back(std::move(row));
    }
    Params &p = out.params;
    p.main_length = std::stoi(rows[0][1]);
    p.main_window = rows[1][1];
    p.peak_threshold = std::stod(rows[2][1]);
    p.peak_count = std::stoi(rows[3][1]);
    p.fundamental = std::stod(rows[4][1]);
    p.search = std::stoi(rows[4][2]);
    p.welch_length = std::stoi(rows[5][1]);
    p.welch_window = rows[5][2];
    p.frame_length = std::stoi(rows[6][1]);
    p.hop = std::stoi(rows[6][2]);
    p.shade = std::stoi(rows[6][3]);
    p.frame_window = rows[6][4];
    p.onset_factor = std::stod(rows[7][1]);
    p.pitch_low = std::stoi(rows[8][1]);
    p.pitch_high = std::stoi(rows[8][2]);
    p.band_low = std::stoi(rows[9][1]);
    p.band_high = std::stoi(rows[9][2]);
    p.notch_frequency = std::stoi(rows[10][1]);
    p.notch_width = std::stoi(rows[10][2]);
    p.envelope_low = std::stoi(rows[11][1]);
    p.envelope_high = std::stoi(rows[11][2]);
    p.zoom_low = std::stoi(rows[12][1]);
    p.zoom_high = std::stoi(rows[12][2]);
    p.zoom_points = std::stoi(rows[12][3]);
    for (std::size_t i = 1; i < rows[13].size(); ++i)
        p.fir.push_back(std::stod(rows[13][i]));
    p.max_lag = std::stoi(rows[14][1]);
    for (std::size_t i = 1; i < rows[15].size(); ++i)
        p.bands.push_back(std::stoi(rows[15][i]));
    p.third_low = std::stoi(rows[16][1]);
    p.third_high = std::stoi(rows[16][2]);
    p.block_length = std::stoi(rows[17][1]);
    return out;
}
