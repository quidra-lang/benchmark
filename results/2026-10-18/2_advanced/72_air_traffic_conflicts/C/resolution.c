#include "airspace.h"
Manoeuvres manoeuvres(Integer max_delay) {
    Manoeuvres out = {0};
    Manoeuvre item = {{{0}}, CHANGE_LEVEL, 10};
    strcpy(item.name.text, "level_up");
    Manoeuvres_append(&out, item);
    strcpy(item.name.text, "level_down");
    item.amount = -10;
    Manoeuvres_append(&out, item);
    strcpy(item.name.text, "speed_down");
    item.kind = CHANGE_SPEED;
    item.amount = 0;
    Manoeuvres_append(&out, item);
    for (Integer delay = 60; delay <= max_delay; delay += 60) {
        item.kind = CHANGE_DELAY;
        item.amount = delay;
        snprintf(item.name.text, sizeof item.name.text, "delay_%lld", (long long)delay);
        Manoeuvres_append(&out, item);
    }
    return out;
}
bool propose(const Plan *plan, const Manoeuvre *manoeuvre, const AircraftType *types,
             const Params *params, Plan *out) {
    *out = *plan;
    if (manoeuvre->kind == CHANGE_LEVEL) {
        out->offset += manoeuvre->amount;
        Integer levels[8];
        int count = flight_levels(out, levels);
        for (int i = 0; i < count; ++i)
            if (levels[i] < params->level_min || levels[i] > params->level_max)
                return false;
    } else if (manoeuvre->kind == CHANGE_SPEED) {
        out->speed = out->speed * 9 / 10;
        if (out->speed < types[out->type].minimum)
            return false;
    } else
        out->delay += manoeuvre->amount;
    return true;
}
void priority_order(int first, int second, const Plan *plans, int out[2]) {
    Integer a = plans[first].departure + plans[first].delay,
            b = plans[second].departure + plans[second].delay;
    bool lower = a > b || (a == b && strcmp(plans[first].callsign, plans[second].callsign) > 0);
    out[0] = lower ? first : second;
    out[1] = lower ? second : first;
}
