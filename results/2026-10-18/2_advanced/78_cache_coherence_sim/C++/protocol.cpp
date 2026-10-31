#include "coherence.hpp"
bool dirty(char state) { return state == 'M' || state == 'O'; }
RequestTransition requester(const std::string &protocol, char old, char op, bool other) {
    using T = TransactionKind;
    if (protocol == "VI") {
        if (op == 'R')
            return {old == 'I' ? T::BusRd : T::None, 'V'};
        return {T::BusWr, old == 'I' ? 'I' : 'V'};
    }
    if (old == 'I') {
        if (op == 'W')
            return {T::BusRdX, 'M'};
        return {T::BusRd, protocol == "MSI" || other ? 'S' : 'E'};
    }
    if (op == 'R')
        return {T::None, old};
    if (old == 'M' || old == 'E')
        return {T::None, 'M'};
    return {T::BusUpgr, 'M'};
}
SnoopTransition snoop(const std::string &protocol, char old, TransactionKind type) {
    using T = TransactionKind;
    if (protocol == "VI")
        return {type == T::BusRd ? 'V' : 'I', false, false};
    if (type == T::BusRd) {
        if (old == 'M')
            return {protocol == "MOESI" ? 'O' : 'S', true, protocol != "MOESI"};
        if (old == 'O')
            return {'O', true, false};
        return {'S', false, false};
    }
    return {'I', type == T::BusRdX && dirty(old), false};
}
