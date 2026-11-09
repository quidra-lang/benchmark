using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Linq;
public static class Simulator {
    public record Message(int serial, int sender, int receiver, Topology.Link link,
                          Topology.Prefix prefix, Decision.Attribute content, int arrival);
    public static readonly IComparer<Message> Order = Comparer<Message>.Create((a, b) => {
        int c = a.arrival.CompareTo(b.arrival);
        if (c == 0)
            c = a.receiver.CompareTo(b.receiver);
        if (c == 0)
            c = a.sender.CompareTo(b.sender);
        return c != 0 ? c : a.serial.CompareTo(b.serial);
    });
    public sealed class MessageQueue {
        readonly SortedSet<Message> queue = new(Order);
        int serial;
        public Message Send(int time, int sender, int receiver, Topology.Link link,
                            Topology.Prefix prefix, Decision.Attribute content) {
            Message message =
                new(++serial, sender, receiver, link, prefix, content, time + link.delay);
            queue.Add(message);
            return message;
        }
        public int? NextTime() => queue.Count == 0 ? null : queue.Min.arrival;
        public Message Take() {
            Message message = queue.Min;
            queue.Remove(message);
            return message;
        }
        public List<Message> Ordered() => queue.ToList();
        public List<Message> RemoveLink(Topology.Link link) {
            List<Message> removed =
                queue.Where(message => ReferenceEquals(message.link, link)).ToList();
            queue.RemoveWhere(message => ReferenceEquals(message.link, link));
            return removed;
        }
    }
    public sealed class Event {
        public int time;
        public string text, kind;
        public string[] fields;
        public Event(int time, string text) {
            this.time = time;
            this.text = text;
            fields = text.Split(' ');
            kind = fields[0] == "LINK" || fields[0] == "POLICY" ? fields[0] + "_" + fields[1]
                                                                : fields[0];
        }
    }
    public record Trace(int source, string address, long value);
    public record Params(Dictionary<string, int> defaults, int stepcap, List<Trace> traces);
    public static List<Event> Events() {
        List<Event> events = new() { new(0, "INITIAL") };
        foreach (string line in File.ReadAllLines("input/events.txt", Encoding.ASCII)) {
            int separator = line.IndexOf(' ');
            events.Add(new(int.Parse(line[..separator]), line[(separator + 1)..]));
        }
        return events;
    }
    public static Params ReadParams() {
        string[] lines = File.ReadAllLines("input/params.txt", Encoding.ASCII),
                 f = lines[0].Split(' ');
        Dictionary<string, int> defaults = new() { { "customer", int.Parse(f[1]) },
                                                   { "peer", int.Parse(f[2]) },
                                                   { "provider", int.Parse(f[3]) } };
        int stepcap = int.Parse(lines[1].Split(' ')[1]);
        List<Trace> traces = new();
        foreach (string line in lines.Skip(2)) {
            string[] t = line.Split(' ');
            traces.Add(new(int.Parse(t[1]), t[2], Topology.AddressValue(t[2])));
        }
        return new(defaults, stepcap, traces);
    }
}
