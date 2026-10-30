#include "airspace.hpp"
std::vector<Manoeuvre> manoeuvres(Integer max_delay) {
    std::vector<Manoeuvre> out{{"level_up", ManoeuvreKind::Level, 10},
                               {"level_down", ManoeuvreKind::Level, -10},
                               {"speed_down", ManoeuvreKind::Speed, 0}};
    for (Integer delay = 60; delay <= max_delay; delay += 60)
        out.push_back({"delay_" + std::to_string(delay), ManoeuvreKind::Delay, delay});
    return out;
}
std::optional<Plan> propose(const Plan &plan, const Manoeuvre &manoeuvre,
                            const std::vector<AircraftType> &types, const Params &params) {
    Plan changed = plan;
    if (manoeuvre.kind == ManoeuvreKind::Level) {
        changed.offset += manoeuvre.amount;
        for (Integer level : flight_levels(changed))
            if (level < params.level_min || level > params.level_max)
                return {};
    } else if (manoeuvre.kind == ManoeuvreKind::Speed) {
        changed.speed = changed.speed * 9 / 10;
        if (changed.speed < types[changed.type].minimum)
            return {};
    } else
        changed.delay += manoeuvre.amount;
    return changed;
}
std::array<int, 2> priority_order(int first, int second, const std::vector<Plan> &plans) {
    const Plan &a = plans[first], &b = plans[second];
    return std::make_pair(a.departure + a.delay, a.callsign) >
                   std::make_pair(b.departure + b.delay, b.callsign)
               ? std::array<int, 2>{first, second}
               : std::array<int, 2>{second, first};
}
