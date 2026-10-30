#include "stereo.hpp"
PGM read_pgm(const std::string &path) {
    std::ifstream input(path);
    std::string magic;
    int maximum;
    PGM out;
    input >> magic >> out.width >> out.height >> maximum;
    I value;
    while (input >> value)
        out.pixels.push_back(value);
    return out;
}
Params read_parameters() {
    std::ifstream input("input/params.txt");
    Params p;
    std::string text;
    const std::array<std::string, 3> kinds{"sad", "ssd", "census"};
    while (std::getline(input, text)) {
        std::istringstream row(text);
        std::string key;
        row >> key;
        if (key == "disparity_min")
            row >> p.minimum;
        else if (key == "disparity_max")
            row >> p.maximum;
        else if (key == "sad_windows" || key == "ssd_windows" || key == "census_windows") {
            int kind = key == "sad_windows" ? 0 : key == "ssd_windows" ? 1 : 2, value;
            while (row >> value)
                p.windows[kind].push_back(value);
        } else if (key == "texture_window")
            row >> p.texture_window;
        else if (key == "texture_threshold")
            row >> p.texture_threshold;
        else if (key == "uniqueness")
            row >> p.uniqueness;
        else if (key == "lr_max_diff")
            row >> p.lr;
        else if (key == "wta_cost" || key == "sgm_cost") {
            std::string kind;
            row >> kind;
            int value = int(std::find(kinds.begin(), kinds.end(), kind) - kinds.begin());
            if (key == "wta_cost")
                p.wta_kind = value;
            else
                p.sgm_kind = value;
        } else if (key == "sgm_window")
            row >> p.sgm_window;
        else if (key == "sgm_paths")
            row >> p.paths;
        else if (key == "p1")
            row >> p.p1;
        else if (key == "p2")
            row >> p.p2;
        else if (key == "p2_gamma")
            row >> p.gamma;
        else if (key == "speckle_size")
            row >> p.speckle_size;
        else if (key == "speckle_range")
            row >> p.speckle_range;
        else if (key == "fusion_min_votes")
            row >> p.fusion_votes;
        else if (key == "object_range")
            row >> p.object_range;
        else if (key == "object_min_size")
            row >> p.object_size;
        else if (key == "focal_length")
            row >> p.focal;
        else if (key == "baseline")
            row >> p.baseline;
        else if (key == "sample") {
            int x, y;
            row >> x >> y;
            p.samples.push_back({x, y});
        }
    }
    return p;
}
void write_pgm(const std::string &name, const PGM &image) {
    Lines out;
    line(out, "P2");
    line(out, image.width, " ", image.height);
    line(out, "255");
    for (int y = 0; y < image.height; ++y) {
        std::string row;
        for (int x = 0; x < image.width; ++x) {
            if (x)
                row += " ";
            row += std::to_string(image.pixels[y * image.width + x]);
        }
        out.push_back(row);
    }
    save(name, out);
}
void save(const std::string &name, const Lines &lines) {
    std::ofstream output("output/" + name);
    for (const std::string &line : lines)
        output << line << '\n';
}
