using System;
using System.Collections.Generic;
public sealed class Bus {
    public record Eviction(int block, List<string> copies, bool dirty);
    public sealed class Transaction {
        public int number, start, core, block, snoopHits, invalidations;
        public int? supplier;
        public string kind, l2, source;
        public bool flush;
        public List<string> snoop = new();
        public Eviction eviction;
        public Transaction(int number, int start, int core, string kind, int block) {
            this.number = number;
            this.start = start;
            this.core = core;
            this.kind = kind;
            this.block = block;
        }
    }
    public int latency, free, wait;
    public List<Transaction> transactions = new();
    public Bus(int latency) { this.latency = latency; }
    public Transaction Assign(int core, string kind, int block, int requested) {
        int start = Math.Max(requested, free);
        wait += start - requested;
        free = start + latency;
        Transaction transaction = new(transactions.Count + 1, start, core, kind, block);
        transactions.Add(transaction);
        return transaction;
    }
    public string LogLine(Transaction tx, int lineSize) {
        string output = tx.number + " " + tx.start + " c" + tx.core + " " + tx.kind + " " +
                        ConfigIo.HexAddress(tx.block * lineSize);
        if (tx.kind == "WB")
            return output;
        output += " snoop " + (tx.snoop.Count == 0 ? "none" : string.Join(" ", tx.snoop));
        if (tx.kind == "BusUpgr")
            return output;
        if (tx.kind == "BusRd" || tx.kind == "BusRdX")
            output += " data " + tx.source;
        output += " l2 " + tx.l2;
        if (tx.eviction != null) {
            Eviction e = tx.eviction;
            output += " evict " + ConfigIo.HexAddress(e.block * lineSize) + " " +
                      (e.copies.Count == 0 ? "none" : string.Join(" ", e.copies)) + " " +
                      (e.dirty ? "dirty" : "clean");
        }
        return output;
    }
}
