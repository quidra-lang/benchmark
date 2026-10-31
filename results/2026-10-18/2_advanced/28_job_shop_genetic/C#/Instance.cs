using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

sealed class Operation {
    public readonly int ident, job, index, machine, duration, head;
    public int tail, previous = -1, next = -1;
    public Operation(int ident, int job, int index, int machine, int duration, int head) {
        this.ident = ident;
        this.job = job;
        this.index = index;
        this.machine = machine;
        this.duration = duration;
        this.head = head;
    }
    public string Code() {
        return "J" + job + "-" + index;
    }
}
sealed record Job(int number, List<Operation> operations, int work);
sealed record Machine(int number, List<Operation> operations, int load, int head, int tail, int bound);
sealed class Instance {
    public readonly int machineCount;
    public readonly List<Job> jobs = new();
    public readonly List<Operation> operations = new();
    public readonly List<Machine> machines = new();
    public readonly List<string> errors = new();
    public readonly Dictionary<int, Job> named = new();
    public int[] durations;
    public Instance() {
        List<string> lines = File.ReadAllLines(Path.Combine("input/instance.txt"), Encoding.ASCII).ToList();
        string[] header = lines[0].Split(" ");
        machineCount = int.Parse(header[1]);
        for (int number = 1; number <= int.Parse(header[0]); number++) {
            List<Operation> steps = new();
            HashSet<int> used = new();
            int head = 0;
            bool valid = true;
            string[] tokens = lines[number].Split(" ");
            for (int k = 0; k < tokens.Length; k++) {
                string[] pair = tokens[k].Split(":");
                int machine = int.Parse(pair[0]), duration = int.Parse(pair[1]);
                string error = machine < 1 || machine > machineCount ? "unknown machine " + machine
                               : duration < 1 || duration > 99       ? "bad duration " + duration
                               : used.Contains(machine)              ? "repeated machine " + machine
                                                                     : "";
                if (error.Length != 0) {
                    errors.Add("job " + number + " operation " + (k + 1) + ": " + error);
                    valid = false;
                    break;
                }
                used.Add(machine);
                steps.Add(new Operation(operations.Count + k, number, k + 1, machine, duration, head));
                head += duration;
            }
            if (!valid)
                continue;
            for (int k = 0; k < steps.Count; k++) {
                Operation operation = steps[k];
                operation.tail = head - operation.head - operation.duration;
                if (k > 0)
                    operation.previous = operation.ident - 1;
                if (k + 1 < steps.Count)
                    operation.next = operation.ident + 1;
            }
            Job job = new Job(number, steps, head);
            jobs.Add(job);
            named[number] = job;
            operations.AddRange(steps);
        }
        durations = new int[operations.Count];
        foreach (Operation operation in operations)
            durations[operation.ident] = operation.duration;
        for (int m = 1; m <= machineCount; m++) {
            List<Operation> tasks = new();
            int load = 0, head = int.MaxValue, tail = int.MaxValue;
            foreach (Operation operation in operations)
                if (operation.machine == m) {
                    tasks.Add(operation);
                    load += operation.duration;
                    head = Math.Min(head, operation.head);
                    tail = Math.Min(tail, operation.tail);
                }
            machines.Add(new Machine(m, tasks, load, head, tail, head + load + tail));
        }
    }
}
