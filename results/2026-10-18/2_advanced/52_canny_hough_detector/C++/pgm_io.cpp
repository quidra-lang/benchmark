#include "detector.hpp"
Input load() {
    Input out;
    std::ifstream image("input/image.pgm");
    std::string marker;
    int width, height, maximum;
    image >> marker >> width >> height >> maximum;
    out.image = Image(width, height);
    for (I &value : out.image.data)
        image >> value;
    std::ifstream trig("input/trig.txt");
    for (auto &row : out.trig) {
        int angle;
        trig >> angle >> row[0] >> row[1];
    }
    std::ifstream parameters("input/params.txt");
    Params &p = out.params;
    parameters >> marker >> p.ks >> marker;
    p.kernel.resize(p.ks * p.ks);
    for (I &value : p.kernel)
        parameters >> value;
    for (I *value : {&p.divisor,
                     &p.low,
                     &p.high,
                     &p.r_min,
                     &p.r_max,
                     &p.circle_percent,
                     &p.circle_count,
                     &p.rho_step,
                     &p.vote_threshold,
                     &p.line_count,
                     &p.tolerance,
                     &p.max_gap,
                     &p.min_length,
                     &p.junction_distance,
                     &p.junction_angle,
                     &p.angle_tolerance,
                     &p.square_tolerance,
                     &p.margin,
                     &p.harris_window,
                     &p.harris_threshold,
                     &p.corner_count,
                     &p.match_distance,
                     &p.overlay_divisor})
        parameters >> marker >> *value;
    return out;
}
void write_pgm(const std::string &name, const Image &image) {
    std::ofstream out("output/" + name);
    out << "P2\n" << image.width << ' ' << image.height << "\n255\n";
    for (int y = 0; y < image.height; ++y) {
        for (int x = 0; x < image.width; ++x)
            out << (x ? " " : "") << image.at({x, y});
        out << '\n';
    }
}
