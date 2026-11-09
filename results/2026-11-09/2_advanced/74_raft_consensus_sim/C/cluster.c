#include "raft.h"
const char *status_name(RequestStatus status) {
    const char *names[5] = {"COMMITTED", "UNCOMMITTED", "LOST", "FAILED", "WAITING"};
    return names[status];
}
static int split(char *text, char **parts) {
    int count = 0;
    for (char *p = strtok(text, " \n"); p; p = strtok(NULL, " \n"))
        parts[count++] = p;
    return count;
}
void read_cluster(Input *out) {
    memset(out, 0, sizeof *out);
    FILE *file = fopen("input/cluster.txt", "r");
    char line[256], *row[32];
    int values[11], position = 0;
    while (fgets(line, sizeof line, file)) {
        int n = split(line, row);
        for (int i = 1; i < n; ++i)
            values[position++] = atoi(row[i]);
    }
    fclose(file);
    out->settings = (Settings){values[0], values[1], values[2], values[3], values[4], values[5],
                               values[6], values[7], values[8], values[9], values[10]};
    file = fopen("input/script.txt", "r");
    while (fgets(line, sizeof line, file)) {
        int n = split(line, row), time = atoi(row[0]);
        if (!strcmp(row[1], "REQUEST")) {
            Request *v = &out->requests[out->request_count++];
            v->number = out->request_count;
            v->time = v->scheduled = time;
            v->initial_destination = v->destination = atoi(row[2]);
            v->command.kind = !strcmp(row[3], "SET")   ? OP_SET
                              : !strcmp(row[3], "ADD") ? OP_ADD
                              : !strcmp(row[3], "DEL") ? OP_DELETE
                                                       : OP_GET;
            strcpy(v->command.key, row[4]);
            if (n == 6)
                v->command.value = atoi(row[5]);
        } else {
            Control *v = &out->controls[out->control_count++];
            v->time = time;
            v->kind = !strcmp(row[1], "CRASH")       ? CONTROL_CRASH
                      : !strcmp(row[1], "RESTART")   ? CONTROL_RESTART
                      : !strcmp(row[1], "PARTITION") ? CONTROL_PARTITION
                      : !strcmp(row[1], "HEAL")      ? CONTROL_HEAL
                                                     : CONTROL_TRANSFER;
            if (v->kind == CONTROL_PARTITION) {
                for (int i = 2; i < n; ++i) {
                    Group *group = &v->groups[v->group_count++];
                    for (char *p = strtok(row[i], ","); p; p = strtok(NULL, ","))
                        group->nodes[group->count++] = atoi(p);
                }
            } else if (v->kind != CONTROL_HEAL) {
                v->first = atoi(row[2]);
                if (v->kind == CONTROL_TRANSFER)
                    v->second = atoi(row[3]);
            }
        }
    }
    fclose(file);
}
