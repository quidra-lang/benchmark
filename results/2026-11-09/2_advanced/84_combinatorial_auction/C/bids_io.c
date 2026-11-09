#include "auction.h"
#include <stdlib.h>
#include <string.h>
static Words next_line(FILE *file, Input *input) {
    char *line = read_line(file);
    if (!line)
        return (Words){0};
    lines_add(&input->storage, line);
    return words(line);
}
void read_input(Input *input) {
    memset(input, 0, sizeof(*input));
    FILE *file = open_file("input/items.txt", "r");
    Words a;
    while ((a = next_line(file, input)).count) {
        input->items[input->item_count++] = (Item){a.items[0], strtoll(a.items[1], NULL, 10)};
        free(a.items);
    }
    fclose(file);
    file = open_file("input/bids.txt", "r");
    RawAuction *auction = NULL;
    while ((a = next_line(file, input)).count) {
        if (strcmp(a.items[0], "auction") == 0) {
            auction = &input->auctions[input->auction_count++];
            auction->name = a.items[1];
            for (int i = 2; i < a.count; ++i)
                auction->offered[auction->offered_count++] = a.items[i];
        } else {
            BidLine *bidder = &auction->lines[auction->line_count++];
            bidder->name = a.items[1];
            bidder->language = a.items[2];
            for (int i = 3; i < a.count; ++i)
                bidder->raw[bidder->count++] = a.items[i];
        }
        free(a.items);
    }
    fclose(file);
    file = open_file("input/single_item.txt", "r");
    Group *group = NULL;
    while ((a = next_line(file, input)).count) {
        if (strcmp(a.items[0], "lot") == 0 || strcmp(a.items[0], "slots") == 0) {
            group = &input->groups[input->group_count++];
            group->kind = a.items[0];
            group->name = a.items[1];
            for (int i = 2; i < a.count; ++i)
                group->arguments[group->argument_count++] = a.items[i];
        } else
            group->participants[group->participant_count++] = (Participant){
                a.items[1], strtoll(a.items[2], NULL, 10), strtoll(a.items[3], NULL, 10)};
        free(a.items);
    }
    fclose(file);
    file = open_file("input/params.txt", "r");
    while ((a = next_line(file, input)).count) {
        if (strcmp(a.items[0], "run") == 0) {
            for (int i = 1; i < a.count; ++i)
                input->runs[input->run_count++] = a.items[i];
        } else {
            Money value = strtoll(a.items[1], NULL, 10);
            Parameters *p = &input->parameters;
            if (strcmp(a.items[0], "max_bundle_size") == 0)
                p->max_bundle = (int)value;
            else if (strcmp(a.items[0], "max_bids_per_bidder") == 0)
                p->max_bids = (int)value;
            else if (strcmp(a.items[0], "core_max_bidders") == 0)
                p->core_max = (int)value;
            else if (strcmp(a.items[0], "saa_increment") == 0)
                p->saa_increment = (int)value;
            else if (strcmp(a.items[0], "round_cap") == 0)
                p->round_cap = (int)value;
            else if (strcmp(a.items[0], "seed") == 0)
                p->seed = value;
            else if (strcmp(a.items[0], "english_increment") == 0)
                p->english_increment = (int)value;
            else if (strcmp(a.items[0], "dutch_start") == 0)
                p->dutch_start = (int)value;
            else
                p->dutch_decrement = (int)value;
        }
        free(a.items);
    }
    fclose(file);
}
