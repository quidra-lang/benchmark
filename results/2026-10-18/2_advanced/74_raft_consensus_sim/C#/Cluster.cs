using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public static class Cluster {
    public record Settings(int nodes, int electionMin, int electionMax, int heartbeat, int batch,
                           int quorum, int seed, int end, int retry, int attempts, int sample) {}
    public record Control(int time, string kind, List<int> arguments, List<List<int>> groups) {}
    public sealed class Request {
        public int number, time, initialDestination, scheduled, destination, attempts, redirects,
            index, term, latency;
        public string command, status, result;
        public bool accepted, abandoned;
        public Request(int number, int time, int destination, string command) {
            this.number = number;
            this.time = time;
            this.initialDestination = destination;
            this.destination = destination;
            this.scheduled = time;
            this.command = command;
        }
    }
    public record Input(Settings settings, List<Control> controls, List<Request> requests) {}
    public static Input Read() {
        Dictionary<string, int[]> values = new();
        foreach (string line in File.ReadAllLines(Path.Combine("input", "cluster.txt")).ToList()) {
            string[] fields = line.Split(" ");
            int[] numbers = new int[fields.Length - 1];
            for (int i = 1; i < fields.Length; i++)
                numbers[i - 1] = int.Parse(fields[i]);
            values[fields[0]] = numbers;
        }
        Settings settings = new Settings(
            values["NODES"][0], values["ELECTION"][0], values["ELECTION"][1],
            values["HEARTBEAT"][0], values["BATCH"][0], values["QUORUM"][0], values["SEED"][0],
            values["END"][0], values["RETRY"][0], values["ATTEMPTS"][0], values["SAMPLE"][0]);
        List<Control> controls = new();
        List<Request> requests = new();
        foreach (string line in File.ReadAllLines(Path.Combine("input", "script.txt")).ToList()) {
            string[] w = line.Split(" ");
            int time = int.Parse(w[0]);
            string kind = w[1];
            if (kind.Equals("REQUEST"))
                requests.Add(new Request(requests.Count + 1, time, int.Parse(w[2]),
                                         string.Join(" ", w[(3)..(w.Length)])));
            else {
                List<int> arguments = new();
                List<List<int>> groups = new();
                for (int i = 2; i < w.Length; i++)
                    if (kind.Equals("PARTITION")) {
                        List<int> group = new();
                        foreach (string number in w[i].Split(","))
                            group.Add(int.Parse(number));
                        groups.Add(group);
                    } else
                        arguments.Add(int.Parse(w[i]));
                controls.Add(new Control(time, kind, arguments, groups));
            }
        }
        return new Input(settings, controls, requests);
    }
}
