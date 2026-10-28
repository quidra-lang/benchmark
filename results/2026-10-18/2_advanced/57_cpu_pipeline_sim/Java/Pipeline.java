import java.util.*;

final class Pipeline {
    static final String[] CAUSES = {"control", "structural", "load_use", "raw"};
    static final String[] STAGES = {"IF", "ID", "EX", "MEM", "WB"};
    record Time(int f, int d, int x, int m, int w) {}
    record Stall(int cause, int cycles, int responsible, int waiting, int producer) {}
    static final class Run {
        TraceIO.Variant variant;
        String predictor;
        List<Time> times = new ArrayList<>();
        List<Stall> records = new ArrayList<>();
        int[] cycles = new int[4], events = new int[4], lengths = new int[6];
        int total;
    }
    static Run simulate(List<Main.Instruction> instructions, List<List<Hazards.Source>> sources,
                        TraceIO.Variant variant, boolean[] misses) {
        Run run = new Run();
        run.variant = variant;
        for (int i = 0; i < instructions.size(); i++) {
            Main.Instruction t = instructions.get(i);
            int f = 1, d = 2, x = 3;
            if (i > 0) {
                Time p = run.times.get(i - 1);
                f = misses[i - 1] ? p.x() + (Hazards.idResolved(instructions.get(i - 1), variant) ? 0 : 1)
                                  : p.d();
                d = Math.max(f + 1, p.x());
                int ideal = p.x() + 1;
                int[] bounds = {d + 1, p.m(), ideal, ideal};
                int[] producers = {-1, -1, -1, -1};
                for (Hazards.Source source : sources.get(i))
                    if (source.producer() >= 0) {
                        int j = source.producer(),
                            ready = Hazards.ready(t, instructions.get(j), run.times.get(j), variant);
                        int cause = instructions.get(j).kind() == 2 ? 2 : 3;
                        if (ready > bounds[cause]) {
                            bounds[cause] = ready;
                            producers[cause] = j;
                        }
                    }
                x = ideal;
                for (int cause = 0; cause < 4; cause++)
                    if (bounds[cause] > x) {
                        run.records.add(
                            new Stall(cause, bounds[cause] - x, cause < 2 ? i - 1 : i, i, producers[cause]));
                        x = bounds[cause];
                    }
                if (x > ideal)
                    run.lengths[Math.min(5, x - ideal)]++;
            }
            int m = x + (t.kind() == 1 ? variant.latency() : 1);
            run.times.add(new Time(f, d, x, m, m + 1));
        }
        int n = instructions.size();
        if (instructions.get(n - 1).kind() == 1 && variant.latency() > 1)
            run.records.add(new Stall(1, variant.latency() - 1, n - 1, -1, -1));
        for (Stall stall : run.records) {
            run.cycles[stall.cause()] += stall.cycles();
            run.events[stall.cause()]++;
        }
        run.total = run.times.get(n - 1).w();
        return run;
    }
}
