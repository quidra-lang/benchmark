#include "railway.hpp"

static Route *clearedRoute(Signal *signal, const Interlocking &interlocking) {
    for (const std::unique_ptr<Route> &route : interlocking.routes) {
        if (route->start != signal || route->state != RouteState::Locked)
            continue;
        bool clear = true;
        for (const Requirement &requirement : route->requirements())
            clear = clear && requirement.point->detected() &&
                    requirement.point->position == requirement.position;
        for (Section *section : route->sections)
            clear = clear && !section->occupied();
        for (Section *section : route->overlap)
            clear = clear && !section->occupied();
        if (clear)
            return route.get();
    }
    return nullptr;
}
std::map<Signal *, Aspect> signalAspects(const Layout &layout, const Interlocking &interlocking) {
    std::map<Signal *, Route *> cleared;
    for (const std::unique_ptr<Signal> &signal : layout.signals)
        cleared[signal.get()] = clearedRoute(signal.get(), interlocking);
    std::map<Signal *, Aspect> result;
    for (const std::unique_ptr<Signal> &signal : layout.signals) {
        Aspect aspect = Aspect::Red;
        Route *route = cleared[signal.get()];
        if (route) {
            std::map<std::string, Signal *>::const_iterator finish =
                layout.signalNames.find(route->finish);
            if (finish != layout.signalNames.end())
                aspect = cleared[finish->second] ? Aspect::Green : Aspect::Yellow;
            else
                aspect = layout.bufferNames.count(route->finish) ? Aspect::Yellow : Aspect::Green;
        }
        result[signal.get()] = aspect;
    }
    return result;
}
