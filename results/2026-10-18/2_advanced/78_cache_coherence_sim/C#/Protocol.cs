using System.Collections.Generic;
public static class Protocol {
    public static readonly HashSet<string> DIRTY = new() { "M", "O" };
    public record Request(string transaction, string state);
    public record Snoop(string state, bool supply, bool flush);
    public static Request Requester(string protocol, string old, string op, bool otherHasLine) {
        if (protocol == "VI")
            return op == "R" ? new(old == "I" ? "BusRd" : null, "V")
                             : new("BusWr", old == "I" ? "I" : "V");
        if (old == "I")
            return op == "W" ? new("BusRdX", "M")
                             : new("BusRd", protocol != "MSI" && !otherHasLine ? "E" : "S");
        if (op == "R")
            return new(null, old);
        return old == "M" || old == "E" ? new(null, "M") : new("BusUpgr", "M");
    }
    public static Snoop OnSnoop(string protocol, string old, string transaction) {
        if (protocol == "VI")
            return new(transaction == "BusRd" ? "V" : "I", false, false);
        if (transaction == "BusRd") {
            if (old == "M")
                return protocol == "MOESI" ? new("O", true, false) : new("S", true, true);
            if (old == "O")
                return new("O", true, false);
            return new("S", false, false);
        }
        return new("I", transaction == "BusRdX" && DIRTY.Contains(old), false);
    }
}
