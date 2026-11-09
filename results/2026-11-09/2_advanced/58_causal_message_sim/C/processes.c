#include "simulation.h"
static Action parse_action(const Topology *topology, const char *text) {
    Action out = {0};
    char kind[10];
    sscanf(text, "%9s %8s %8s", kind, out.argument, out.tag);
    if (strcmp(kind, "LOCAL") == 0)
        out.kind = A_LOCAL;
    else if (strcmp(kind, "SEND") == 0)
        out.kind = A_SEND;
    else if (strcmp(kind, "TRANSFER") == 0) {
        out.kind = A_TRANSFER;
        sscanf(text, "%*s %*s %lld", &out.amount);
    } else if (strcmp(kind, "BROADCAST") == 0)
        out.kind = A_BROADCAST;
    else
        out.kind = A_SNAPSHOT;
    out.destination =
        strcmp(out.argument, "SENDER") == 0 ? -2 : process_index(topology, out.argument);
    return out;
}
Script *read_scripts(const Topology *topology) {
    Script *out = allocate((size_t)topology->count, sizeof(Script));
    Lines lines = read_lines("input/programs.txt");
    int current = 0;
    for (int i = 0; i < lines.count; ++i) {
        char kind[10];
        sscanf(lines.data[i], "%9s", kind);
        if (strcmp(kind, "PROCESS") == 0) {
            char name[7];
            I balance;
            sscanf(lines.data[i], "PROCESS %6s BALANCE %lld", name, &balance);
            current = process_index(topology, name);
            out[current].balance = balance;
        } else if (strcmp(kind, "AT") == 0) {
            Timed item = {0};
            int offset = 0;
            sscanf(lines.data[i], "AT %d %n", &item.start, &offset);
            if (strncmp(lines.data[i] + offset, "EVERY ", 6) == 0) {
                int more = 0;
                sscanf(lines.data[i] + offset, "EVERY %d %n", &item.period, &more);
                offset += more;
            }
            item.action = parse_action(topology, lines.data[i] + offset);
            Script *script = &out[current];
            if (script->at_count == script->at_capacity)
                grow((void **)&script->at, &script->at_capacity, sizeof(Timed));
            script->at[script->at_count++] = item;
        } else if (strcmp(kind, "ON") == 0) {
            Rule rule = {0};
            int offset = 0;
            sscanf(lines.data[i], "ON %8s %n", rule.tag, &offset);
            rule.action = parse_action(topology, lines.data[i] + offset);
            Script *script = &out[current];
            if (script->on_count == script->on_capacity)
                grow((void **)&script->on, &script->on_capacity, sizeof(Rule));
            script->on[script->on_count++] = rule;
        }
    }
    return out;
}
void initialize(Simulation *simulation) {
    for (int p = 0; p < simulation->topology.count; ++p) {
        Process *state = &simulation->processes[p];
        state->initial = state->balance = state->minimum = simulation->scripts[p].balance;
        for (int q = 0; q < simulation->topology.count; ++q)
            state->next[q] = 1;
    }
}
void schedule_actions(Simulation *simulation) {
    for (int p = 0; p < simulation->topology.count; ++p)
        for (int i = 0; i < simulation->scripts[p].at_count; ++i) {
            Timed item = simulation->scripts[p].at[i];
            for (int time = item.start; time <= simulation->params->end; time += item.period) {
                Item queued = {0};
                queued.time = time;
                queued.process = p;
                queued.packet = -1;
                queued.action = item.action;
                enqueue(simulation, queued);
                if (!item.period)
                    break;
            }
        }
}
I balance_at_cut(const Simulation *simulation, int process, I count) {
    return count ? simulation->events[simulation->processes[process].events.data[count - 1]].balance
                 : simulation->processes[process].initial;
}
