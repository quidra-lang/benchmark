#include "coherence.h"
const char *protocol_names[4] = {"VI", "MSI", "MESI", "MOESI"};
bool dirty(char state) { return state == 'M' || state == 'O'; }
RequestTransition requester(Protocol protocol, char old, char op, bool other) {
    if (protocol == P_VI) {
        if (op == 'R')
            return (RequestTransition){old == 'I' ? BUS_RD : TX_NONE, 'V'};
        return (RequestTransition){BUS_WR, old == 'I' ? 'I' : 'V'};
    }
    if (old == 'I') {
        if (op == 'W')
            return (RequestTransition){BUS_RDX, 'M'};
        return (RequestTransition){BUS_RD, protocol == P_MSI || other ? 'S' : 'E'};
    }
    if (op == 'R')
        return (RequestTransition){TX_NONE, old};
    if (old == 'M' || old == 'E')
        return (RequestTransition){TX_NONE, 'M'};
    return (RequestTransition){BUS_UPGR, 'M'};
}
SnoopTransition snoop(Protocol protocol, char old, TransactionKind transaction) {
    if (protocol == P_VI)
        return (SnoopTransition){transaction == BUS_RD ? 'V' : 'I', false, false};
    if (transaction == BUS_RD) {
        if (old == 'M')
            return (SnoopTransition){protocol == P_MOESI ? 'O' : 'S', true, protocol != P_MOESI};
        if (old == 'O')
            return (SnoopTransition){'O', true, false};
        return (SnoopTransition){'S', false, false};
    }
    return (SnoopTransition){'I', transaction == BUS_RDX && dirty(old), false};
}
