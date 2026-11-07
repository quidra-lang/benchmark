#include "simulation.h"
I random_draw(Random *random) {
    random->state = 48271 * random->state % 2147483647;
    ++random->draws;
    return random->state;
}
int process_index(const Topology *topology, const char *name) {
    for (int i = 0; i < topology->count; ++i)
        if (strcmp(topology->names[i], name) == 0)
            return i;
    return -1;
}
Topology read_topology(void) {
    Topology out = {0};
    Lines lines = read_lines("input/topology.txt");
    char *copy = format("%s", lines.data[0]);
    char *word = strtok(copy, " ");
    while ((word = strtok(NULL, " ")))
        strcpy(out.names[out.count++], word);
    for (int i = 1; i < lines.count; ++i) {
        char source[7], destination[7], type[8];
        int minimum, maximum;
        int fields = sscanf(lines.data[i], "CHANNEL %6s %6s %7s %d %d", source, destination, type,
                            &minimum, &maximum);
        if (fields == 4)
            maximum = minimum;
        int a = process_index(&out, source), b = process_index(&out, destination);
        Channel *channel = &out.channels[a][b];
        channel->source = a;
        channel->destination = b;
        channel->fifo = strcmp(type, "FIFO") == 0;
        channel->minimum = minimum;
        channel->maximum = maximum;
    }
    return out;
}
void dispatch(Channel *channel, int time, bool marker, const I *clock, int count, Random *random,
              int *sequence, int *arrival) {
    *sequence = ++channel->sequence;
    int delay = channel->minimum +
                (channel->minimum == channel->maximum
                     ? 0
                     : (int)(random_draw(random) % (channel->maximum - channel->minimum + 1)));
    *arrival = time + delay;
    if (channel->fifo && *arrival < channel->last_arrival)
        *arrival = channel->last_arrival;
    if (*arrival > channel->last_arrival)
        channel->last_arrival = *arrival;
    if (*arrival - time > channel->max_delay)
        channel->max_delay = *arrival - time;
    if (marker)
        ++channel->markers;
    else {
        ++channel->messages;
        for (int i = 0; i < count; ++i) {
            channel->entries += clock[i] != channel->previous[i];
            channel->previous[i] = clock[i];
        }
    }
}
char *delay_text(Channel channel) {
    return channel.minimum == channel.maximum ? format("%d", channel.minimum)
                                              : format("%d-%d", channel.minimum, channel.maximum);
}
