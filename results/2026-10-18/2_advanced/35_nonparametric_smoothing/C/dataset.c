#include "smoothing.h"
int hundredths(const char *text) {
    char digits[64];
    size_t n = 0;
    for (size_t i = 0; text[i]; ++i)
        if (text[i] != '.')
            digits[n++] = text[i];
    digits[n] = 0;
    return (int)strtol(digits, NULL, 10);
}
static int point_compare(const void *pa, const void *pb) {
    const int *a = pa, *b = pb;
    return a[0] < b[0] ? -1 : a[0] > b[0];
}
Input *read_input(void) {
    Input *out = allocate(1, sizeof *out);
    Lines lines = read_lines("input/series.csv");
    for (size_t i = 1; i < lines.len; ++i) {
        Lines fields = split(lines.data[i], ',');
        int s = 0;
        while (s < out->series_count && strcmp(out->series[s].name, fields.data[0]))
            ++s;
        if (s == out->series_count)
            out->series[out->series_count++].name = fields.data[0];
        Data *data = &out->series[s].data;
        int index = data->n++;
        data->x[index] = hundredths(fields.data[1]);
        data->y[index] = hundredths(fields.data[2]);
    }
    for (int s = 0; s < out->series_count; ++s) {
        Data *data = &out->series[s].data;
        int points[200][2];
        for (int i = 0; i < data->n; ++i) {
            points[i][0] = data->x[i];
            points[i][1] = data->y[i];
        }
        qsort(points, data->n, sizeof *points, point_compare);
        for (int i = 0; i < data->n; ++i) {
            data->x[i] = points[i][0];
            data->y[i] = points[i][1];
            data->real_x[i] = (double)points[i][0] / 100;
            data->real_y[i] = (double)points[i][1] / 100;
        }
    }
    lines = read_lines("input/test_points.csv");
    for (size_t i = 1; i < lines.len; ++i) {
        Lines fields = split(lines.data[i], ',');
        out->tests[out->test_count++] = (TestPoint){fields.data[0], hundredths(fields.data[1])};
    }
    lines = read_lines("input/params.txt");
    for (int i = 0; i < 17; ++i) {
        Lines words = split(lines.data[i], ' ');
        for (size_t j = 1; j < words.len; ++j)
            line_add(&out->params.rows[i], "%s", words.data[j]);
    }
    return out;
}
