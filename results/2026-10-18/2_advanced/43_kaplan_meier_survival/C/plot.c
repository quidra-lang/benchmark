#include "survival.h"
Lines curve_plot(const KMRows *curves, const int *maximums, const Params *params) {
    int width = params->plot_width, height = params->plot_height, time = params->plot_time;
    unsigned *cells = calloc((size_t)height * width, sizeof(unsigned));
    for (int group = 0; group < params->groups.count; ++group) {
        int previous = -1;
        for (int column = 0; column < width; ++column) {
            int t = column * (time / width);
            if (t > maximums[group])
                break;
            double survival = row_at(&curves[group], t).survival;
            int band = (int)floor(survival * height);
            if (band > height - 1)
                band = height - 1;
            cells[band * width + column] |= 1u << group;
            if (previous >= 0 && previous - 1 > band)
                for (int q = band + 1; q < previous; ++q)
                    cells[q * width + column] |= 1u << group;
            previous = band;
        }
    }
    Lines out = {0};
    line_push(&out, format("km_plot width %d height %d time %d", width, height, time));
    char *legend = text("legend");
    for (int group = 0; group < params->groups.count; ++group) {
        char *next = format("%s %c %s", legend, 'A' + group, params->groups.data[group]);
        free(legend);
        legend = next;
    }
    line_push(&out, legend);
    char *rule = resize(NULL, (size_t)width + 1);
    memset(rule, '-', (size_t)width);
    rule[width] = 0;
    char *border = format("   +%s+", rule);
    free(rule);
    line_push(&out, text(border));
    for (int band = height - 1; band >= 0; --band) {
        char *marks = resize(NULL, (size_t)width + 1);
        for (int column = 0; column < width; ++column) {
            unsigned mask = cells[band * width + column];
            if (!mask)
                marks[column] = ' ';
            else if ((mask & (mask - 1)) != 0)
                marks[column] = '*';
            else {
                int group = 0;
                while ((mask >> group) != 1)
                    ++group;
                marks[column] = (char)('A' + group);
            }
        }
        marks[width] = 0;
        line_push(&out, format("%3d|%s|", 100 * band / height, marks));
        free(marks);
    }
    line_push(&out, border);
    line_push(&out, format("time 0 to %d days, %d days per column", time, time / width));
    free(cells);
    return out;
}
