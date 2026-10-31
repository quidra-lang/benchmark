import java.util.*;
final class Bus {
    record Eviction(int block, List<String> copies, boolean dirty) {}
    static final class Transaction {
        int number, start, core, block, snoopHits, invalidations;
        Integer supplier;
        String kind, l2, source;
        boolean flush;
        List<String> snoop = new ArrayList<>();
        Eviction eviction;
        Transaction(int number, int start, int core, String kind, int block) {
            this.number = number;
            this.start = start;
            this.core = core;
            this.kind = kind;
            this.block = block;
        }
    }
    int latency, free, wait;
    List<Transaction> transactions = new ArrayList<>();
    Bus(int latency) { this.latency = latency; }
    Transaction assign(int core, String kind, int block, int requested) {
        int start = Math.max(requested, free);
        wait += start - requested;
        free = start + latency;
        Transaction transaction =
            new Transaction(transactions.size() + 1, start, core, kind, block);
        transactions.add(transaction);
        return transaction;
    }
    String line(Transaction tx, int lineSize) {
        String output = tx.number + " " + tx.start + " c" + tx.core + " " + tx.kind + " " +
                        ConfigIo.hexAddress(tx.block * lineSize);
        if (tx.kind.equals("WB"))
            return output;
        output += " snoop " + (tx.snoop.isEmpty() ? "none" : String.join(" ", tx.snoop));
        if (tx.kind.equals("BusUpgr"))
            return output;
        if (tx.kind.equals("BusRd") || tx.kind.equals("BusRdX"))
            output += " data " + tx.source;
        output += " l2 " + tx.l2;
        if (tx.eviction != null) {
            Eviction e = tx.eviction;
            output += " evict " + ConfigIo.hexAddress(e.block() * lineSize) + " " +
                      (e.copies().isEmpty() ? "none" : String.join(" ", e.copies())) + " " +
                      (e.dirty() ? "dirty" : "clean");
        }
        return output;
    }
}
