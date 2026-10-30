import java.util.*;
final class Protocol {
    static final Set<String> DIRTY = Set.of("M", "O");
    record Request(String transaction, String state) {}
    record Snoop(String state, boolean supply, boolean flush) {}
    static Request requester(String protocol, String old, String op, boolean otherHasLine) {
        if (protocol.equals("VI"))
            return op.equals("R") ? new Request(old.equals("I") ? "BusRd" : null, "V")
                                  : new Request("BusWr", old.equals("I") ? "I" : "V");
        if (old.equals("I"))
            return op.equals("W")
                ? new Request("BusRdX", "M")
                : new Request("BusRd", !protocol.equals("MSI") && !otherHasLine ? "E" : "S");
        if (op.equals("R"))
            return new Request(null, old);
        return old.equals("M") || old.equals("E") ? new Request(null, "M")
                                                  : new Request("BusUpgr", "M");
    }
    static Snoop snoop(String protocol, String old, String transaction) {
        if (protocol.equals("VI"))
            return new Snoop(transaction.equals("BusRd") ? "V" : "I", false, false);
        if (transaction.equals("BusRd")) {
            if (old.equals("M"))
                return protocol.equals("MOESI") ? new Snoop("O", true, false)
                                                : new Snoop("S", true, true);
            if (old.equals("O"))
                return new Snoop("O", true, false);
            return new Snoop("S", false, false);
        }
        return new Snoop("I", transaction.equals("BusRdX") && DIRTY.contains(old), false);
    }
}
