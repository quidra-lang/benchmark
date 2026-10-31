using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public sealed class Network {
    public sealed class Generator {
        public long state;
        public int draws;
        public Generator(int seed) {
            state = seed;
        }
        public int Draw() {
            state = 48271 * state % 2147483647;
            draws++;
            return (int)state;
        }
    }
    public sealed class Channel {
        public int source, destination, a, b, sequence, lastArrival, messages, markers, buffered, maxDelay,
            entries;
        public bool fifo;
        public int[] previous;
        public string Delay() {
            return a == b ? Convert.ToString(a) : a + "-" + b;
        }
        public void Dispatch(Program.Packet packet, int time, Generator generator) {
            packet.source = source;
            packet.destination = destination;
            packet.sequence = ++sequence;
            packet.dispatch = time;
            int delay = a == b ? a : a + generator.Draw() % (b - a + 1);
            int arrival = time + delay;
            if (fifo)
                arrival = Math.Max(arrival, lastArrival);
            lastArrival = Math.Max(lastArrival, arrival);
            packet.arrival = arrival;
            maxDelay = Math.Max(maxDelay, arrival - time);
            if (packet.message == null)
                markers++;
            else {
                messages++;
                int[] vector = packet.message.send.vector;
                for (int i = 0; i < previous.Length; i++)
                    if (previous[i] != vector[i])
                        entries++;
                previous = vector.ToArray();
            }
        }
    }
    public List<string> names;
    public Channel[][] channels;
    public Network() {
        List<string> lines = File.ReadAllLines(Path.Combine("input/topology.txt")).ToList();
        string[] header = lines[0].Split(' ');
        names = header.Skip(1).ToList();
        int n = names.Count;
        channels = Enumerable.Range(0, n)
                       .Select(
                           _ => new Channel[n])
                       .ToArray();
        foreach (string line in lines.GetRange(1, lines.Count - (1))) {
            string[] w = line.Split(' ');
            Channel c = new Channel();
            c.source = names.IndexOf(w[1]);
            c.destination = names.IndexOf(w[2]);
            c.fifo = w[3].Equals("FIFO");
            c.a = int.Parse(w[4]);
            c.b = w.Length == 6 ? int.Parse(w[5]) : c.a;
            c.previous = new int[n];
            channels[c.source][c.destination] = c;
        }
    }
}
