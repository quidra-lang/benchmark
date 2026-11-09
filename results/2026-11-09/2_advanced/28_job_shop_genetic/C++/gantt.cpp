#include "scheduler.hpp"
Chart gantt(const Instance &data, const Schedule &schedule, const std::vector<int> &path, int width) {
    Chart chart{1, 0, {}};
    bool found = false;
    for (int power = 1; !found; power *= 10) {
        for (int multiplier : {1, 2, 5}) {
            const int scale = power * multiplier;
            if ((schedule.makespan + scale - 1) / scale <= width) {
                chart.scale = scale;
                found = true;
                break;
            }
        }
    }
    chart.columns = (schedule.makespan + chart.scale - 1) / chart.scale;
    std::string time = "time";
    for (int column = 0; column < chart.columns; column += 10) {
        time.resize(6 + column, ' ');
        time += std::to_string(column * chart.scale);
    }
    chart.lines.push_back(time);
    std::string rule(6, ' ');
    for (int column = 0; column < chart.columns; ++column)
        rule += column % 10 ? '-' : '+';
    chart.lines.push_back(rule);
    const std::set<int> critical(path.begin(), path.end());
    auto row = [&](const std::string &label, const std::vector<int> &operations, bool job_row) {
        std::ostringstream result;
        result << std::left << std::setw(4) << label << " |";
        for (int column = 0; column < chart.columns; ++column) {
            int overlap = 0, selected = -1;
            for (int id : operations) {
                const int value = std::min(schedule.finish[id], (column + 1) * chart.scale) -
                                  std::max(schedule.start[id], column * chart.scale);
                if (value > overlap || (value == overlap && value > 0 &&
                                        (selected < 0 || schedule.start[id] < schedule.start[selected]))) {
                    overlap = value;
                    selected = id;
                }
            }
            char mark = '.';
            if (selected >= 0) {
                const Operation &op = data.operations[selected];
                mark = job_row ? char('0' + (op.machine + 1) % 10)
                               : char((critical.count(selected) ? 'a' : 'A') + op.job - 1);
            }
            result << mark;
        }
        result << '|';
        return result.str();
    };
    for (int m = 0; m < data.machines; ++m)
        chart.lines.push_back(row("M" + std::to_string(m + 1), schedule.order[m], false));
    std::string busy = "busy |";
    for (int column = 0; column < chart.columns; ++column) {
        int count = 0;
        for (std::size_t i = 0; i < data.operations.size(); ++i)
            if (schedule.start[i] <= column * chart.scale && column * chart.scale < schedule.finish[i])
                ++count;
        busy += count == 10 ? 'X' : char('0' + count);
    }
    chart.lines.push_back(busy + '|');
    for (const Job &job : data.jobs)
        chart.lines.push_back(row("J" + std::to_string(job.number), job.operations, true));
    return chart;
}
