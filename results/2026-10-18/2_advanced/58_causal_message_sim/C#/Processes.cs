using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Processes {
    public record Action(string kind, string argument, string value) {
    }
    public record Scheduled(int first, int period, Action action) {
    }
    public record Rule(string tag, Action action) {
    }
    public record Planned(int time, int process, Action action) {
    }
    public sealed class State {
        public int index, initial, balance, lamport, incoming, outgoing, refused, minimum, maxHeld;
        public int[] vector, broadcast, next, counts = new int[5];
        public List<Scheduled> scheduled = new();
        public List<Rule> rules = new();
        public List<Program.Event> events = new();
        public List<Program.Packet> hold = new(), delivered = new();
        public List<Dictionary<int, Program.Packet>> reorder = new();
        public State(int index, int initial, int size) {
            this.index = index;
            this.initial = initial;
            balance = initial;
            minimum = initial;
            vector = new int[size];
            broadcast = new int[size];
            next = new int[size];
            Array.Fill(next, 1);
            for (int i = 0; i < size; i++)
                reorder.Add(new());
        }
        public int Held() {
            int total = hold.Count;
            foreach (Dictionary<int, Program.Packet> buffer in reorder)
                total += buffer.Count;
            return total;
        }
        public int BalanceAt(int count) {
            return count == 0 ? initial : events[count - 1].balance;
        }
    }
    public static Action ParseAction(string[] w, int start) {
        return new Action(w[start], w[start + 1], start + 2 < w.Length ? w[start + 2] : "");
    }
    public static List<State> Read(List<string> names) {
        List<State> result = new();
        State current = null;
        foreach (string line in File.ReadAllLines(Path.Combine("input/programs.txt")).ToList()) {
            string[] w = line.Split(' ');
            switch (w[0]) {
            case "PROCESS": {
                current = new State(names.IndexOf(w[1]), int.Parse(w[3]), names.Count);
                result.Add(current);
                break;
            }
            case "AT": {
                bool every = w[2].Equals("EVERY");
                current.scheduled.Add(new Scheduled(int.Parse(w[1]), every ? int.Parse(w[3]) : 0,
                                                    ParseAction(w, every ? 4 : 2)));
                break;
            }
            case "ON":
                current.rules.Add(new Rule(w[1], ParseAction(w, 2)));
                break;
            }
        }
        return result;
    }
    public static List<Planned> Expand(List<State> states, int end) {
        List<Planned> result = new();
        foreach (State p in states)
            foreach (Scheduled s in p.scheduled) {
                for (int time = s.first; time <= end; time += s.period) {
                    result.Add(new Planned(time, p.index, s.action));
                    if (s.period == 0)
                        break;
                }
            }
        return result;
    }
}
