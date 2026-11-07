#include "survival.hpp"
Lines curve_plot(const std::vector<std::vector<KMRow>> &curves, const std::vector<int> &maximums,
                 const Params &params) {
    const int width = params.plot_width, height = params.plot_height, time = params.plot_time;
    std::vector<std::vector<unsigned>> cells(height, std::vector<unsigned>(width));
    for (std::size_t group = 0; group < curves.size(); ++group) {
        int previous = -1;
        for (int column = 0; column < width; ++column) {
            const int t = column * (time / width);
            if (t > maximums[group])
                break;
            const double survival = row_at(curves[group], t).survival;
            const int band = std::min(height - 1, int(std::floor(survival * height)));
            cells[band][column] |= 1u << group;
            if (previous >= 0 && previous - 1 > band)
                for (int q = band + 1; q < previous; ++q)
                    cells[q][column] |= 1u << group;
            previous = band;
        }
    }
    Lines out = {"km_plot width " + std::to_string(width) + " height " + std::to_string(height) + " time " +
                 std::to_string(time)};
    std::string legend = "legend";
    for (std::size_t group = 0; group < curves.size(); ++group)
        legend += " " + std::string(1, char('A' + group)) + " " + params.groups[group];
    out.push_back(legend);
    const std::string border = "   +" + std::string(width, '-') + "+";
    out.push_back(border);
    for (int band = height - 1; band >= 0; --band) {
        std::ostringstream row;
        row << std::setw(3) << (100 * band / height) << '|';
        for (unsigned mask : cells[band]) {
            if (mask == 0)
                row << ' ';
            else if ((mask & (mask - 1)) != 0)
                row << '*';
            else {
                int group = 0;
                while ((mask >> group) != 1)
                    ++group;
                row << char('A' + group);
            }
        }
        row << '|';
        out.push_back(row.str());
    }
    out.push_back(border);
    out.push_back("time 0 to " + std::to_string(time) + " days, " + std::to_string(time / width) +
                  " days per column");
    return out;
}
