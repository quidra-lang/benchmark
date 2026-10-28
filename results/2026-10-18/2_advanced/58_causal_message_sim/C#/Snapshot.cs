using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Snapshot {
    public record LocalRecord(int time, string reason, int balance, int lamport, int[] vector,
                              List<Program.Packet> pending) {
    }
    public record Ignored(int process, int time) {
    }
    public sealed class State {
        public string name;
        public int start, complete, finished;
        public LocalRecord[] records;
        public List<List<List<Program.Packet>>> channels = new();
        public int[][] sent, accepted;
        public List<Ignored> ignored = new();
        public State(string name, int time, int size) {
            this.name = name;
            start = time;
            records = new LocalRecord[size];
            sent = Enumerable.Range(0, size)
                       .Select(
                           _ => new int[size])
                       .ToArray();
            accepted = Enumerable.Range(0, size)
                           .Select(
                               _ => new int[size])
                           .ToArray();
            for (int i = 0; i < size; i++) {
                Array.Fill(sent[i], -1);
                Array.Fill(accepted[i], -1);
                List<List<Program.Packet>> row = new();
                for (int j = 0; j < size; j++)
                    row.Add(new());
                channels.Add(row);
            }
        }
        public void RecordState(Processes.State p, int time, string reason) {
            records[p.index] =
                new LocalRecord(time, reason, p.balance, p.lamport, p.vector.ToArray(), new(p.hold));
        }
        public void Accept(int source, int destination, int time) {
            accepted[source][destination] = time;
            finished++;
            if (finished == records.Length * (records.Length - 1))
                complete = time;
        }
        public int[] Cut() {
            int[] c = new int[records.Length];
            for (int i = 0; i < c.Length; i++)
                c[i] = records[i].vector[i];
            return c;
        }
    }
    public sealed class Cut {
        public List<Program.Packet> orphans = new(), transit = new();
        public int balances, money;
    }
    public static Cut Inspect(int[] cut, Program.Simulation sim) {
        Cut result = new Cut();
        foreach (Program.Packet c in sim.copies) {
            bool sent = c.message.send.local <= cut[c.source],
                 received = c.recv != null && c.recv.local <= cut[c.destination];
            if (received && !sent)
                result.orphans.Add(c);
            if (sent && !received)
                result.transit.Add(c);
        }
        for (int i = 0; i < cut.Length; i++)
            result.balances += sim.processes[i].BalanceAt(cut[i]);
        result.money = result.balances;
        foreach (Program.Packet c in result.transit)
            result.money += c.message.amount;
        return result;
    }
    public static bool Match(List<Program.Packet> recorded, List<Program.Packet> transit) {
        if (recorded.Count != transit.Count)
            return false;
        Dictionary<Program.Packet, int> counts = new();
        foreach (Program.Packet c in recorded)
            counts[c] = counts.GetValueOrDefault(c, 0) + 1;
        foreach (Program.Packet c in transit) {
            int value = counts.GetValueOrDefault(c, 0);
            if (value == 0)
                return false;
            counts[c] = value - 1;
        }
        return true;
    }
}
