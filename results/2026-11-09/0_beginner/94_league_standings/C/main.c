#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    const char *name;
    int played, wins, draws, losses, gf, ga, points;
} Team;

void record(Team *t, int gf, int ga) {
    t->played++;
    t->gf += gf;
    t->ga += ga;
    if (gf > ga) {
        t->wins++;
        t->points += 3;
    } else if (gf == ga) {
        t->draws++;
        t->points++;
    } else {
        t->losses++;
    }
}

int compare(const void *a, const void *b) {
    const Team *x = a, *y = b;
    if (x->points != y->points)
        return y->points - x->points;
    if (x->gf - x->ga != y->gf - y->ga)
        return (y->gf - y->ga) - (x->gf - x->ga);
    if (x->gf != y->gf)
        return y->gf - x->gf;
    return strcmp(x->name, y->name);
}

int main(void) {
    const char *names[] = {"Lions", "Tigers", "Eagles", "Sharks", "Wolves", "Bears"};
    const char *matches[] = {
        "Lions 0-3 Bears", "Tigers 2-2 Wolves", "Eagles 4-0 Sharks", "Bears 0-1 Sharks", "Wolves 2-1 Eagles",
        "Lions 0-1 Tigers", "Tigers 3-3 Bears", "Eagles 2-2 Lions", "Sharks 2-2 Wolves", "Bears 3-1 Wolves",
        "Lions 2-0 Sharks", "Tigers 2-1 Eagles", "Eagles 1-0 Bears", "Sharks 2-0 Tigers", "Wolves 2-1 Lions"};
    Team teams[6];
    for (int i = 0; i < 6; i++)
        teams[i] = (Team){.name = names[i]};
    for (int i = 0; i < 15; i++) {
        char home[32], away[32];
        int h, a;
        sscanf(matches[i], "%31s %d-%d %31s", home, &h, &a, away);
        int x = 0, y = 0;
        while (strcmp(teams[x].name, home))
            x++;
        while (strcmp(teams[y].name, away))
            y++;
        record(&teams[x], h, a);
        record(&teams[y], a, h);
    }
    qsort(teams, 6, sizeof(Team), compare);
    for (int i = 0; i < 6; i++) {
        Team t = teams[i];
        int gd = t.gf - t.ga;
        printf("%d. %s P=%d W=%d D=%d L=%d GF=%d GA=%d GD=%s%d Pts=%d\n", i + 1, t.name, t.played, t.wins,
            t.draws, t.losses, t.gf, t.ga, gd > 0 ? "+" : "", gd, t.points);
    }
    return 0;
}
