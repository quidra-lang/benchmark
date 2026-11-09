using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public sealed class Network {
    public static readonly string[] TYPES = { "RV", "RVR", "AE", "AER", "TN" },
                                    FIELDS = { "sent", "delivered", "inflight", "partition",
                                               "rule", "loss",      "down" };
    public interface Payload {}
    public record VoteRequest(int lastIndex, int lastTerm) : Payload {}
    public record VoteResponse(bool granted) : Payload {}
    public record AppendRequest(int previous, int previousTerm, List<RaftNode.Entry> entries,
                                int commit)
        : Payload {}
    public record AppendResponse(bool success, int match) : Payload {}
    public record Immediate() : Payload {}
    public record Message(string kind, int source, int destination, int term, Payload data) {}
    public record Drop(string kind, int start, int end) {}
    public record Scheduled(int arrival, int source, int serial, Message message) {}
    public sealed class Link {
        public int delay, loss, passed;
        public List<Drop> drops = new();
        public int[] stats = new int[7];
        public Link(int delay) { this.delay = delay; }
    }
    public readonly int count;
    public Link[][] links;
    public int[] groups, total = new int[7];
    public int[][] byType = Enumerable.Range(0, 5)
                                .Select(
                                    _ => new int[7])
                                .ToArray();
    public int serial;
    public PriorityQueue<Scheduled, (int arrival, int source, int serial)> queue = new();
    public Network(int count) {
        this.count = count;
        links = Enumerable.Range(0, count + 1)
                    .Select(
                        _ => new Link[count + 1])
                    .ToArray();
        groups = new int[count + 1];
        List<string> lines = File.ReadAllLines(Path.Combine("input", "network.txt")).ToList();
        int defaultDelay = int.Parse(lines[0].Split(" ")[1]);
        for (int a = 1; a <= count; a++)
            for (int b = 1; b <= count; b++)
                if (a != b)
                    links[a][b] = new Link(defaultDelay);
        foreach (string line in lines.GetRange(1, lines.Count - 1)) {
            string[] w = line.Split(" ");
            for (int a = 1; a <= count; a++)
                for (int b = 1; b <= count; b++)
                    if (a != b && (w[1].Equals("*") || int.Parse(w[1]) == a) &&
                        (w[2].Equals("*") || int.Parse(w[2]) == b)) {
                        Link link = links[a][b];
                        switch (w[0]) {
                        case "DELAY":
                            link.delay = int.Parse(w[3]);
                            break;
                        case "LOSS":
                            link.loss = int.Parse(w[3]);
                            break;
                        default:
                            link.drops.Add(new Drop(w[3], int.Parse(w[4]), int.Parse(w[5])));
                            break;
                        }
                    }
        }
    }
    public void Partition(List<List<int>> partitions) {
        for (int i = 0; i < partitions.Count; i++)
            foreach (int node in partitions[i])
                groups[node] = i;
    }
    public void Heal() { Array.Fill(groups, 0); }
    public bool Separated(int a, int b) { return groups[a] != groups[b]; }
    public int TypeIndex(string kind) {
        for (int i = 0; i < TYPES.Length; i++)
            if (TYPES[i].Equals(kind))
                return i;
        throw new ArgumentException();
    }
    public void Count(Message message, int field, int amount) {
        total[field] += amount;
        byType[TypeIndex(message.kind)][field] += amount;
        links[message.source][message.destination].stats[field] += amount;
    }
    public void Send(int time, int source, int destination, int term, string kind, Payload data) {
        Message message = new Message(kind, source, destination, term, data);
        serial++;
        Count(message, 0, 1);
        Link link = links[source][destination];
        if (Separated(source, destination)) {
            Count(message, 3, 1);
            return;
        }
        foreach (Drop drop in link.drops)
            if ((drop.kind.Equals(kind) || drop.kind.Equals("ALL")) && drop.start <= time &&
                time <= drop.end) {
                Count(message, 4, 1);
                return;
            }
        link.passed++;
        if (link.loss > 0 && link.passed % link.loss == 0) {
            Count(message, 5, 1);
            return;
        }
        Count(message, 2, 1);
        queue.Enqueue(new Scheduled(time + link.delay, source, serial, message),
                      (time + link.delay, source, serial));
    }
    public List<Message> Arrivals(int time) {
        List<Message> result = new();
        while (queue.Count != 0 && queue.Peek().arrival == time) {
            Message message = queue.Dequeue().message;
            Count(message, 2, -1);
            result.Add(message);
        }
        return result;
    }
    public bool Deliver(Message message, bool up) {
        if (!up) {
            Count(message, 6, 1);
            return false;
        }
        if (Separated(message.source, message.destination)) {
            Count(message, 3, 1);
            return false;
        }
        Count(message, 1, 1);
        return true;
    }
}
