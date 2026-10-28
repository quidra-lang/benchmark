#include "scheduler.h"
char *read_line(FILE *file) {
    size_t length = 0, capacity = 128;
    char *line = malloc(capacity);
    int c;
    while ((c = fgetc(file)) != EOF && c != '\n') {
        if (length + 1 == capacity) {
            capacity *= 2;
            line = realloc(line, capacity);
        }
        line[length++] = (char)c;
    }
    if (c == EOF && !length) {
        free(line);
        return NULL;
    }
    line[length] = 0;
    return line;
}
char *notation(Operation op) {
    char *result = malloc(32);
    snprintf(result, 32, "J%d-%d", op.job, op.index);
    return result;
}
Instance read_instance(void) {
    Instance data = {0};
    FILE *input = fopen("input/instance.txt", "r");
    char *line = read_line(input);
    int lines;
    sscanf(line, "%d %d", &lines, &data.machines);
    free(line);
    for (int m = 0; m < data.machines; ++m)
        data.machine[m].head = data.machine[m].tail = 1000000;
    for (int number = 1; number <= lines; ++number) {
        line = read_line(input);
        int seen[10] = {0}, machines[12], durations[12], count = 0;
        char message[128] = {0};
        for (char *token = strtok(line, " "); token; token = strtok(NULL, " ")) {
            int machine, duration;
            sscanf(token, "%d:%d", &machine, &duration);
            ++count;
            if (machine < 1 || machine > data.machines)
                snprintf(message, sizeof message, "unknown machine %d", machine);
            else if (duration < 1 || duration > 99)
                snprintf(message, sizeof message, "bad duration %d", duration);
            else if (seen[machine - 1])
                snprintf(message, sizeof message, "repeated machine %d", machine);
            if (message[0]) {
                char *error = malloc(192);
                snprintf(error, 192, "job %d operation %d: %s", number, count, message);
                data.errors[data.error_count++] = error;
                break;
            }
            seen[machine - 1] = 1;
            machines[count - 1] = machine - 1;
            durations[count - 1] = duration;
        }
        free(line);
        if (message[0])
            continue;
        Job *job = &data.jobs[data.job_count++];
        job->number = number;
        for (int i = 0; i < count; ++i)
            job->work += durations[i];
        int head = 0;
        for (int i = 0; i < count; ++i) {
            int id = data.count++;
            Operation op = {number,
                            i + 1,
                            machines[i],
                            durations[i],
                            head,
                            job->work - head - durations[i],
                            i ? id - 1 : -1,
                            i + 1 < count ? id + 1 : -1};
            data.operations[id] = op;
            job->operations.ids[job->operations.count++] = id;
            head += op.duration;
            Machine *m = &data.machine[op.machine];
            ++m->count;
            m->load += op.duration;
            if (op.head < m->head)
                m->head = op.head;
            if (op.tail < m->tail)
                m->tail = op.tail;
        }
        data.work += job->work;
    }
    fclose(input);
    for (int m = 0; m < data.machines; ++m)
        data.machine[m].bound = data.machine[m].head + data.machine[m].load + data.machine[m].tail;
    return data;
}
