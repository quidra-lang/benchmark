using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Pipeline {
    public static readonly string[] CAUSES = { "control", "structural", "load_use", "raw" };
    public static readonly string[] STAGES = { "IF", "ID", "EX", "MEM", "WB" };
    public record Time(int f, int d, int x, int m, int w) {
    }
    public record Stall(int cause, int cycles, int responsible, int waiting, int producer) {
    }
    public sealed class Run {
        public TraceIO.Variant variant;
        public string predictor;
        public List<Time> times = new();
        public List<Stall> records = new();
        public int[] cycles = new int[4], events = new int[4], lengths = new int[6];
        public int total;
    }
    public static Run Simulate(List<Program.Instruction> instructions, List<List<Hazards.Source>> sources,
                               TraceIO.Variant variant, bool[] misses) {
        Run run = new Run();
        run.variant = variant;
        for (int i = 0; i < instructions.Count; i++) {
            Program.Instruction t = instructions[i];
            int f = 1, d = 2, x = 3;
            if (i > 0) {
                Time p = run.times[i - 1];
                f = misses[i - 1] ? p.x + (Hazards.IdResolved(instructions[i - 1], variant) ? 0 : 1) : p.d;
                d = Math.Max(f + 1, p.x);
                int ideal = p.x + 1;
                int[] bounds = { d + 1, p.m, ideal, ideal };
                int[] producers = { -1, -1, -1, -1 };
                foreach (Hazards.Source source in sources[i])
                    if (source.producer >= 0) {
                        int j = source.producer,
                            ready = Hazards.Ready(t, instructions[j], run.times[j], variant);
                        int cause = instructions[j].kind == 2 ? 2 : 3;
                        if (ready > bounds[cause]) {
                            bounds[cause] = ready;
                            producers[cause] = j;
                        }
                    }
                x = ideal;
                for (int cause = 0; cause < 4; cause++)
                    if (bounds[cause] > x) {
                        run.records.Add(
                            new Stall(cause, bounds[cause] - x, cause < 2 ? i - 1 : i, i, producers[cause]));
                        x = bounds[cause];
                    }
                if (x > ideal)
                    run.lengths[Math.Min(5, x - ideal)]++;
            }
            int m = x + (t.kind == 1 ? variant.latency : 1);
            run.times.Add(new Time(f, d, x, m, m + 1));
        }
        int n = instructions.Count;
        if (instructions[n - 1].kind == 1 && variant.latency > 1)
            run.records.Add(new Stall(1, variant.latency - 1, n - 1, -1, -1));
        foreach (Stall stall in run.records) {
            run.cycles[stall.cause] += stall.cycles;
            run.events[stall.cause]++;
        }
        run.total = run.times[n - 1].w;
        return run;
    }
}
