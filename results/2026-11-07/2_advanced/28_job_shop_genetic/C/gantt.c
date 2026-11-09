#include "scheduler.h"
static char *row(const Instance *data, const Schedule *schedule, Sequence operations, const bool *critical,
                 const char *label, bool job_row, int scale, int columns) {
    char *text = malloc((size_t)columns + 16);
    snprintf(text, 16, "%-4s |", label);
    for (int c = 0; c < columns; ++c) {
        int overlap = 0, selected = -1;
        for (int i = 0; i < operations.count; ++i) {
            int id = operations.ids[i],
                end = schedule->finish[id] < (c + 1) * scale ? schedule->finish[id] : (c + 1) * scale,
                start = schedule->start[id] > c * scale ? schedule->start[id] : c * scale,
                value = end - start;
            if (value > overlap || (value == overlap && value > 0 &&
                                    (selected < 0 || schedule->start[id] < schedule->start[selected]))) {
                overlap = value;
                selected = id;
            }
        }
        char mark = '.';
        if (selected >= 0) {
            Operation op = data->operations[selected];
            mark = job_row ? (char)('0' + (op.machine + 1) % 10)
                           : (char)((critical[selected] ? 'a' : 'A') + op.job - 1);
        }
        text[6 + c] = mark;
    }
    text[6 + columns] = '|';
    text[7 + columns] = 0;
    return text;
}
Chart gantt(const Instance *data, const Schedule *schedule, const Sequence *path, int width) {
    Chart chart = {0};
    int multipliers[3] = {1, 2, 5};
    for (int power = 1; !chart.scale; power *= 10)
        for (int i = 0; i < 3; ++i) {
            int scale = power * multipliers[i];
            if ((schedule->makespan + scale - 1) / scale <= width) {
                chart.scale = scale;
                break;
            }
        }
    chart.columns = (schedule->makespan + chart.scale - 1) / chart.scale;
    char *time = malloc((size_t)chart.columns + 32);
    memset(time, ' ', (size_t)chart.columns + 31);
    memcpy(time, "time", 4);
    int length = 4;
    for (int c = 0; c < chart.columns; c += 10) {
        char value[32];
        int size = snprintf(value, sizeof value, "%d", c * chart.scale);
        memcpy(time + 6 + c, value, (size_t)size);
        length = 6 + c + size;
    }
    time[length] = 0;
    chart.lines[chart.count++] = time;
    char *rule = malloc((size_t)chart.columns + 7);
    memset(rule, ' ', 6);
    for (int c = 0; c < chart.columns; ++c)
        rule[6 + c] = c % 10 ? '-' : '+';
    rule[6 + chart.columns] = 0;
    chart.lines[chart.count++] = rule;
    bool critical[100] = {0};
    for (int i = 0; i < path->count; ++i)
        critical[path->ids[i]] = true;
    for (int m = 0; m < data->machines; ++m) {
        char label[16];
        snprintf(label, sizeof label, "M%d", m + 1);
        chart.lines[chart.count++] = row(data, schedule, schedule->order.machines[m], critical, label, false,
                                         chart.scale, chart.columns);
    }
    char *busy = malloc((size_t)chart.columns + 8);
    memcpy(busy, "busy |", 6);
    for (int c = 0; c < chart.columns; ++c) {
        int count = 0;
        for (int i = 0; i < data->count; ++i)
            if (schedule->start[i] <= c * chart.scale && c * chart.scale < schedule->finish[i])
                ++count;
        busy[6 + c] = count == 10 ? 'X' : (char)('0' + count);
    }
    busy[6 + chart.columns] = '|';
    busy[7 + chart.columns] = 0;
    chart.lines[chart.count++] = busy;
    for (int j = 0; j < data->job_count; ++j) {
        char label[16];
        snprintf(label, sizeof label, "J%d", data->jobs[j].number);
        chart.lines[chart.count++] =
            row(data, schedule, data->jobs[j].operations, critical, label, true, chart.scale, chart.columns);
    }
    return chart;
}
