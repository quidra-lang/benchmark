using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Program {
    public static readonly string[] CLASSES = { "ALU", "MUL", "LOAD", "STORE", "BRANCH", "JUMP", "NOP" };
    public static readonly string[] MISS = { "direction", "btb_miss", "wrong_target" };
    public static readonly int[][] USE = { new int[] { 1, 1, 2 }, new int[] { 1, 1, 1 },
                                           new int[] { 1, 1, 0 }, new int[] { 0, 1, 1 },
                                           new int[] { 0, 1, 2 }, new int[] { 2, 2, 0 },
                                           new int[] { 0, 0, 0 } };
    public record Instruction(int number, int line, int pc, int kind, int rd, int rs1, int rs2, bool taken,
                              int target, int address) {
        public bool Control() {
            return kind == 4 || kind == 5;
        }
        public int Next() {
            return taken ? target : pc + 4;
        }
    }
    public record Detail(int predicted, int kind) {
    }
    public sealed class Prediction {
        public TraceIO.Predictor definition;
        public bool[] flags;
        public Detail[] details;
        public int[] counts = new int[14];
        public int bits;
        public string Accuracy(int kind) {
            int i = kind == 0 ? 0 : kind == 4 ? 2 : 4;
            return Report.Percentage(counts[i] - counts[i + 1], counts[i]);
        }
    }
    public record Combination(TraceIO.Variant variant, string predictor, Pipeline.Run run) {
    }
    public record Pair(int producer, int waiting, int cause) {
    }
    public record Span(int first, int last, char symbol, int stage) {
    }
    public sealed class Row {
        public int number, pc;
        public string kind, annotation;
        public List<Span> spans = new();
        public Row(int number, int pc, string kind, string annotation) {
            this.number = number;
            this.pc = pc;
            this.kind = kind;
            this.annotation = annotation;
        }
        public void Add(int first, int last, char symbol, int stage) {
            if (first <= last)
                spans.Add(new Span(first, last, symbol, stage));
        }
    }
    public static TraceIO.Config config;
    public static List<Instruction> instructions = new();
    public static SortedDictionary<int, Instruction> statics = new();
    public static SortedDictionary<int, List<int>> groups = new();
    public static List<string> rejects = new(), gaps = new();
    public static Dictionary<string, Prediction> predictions = new();
    public static List<List<Hazards.Source>> sources;
    public static List<Combination> combinations = new();
    public static Pipeline.Run primary;
    public static int inputLines;
    public static string Check(string line, int lineNumber) {
        string[] w = line.Split(' ', StringSplitOptions.None);
        if (w.Length != 8 || w.Contains(""))
            return "fields";
        int pc = TraceIO.Hex(w[0]);
        if (pc < 0 || pc % 4 != 0)
            return "pc";
        int kind = Array.IndexOf(CLASSES, w[1]);
        if (kind < 0)
            return "class";
        int[] regs = new int[3];
        for (int i = 0; i < 3; i++) {
            regs[i] = TraceIO.Register(w[i + 2]);
            if (regs[i] < 0 && !w[i + 2].Equals("-"))
                return "register";
        }
        for (int i = 0; i < 3; i++)
            if (USE[kind][i] == 1 && regs[i] < 0 || USE[kind][i] == 0 && regs[i] >= 0)
                return "operands";
        bool control = kind == 4 || kind == 5;
        if (kind == 4   ? !w[5].Equals("T") && !w[5].Equals("N")
            : kind == 5 ? !w[5].Equals("T")
                        : !w[5].Equals("-"))
            return "taken";
        int target = TraceIO.Hex(w[6]);
        if (control ? (target < 0 || target % 4 != 0 || target == pc + 4) : !w[6].Equals("-"))
            return "target";
        int address = TraceIO.Hex(w[7]);
        if (kind == 2 || kind == 3) {
            if (address < 0 || address % 4 != 0)
                return "address";
        } else if (!w[7].Equals("-"))
            return "address";
        Instruction first = statics.GetValueOrDefault(pc);
        if (first != null &&
            (kind != first.kind || regs[0] != first.rd || regs[1] != first.rs1 || regs[2] != first.rs2 ||
             ((kind == 4 || kind == 5 && regs[1] < 0) && target != first.target)))
            return "conflict";
        int n = instructions.Count;
        Instruction t = new Instruction(n + 1, lineNumber, pc, kind, regs[0], regs[1], regs[2],
                                        w[5].Equals("T"), target, address);
        if (n > 0 && instructions[n - 1].Next() != pc)
            gaps.Add("gap line " + lineNumber + " expected " + Report.Hex(instructions[n - 1].Next()) +
                     " found " + Report.Hex(pc));
        instructions.Add(t);
        statics.TryAdd(pc, t);
        groups.GetOrAdd(pc, () => new()).Add(n);
        return null;
    }
    public static Prediction Predict(TraceIO.Predictor definition) {
        Prediction p = new Prediction();
        p.definition = definition;
        p.flags = new bool[instructions.Count];
        p.details = new Detail[instructions.Count];
        Predictors.BTB btb = new Predictors.BTB(config.btb);
        Predictors.RAS ras = new Predictors.RAS(config.ras);
        Predictors.Direction direction = new Predictors.Direction(definition);
        p.bits = direction.Bits();
        for (int i = 0; i < instructions.Count; i++) {
            Instruction t = instructions[i];
            if (!t.Control())
                continue;
            int candidate = btb.Lookup(t.pc);
            if (candidate >= 0)
                p.counts[6]++;
            bool isReturn = t.kind == 5 && t.rd < 0 && t.rs1 == 31, isCall = t.kind == 5 && t.rd == 31;
            if (isReturn) {
                p.counts[8]++;
                int value = ras.Pop();
                if (value >= 0) {
                    candidate = value;
                    p.counts[9]++;
                    if (value == t.target)
                        p.counts[10]++;
                }
            }
            if (isCall) {
                p.counts[7]++;
                ras.Push(t.pc + 4);
            }
            bool taken = t.kind != 4 || direction.Prediction(t.pc, t.target);
            int predicted = definition.scheme.Equals("PERFECT") ? t.Next()
                            : taken && candidate >= 0           ? candidate
                                                                : t.pc + 4;
            bool missed = predicted != t.Next();
            int miss = -1;
            if (missed) {
                miss = t.kind == 4 && taken != t.taken ? 0 : candidate < 0 ? 1 : 2;
                p.counts[11 + miss]++;
                p.counts[1]++;
            }
            p.flags[i] = missed;
            p.details[i] = new Detail(predicted, miss);
            p.counts[0]++;
            int k = t.kind == 4 ? 2 : 4;
            p.counts[k]++;
            if (missed)
                p.counts[k + 1]++;
            if (t.kind == 4)
                direction.Update(t.pc, t.taken);
            if (t.taken)
                btb.Insert(t.pc, t.target);
        }
        return p;
    }
    public static void Simulate() {
        foreach (TraceIO.Variant variant in config.variants)
            foreach (TraceIO.Predictor predictor in config.predictors) {
                Pipeline.Run run =
                    Pipeline.Simulate(instructions, sources, variant, predictions[predictor.name].flags);
                run.predictor = predictor.name;
                combinations.Add(new Combination(variant, predictor.name, run));
                if (variant.name.Equals(config.primaryVariant) &&
                    predictor.name.Equals(config.primaryPredictor))
                    primary = run;
            }
        combinations.Sort((a, b) => {
            int c = (a.run.total).CompareTo(b.run.total);
            if (c == 0)
                c = string.CompareOrdinal(a.variant.name, b.variant.name);
            return c != 0 ? c : string.CompareOrdinal(a.predictor, b.predictor);
        });
    }
    public static List<Row> Rows() {
        List<Row> rows = new();
        StringBuilder[] annotations = new StringBuilder[instructions.Count];
        for (int i = 0; i < annotations.Length; i++)
            annotations[i] = new StringBuilder();
        foreach (Pipeline.Stall stall in primary.records)
            if (stall.waiting >= 0)
                annotations[stall.waiting]
                    .Append(" ")
                    .Append(Pipeline.CAUSES[stall.cause])
                    .Append(" ")
                    .Append(stall.cycles);
        Prediction p = predictions[primary.predictor];
        for (int i = 0; i < instructions.Count; i++) {
            Instruction t = instructions[i];
            Pipeline.Time time = primary.times[i];
            string annotation = annotations[i].ToString();
            if (p.flags[i])
                annotation += " mispredict " + MISS[p.details[i].kind];
            Row row = new Row(i + 1, t.pc, CLASSES[t.kind], annotation);
            row.Add(time.f, time.f, 'F', 0);
            row.Add(time.f + 1, time.d - 1, '*', 0);
            row.Add(time.d, time.d, 'D', 1);
            row.Add(time.d + 1, time.x - 1, '*', 1);
            row.Add(time.x, time.m - 1, 'X', 2);
            row.Add(time.m, time.m, 'M', 3);
            row.Add(time.w, time.w, 'W', 4);
            rows.Add(row);
            if (!p.flags[i])
                continue;
            bool early = Hazards.IdResolved(t, primary.variant);
            int cancel = time.x + (early ? 0 : 1);
            Row wrong = new Row(-1, p.details[i].predicted, "FLUSH", "");
            wrong.Add(time.d, time.d, 'F', 0);
            wrong.Add(time.d + 1, time.x - 1, '*', 0);
            wrong.Add(cancel, cancel, 'x', -1);
            if (!early)
                wrong.Add(time.x, time.x, 'D', 1);
            rows.Add(wrong);
            if (!early) {
                Row second = new Row(-1, p.details[i].predicted + 4, "FLUSH", "");
                second.Add(time.x, time.x, 'F', 0);
                second.Add(cancel, cancel, 'x', -1);
                rows.Add(second);
            }
        }
        return rows;
    }
    public static List<string> Diagram(List<Row> rows) {
        int first = config.first, last = config.last, width = last - first + 1, visible = 0, stars = 0,
            flushed = 0, completed = 0;
        List<string> lines = new();
        lines.Add("pipeline variant=" + config.primaryVariant + " predictor=" + config.primaryPredictor +
                  " cycles " + first + "-" + last);
        lines.Add(Report.Heading(first, last));
        string[][] contents = Enumerable.Range(0, width)
                                  .Select(
                                      _ => new string[5])
                                  .ToArray();
        foreach (string[] content in contents)
            Array.Fill(content, ".");
        foreach (Row row in rows) {
            char[] cells = new char[width];
            Array.Fill(cells, '.');
            bool show = false;
            foreach (Span span in row.spans)
                for (int c = Math.Max(first, span.first); c <= Math.Min(last, span.last); c++) {
                    cells[c - first] = span.symbol;
                    show = true;
                    if (span.stage >= 0)
                        contents[c - first][span.stage] = row.number < 0 ? "w" : Convert.ToString(row.number);
                }
            if (show) {
                visible++;
                foreach (char c in cells) {
                    if (c == '*')
                        stars++;
                    if (c == 'x')
                        flushed++;
                }
                lines.Add(Report.Row(row.number, row.pc, row.kind, new string(cells), row.annotation));
            }
        }
        foreach (Pipeline.Time time in primary.times)
            if (first <= time.w && time.w <= last)
                completed++;
        lines.Add("rows " + visible + " completed " + completed + " stall_cells " + stars + " flushed " +
                  flushed);
        lines.Add("");
        lines.Add("stages");
        lines.Add("cycle IF ID EX MEM WB");
        for (int c = first; c <= last; c++)
            lines.Add(c + " " + string.Join(" ", contents[c - first]));
        return lines;
    }
    public static int Sum(int[] values) {
        int s = 0;
        foreach (int value in values)
            s += value;
        return s;
    }
    public static string Causes(int[] values) {
        List<string> s = new();
        for (int c = 0; c < 4; c++)
            s.Add(Pipeline.CAUSES[c] + " " + values[c]);
        return string.Join(" ", s);
    }
    public static void Part(List<string> lines, List<string> section) {
        if (lines.Count != 0)
            lines.Add("");
        lines.AddRange(section);
    }
    public static List<string> Statistics(List<Row> rows) {
        int n = instructions.Count, c = primary.total;
        TraceIO.Variant v = primary.variant;
        List<string> lines = new(), section = new();
        section.Add("input lines " + inputLines + " accepted " + n + " rejected " + rejects.Count + " gaps " +
                    gaps.Count);
        section.AddRange(rejects);
        section.AddRange(gaps);
        Part(lines, section);
        int[] mix = new int[7], distance = new int[6];
        int branchTaken = 0, backward = 0, indirect = 0, link = 0, staticBranch = 0, staticJump = 0,
            operands = 0;
        HashSet<int> addresses = new();
        for (int i = 0; i < n; i++) {
            Instruction t = instructions[i];
            mix[t.kind]++;
            if (t.kind == 4) {
                if (t.taken)
                    branchTaken++;
                if (t.target < t.pc)
                    backward++;
            }
            if (t.kind == 5) {
                if (t.rs1 >= 0)
                    indirect++;
                if (t.rd >= 0)
                    link++;
            }
            if (t.kind == 2 || t.kind == 3)
                addresses.Add(t.address);
            foreach (Hazards.Source source in sources[i]) {
                operands++;
                if (source.producer >= 0)
                    distance[Math.Min(5, i - source.producer)]++;
            }
        }
        foreach (Instruction t in statics.Values) {
            if (t.kind == 4)
                staticBranch++;
            if (t.kind == 5)
                staticJump++;
        }
        section = new(["trace", "instructions " + n, "static_instructions " + statics.Count]);
        List<string> mixLine = new();
        for (int k = 0; k < 7; k++)
            mixLine.Add(CLASSES[k] + " " + mix[k]);
        section.Add("mix " + string.Join(" ", mixLine));
        section.Add("branches " + mix[4] + " taken " + branchTaken + " backward " + backward);
        section.Add("jumps " + mix[5] + " indirect " + indirect + " link " + link);
        section.Add("static_control branches " + staticBranch + " jumps " + staticJump);
        section.Add("memory loads " + mix[2] + " stores " + mix[3] + " distinct_addresses " +
                    addresses.Count);
        string dline = "operands " + operands + " with_producer " + Sum(distance) + " distance";
        for (int k = 1; k <= 5; k++)
            dline += " " + (k == 5 ? "5+" : Convert.ToString(k)) + " " + distance[k];
        section.Add(dline);
        Part(lines, section);
        section = new(["prediction"]);
        foreach (TraceIO.Predictor definition in config.predictors) {
            Prediction p = predictions[definition.name];
            int[] a = p.counts;
            section.Add(definition.name + " " + definition.scheme + " bits " + p.bits + " control " + a[0] +
                        " mispredicted " + a[1] + " accuracy " + p.Accuracy(0) + " branches " +
                        p.Accuracy(4) + " jumps " + p.Accuracy(5) + " direction " + a[11] + " btb_miss " +
                        a[12] + " wrong_target " + a[13]);
        }
        int[] shared = predictions[config.predictors[0].name].counts;
        section.Add("btb entries " + config.btb + " lookups " + shared[0] + " hits " + shared[6] +
                    " misses " + (shared[0] - shared[6]));
        section.Add("ras depth " + config.ras + " calls " + shared[7] + " returns " + shared[8] +
                    " predicted " + shared[9] + " correct " + shared[10]);
        Part(lines, section);
        int[] finish = new int[n];
        int height = 0;
        for (int i = 0; i < n; i++) {
            int start = 0;
            foreach (Hazards.Source source in sources[i])
                if (source.producer >= 0)
                    start = Math.Max(start, finish[source.producer]);
            int kind = instructions[i].kind;
            finish[i] = start + (kind == 2 ? 2 : kind == 1 ? v.latency : 1);
            height = Math.Max(height, finish[i]);
        }
        int s = Sum(primary.cycles), refetch = rows.Count - n;
        section = new([
            "timing variant=" + v.name + " predictor=" + primary.predictor,
            "forwarding " + (v.forwarding ? "on" : "off") + " branch_stage " + v.stage + " mul_latency " +
                v.latency,
            "cycles " + c, "cpi " + Report.Fraction(c, n) + " " + Report.Decimal(c, n),
            "ipc " + Report.Decimal(n, c), "stall_cycles total " + s + " " + Causes(primary.cycles),
            "stall_events " + Causes(primary.events), "flushed " + refetch,
            "cycle_check " + n + " + 4 + " + s + " = " + (n + 4 + s)
        ]);
        string stack = "cpi_stack base 1.0000 fill " + Report.Decimal(4, n);
        for (int k = 0; k < 4; k++)
            stack += " " + Pipeline.CAUSES[k] + " " + Report.Decimal(primary.cycles[k], n);
        section.Add(stack);
        string lengths = "stall_lengths";
        for (int k = 1; k <= 5; k++)
            lengths += " " + (k == 5 ? "5+" : Convert.ToString(k)) + " " + primary.lengths[k];
        section.Add(lengths);
        section.Add("dataflow height " + height + " ilp " + Report.Decimal(n, height));
        Part(lines, section);
        section = new(["whatif"]);
        string changedStage = v.stage.Equals("EX") ? "ID" : "EX";
        TraceIO.Variant[] variants = { v, new TraceIO.Variant(v.name, v.forwarding, v.stage, 1),
                                       new TraceIO.Variant(v.name, !v.forwarding, v.stage, v.latency),
                                       new TraceIO.Variant(v.name, v.forwarding, changedStage, v.latency) };
        string[] names = { "perfect_prediction", "single_cycle_mul",
                           v.forwarding ? "forwarding_off" : "forwarding_on",
                           "branch_stage_" + changedStage };
        for (int k = 0; k < 4; k++) {
            bool[] flags = k == 0 ? new bool[n] : predictions[primary.predictor].flags;
            int total = Pipeline.Simulate(instructions, sources, variants[k], flags).total;
            section.Add(names[k] + " cycles " + total + " saved " + (c - total) + " speedup " +
                        Report.Decimal(c, total));
        }
        Part(lines, section);
        int[] classStalls = new int[7];
        Dictionary<int, int[]> byPC = new();
        Dictionary<Pair, int[]> pairs = new();
        foreach (Pipeline.Stall stall in primary.records) {
            Instruction responsible = instructions[stall.responsible];
            classStalls[responsible.kind] += stall.cycles;
            byPC.GetOrAdd(responsible.pc, () => new int[4])[stall.cause] += stall.cycles;
            if (stall.cause >= 2) {
                Pair key =
                    new Pair(instructions[stall.producer].pc, instructions[stall.waiting].pc, stall.cause);
                int[] value = pairs.GetOrAdd(key, () => new int[2]);
                value[0] += stall.cycles;
                value[1]++;
            }
        }
        section = new(["classes"]);
        for (int k = 0; k < 7; k++)
            section.Add(CLASSES[k] + " count " + mix[k] + " stall_cycles " + classStalls[k] +
                        " per_instruction " + (mix[k] == 0 ? "-" : Report.Decimal(classStalls[k], mix[k])));
        Part(lines, section);
        int[] paths = new int[3];
        for (int i = 0; i < n; i++)
            foreach (Hazards.Source source in sources[i])
                paths[Hazards.Path(instructions[i],
                                   source.producer < 0 ? null : primary.times[source.producer],
                                   primary.times[i], v)]++;
        Part(lines, ["forwarding regfile " + paths[0] + " ex_mem " + paths[1] + " mem_wb " + paths[2]]);
        int[][] occupancy = Enumerable.Range(0, 5)
                                .Select(
                                    _ => new int[2])
                                .ToArray();
        foreach (Row row in rows)
            foreach (Span span in row.spans)
                if (span.stage >= 0)
                    occupancy[span.stage][row.number < 0 ? 1 : 0] += span.last - span.first + 1;
        section = new(["occupancy cycles " + c]);
        for (int k = 0; k < 5; k++) {
            int correct = occupancy[k][0], wrong = occupancy[k][1];
            section.Add(Pipeline.STAGES[k] + " correct " + correct + " wrong " + wrong + " idle " +
                        (c - correct - wrong) + " busy " + Report.Percentage(correct + wrong, c));
        }
        Part(lines, section);
        List<int> pcs = new(byPC.Keys);
        pcs.Sort((x, y) => {
            int order = (Sum(byPC[y])).CompareTo(Sum(byPC[x]));
            return order != 0 ? order : (x).CompareTo(y);
        });
        section = new(["hotspots"]);
        for (int k = 0; k < Math.Min(config.top, pcs.Count); k++) {
            int pc = pcs[k];
            section.Add((k + 1) + " " + Report.Hex(pc) + " " + CLASSES[statics[pc].kind] + " stall_cycles " +
                        Sum(byPC[pc]) + " " + Causes(byPC[pc]));
        }
        Part(lines, section);
        List<Pair> keys = new(pairs.Keys);
        keys.Sort((x, y) => {
            int order = (pairs[y][0]).CompareTo(pairs[x][0]);
            if (order == 0)
                order = (x.producer).CompareTo(y.producer);
            if (order == 0)
                order = (x.waiting).CompareTo(y.waiting);
            return order != 0 ? order : (x.cause).CompareTo(y.cause);
        });
        section = new(["dependencies total " + keys.Count]);
        for (int k = 0; k < Math.Min(config.top, keys.Count); k++) {
            Pair key = keys[k];
            int[] value = pairs[key];
            section.Add((k + 1) + " " + Report.Hex(key.producer) + " " + CLASSES[statics[key.producer].kind] +
                        " -> " + Report.Hex(key.waiting) + " " + CLASSES[statics[key.waiting].kind] + " " +
                        Pipeline.CAUSES[key.cause] + " stall_cycles " + value[0] + " events " + value[1]);
        }
        Part(lines, section);
        section = new(["intervals size " + config.interval]);
        for (int first = 0; first < n; first += config.interval) {
            int last = Math.Min(n, first + config.interval) - 1,
                total = primary.times[last].w - (first == 0 ? 0 : primary.times[first - 1].w);
            section.Add((first + 1) + "-" + (last + 1) + " cycles " + total + " cpi " +
                        Report.Decimal(total, last - first + 1));
        }
        Part(lines, section);
        string table = "cycles_table";
        foreach (TraceIO.Predictor p in config.predictors)
            table += " " + p.name;
        section = new([table]);
        foreach (TraceIO.Variant variant in config.variants) {
            string line = variant.name;
            foreach (TraceIO.Predictor p in config.predictors)
                foreach (Combination pair in combinations)
                    if (pair.variant.name.Equals(variant.name) && pair.predictor.Equals(p.name))
                        line += " " + pair.run.total;
            section.Add(line);
        }
        Part(lines, section);
        return lines;
    }
    public static int Misses(Prediction prediction, List<int> indices) {
        int count = 0;
        foreach (int i in indices)
            if (prediction.flags[i])
                count++;
        return count;
    }
    public static List<string> Branches() {
        List<string> lines = new(["predictor,pc,class,executions,taken,mispredictions,accuracy"]);
        foreach (TraceIO.Predictor definition in config.predictors)
            foreach (int pc in groups.Keys) {
                List<int> indices = groups[pc];
                Instruction t = statics[pc];
                if (!t.Control())
                    continue;
                int taken = 0;
                foreach (int i in indices)
                    if (instructions[i].taken)
                        taken++;
                int miss = Misses(predictions[definition.name], indices);
                lines.Add(definition.name + "," + Report.Hex(pc) + "," + CLASSES[t.kind] + "," +
                          indices.Count + "," + taken + "," + miss + "," +
                          Report.Percentage(indices.Count - miss, indices.Count));
            }
        return lines;
    }
    public static List<string> Comparison() {
        List<string> lines = new([
            "rank,variant,predictor,cycles,cpi,speedup,accuracy,mispredictions,control,structural,load_use,raw"
        ]);
        for (int i = 0; i < combinations.Count; i++) {
            Combination pair = combinations[i];
            Prediction p = predictions[pair.predictor];
            Pipeline.Run run = pair.run;
            string line = (i + 1) + "," + pair.variant.name + "," + pair.predictor + "," + run.total + "," +
                          Report.Decimal(run.total, instructions.Count) + "," +
                          Report.Decimal(primary.total, run.total) + "," + p.Accuracy(0) + "," + p.counts[1];
            foreach (int value in run.cycles)
                line += "," + value;
            lines.Add(line);
        }
        return lines;
    }
    public static List<string> Profile() {
        List<string> lines = new(), section = new(["branches"]);
        foreach (int pc in groups.Keys) {
            Instruction t = statics[pc];
            if (t.kind != 4)
                continue;
            List<int> indices = groups[pc];
            int transitions = 0, longT = 0, longN = 0, length = 0, taken = 0;
            bool previous = false;
            bool firstOutcome = true;
            foreach (int i in indices) {
                bool outcome = instructions[i].taken;
                if (!firstOutcome && outcome != previous)
                    transitions++;
                length = !firstOutcome && outcome == previous ? length + 1 : 1;
                if (outcome) {
                    taken++;
                    longT = Math.Max(longT, length);
                } else
                    longN = Math.Max(longN, length);
                previous = outcome;
                firstOutcome = false;
            }
            string best = "";
            int minimum = int.MaxValue;
            foreach (TraceIO.Predictor definition in config.predictors)
                if (!definition.scheme.Equals("PERFECT")) {
                    int count = Misses(predictions[definition.name], indices);
                    if (count < minimum) {
                        minimum = count;
                        best = definition.name;
                    }
                }
            section.Add(Report.Hex(pc) + " " + (t.target < pc ? "backward" : "forward") + " executions " +
                        indices.Count + " taken " + taken + " transitions " + transitions +
                        " longest_taken " + longT + " longest_not_taken " + longN + " best " + best + " " +
                        minimum);
        }
        Part(lines, section);
        section = new(["loops"]);
        foreach (int pc in groups.Keys) {
            Instruction t = statics[pc];
            if (t.kind != 4 || t.target >= pc)
                continue;
            int trips = 0, length = 0, longest = 0;
            List<int> indices = groups[pc];
            foreach (int i in indices) {
                length++;
                if (!instructions[i].taken) {
                    trips++;
                    longest = Math.Max(longest, length);
                    length = 0;
                }
            }
            if (length > 0) {
                trips++;
                longest = Math.Max(longest, length);
            }
            section.Add(Report.Hex(t.target) + "-" + Report.Hex(pc) + " body " + ((pc - t.target) / 4 + 1) +
                        " entries " + trips + " iterations " + indices.Count + " avg_trip " +
                        Report.Decimal(indices.Count, trips) + " max_trip " + longest);
        }
        Part(lines, section);
        Dictionary<int, int[]> segments = new();
        int first = 0;
        for (int last = 0; last < instructions.Count; last++)
            if (instructions[last].Control() || last == instructions.Count - 1) {
                int[] group = segments.GetOrAdd(instructions[first].pc, () => new int[3]);
                group[0]++;
                group[1] += last - first + 1;
                group[2] += primary.times[last].w - (first == 0 ? 0 : primary.times[first - 1].w);
                first = last + 1;
            }
        List<int> starts = new(segments.Keys);
        starts.Sort((x, y) => {
            int c = (segments[y][2]).CompareTo(segments[x][2]);
            return c != 0 ? c : (x).CompareTo(y);
        });
        section = new(["segments total " + segments.Count]);
        for (int k = 0; k < Math.Min(config.top, starts.Count); k++) {
            int pc = starts[k];
            int[] group = segments[pc];
            section.Add((k + 1) + " " + Report.Hex(pc) + " instances " + group[0] + " instructions " +
                        group[1] + " cycles " + group[2] + " cpi " + Report.Decimal(group[2], group[1]));
        }
        Part(lines, section);
        section = new(["indirect"]);
        foreach (int pc in groups.Keys) {
            Instruction t = statics[pc];
            if (t.kind != 5 || t.rs1 < 0)
                continue;
            Dictionary<int, int> counts = new();
            List<int> indices = groups[pc];
            foreach (int i in indices) {
                int target = instructions[i].target;
                counts[target] = counts.GetValueOrDefault(target, 0) + 1;
            }
            List<int> targets = new(counts.Keys);
            targets.Sort((x, y) => {
                int c = (counts[y]).CompareTo(counts[x]);
                return c != 0 ? c : (x).CompareTo(y);
            });
            string value = "";
            foreach (int target in targets)
                value += " " + Report.Hex(target) + ":" + counts[target];
            section.Add(Report.Hex(pc) + " executions " + indices.Count + " distinct " + targets.Count +
                        " targets" + value);
        }
        Part(lines, section);
        section = new(["instructions"]);
        Dictionary<int, int> stalls = new();
        foreach (Pipeline.Stall stall in primary.records) {
            int pc = instructions[stall.responsible].pc;
            stalls[pc] = stalls.GetValueOrDefault(pc, 0) + stall.cycles;
        }
        foreach (int pc in groups.Keys) {
            Instruction t = statics[pc];
            section.Add(Report.Hex(pc) + " " + CLASSES[t.kind] + " " + Report.Register(t.rd) + " " +
                        Report.Register(t.rs1) + " " + Report.Register(t.rs2) + " executions " +
                        groups[pc].Count + " stall_cycles " + stalls.GetValueOrDefault(pc, 0));
        }
        Part(lines, section);
        return lines;
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        config = TraceIO.Read();
        List<string> input = TraceIO.Lines("trace.txt");
        inputLines = input.Count;
        for (int i = 0; i < input.Count; i++) {
            string reason = Check(input[i], i + 1);
            if (reason != null)
                rejects.Add("reject line " + (i + 1) + " " + reason);
        }
        sources = Hazards.Dependencies(instructions);
        foreach (TraceIO.Predictor definition in config.predictors)
            predictions[definition.name] = Predict(definition);
        Simulate();
        List<Row> rows = Rows();
        Report.Write("pipeline.txt", Diagram(rows));
        Report.Write("stats.txt", Statistics(rows));
        Report.Write("branches.csv", Branches());
        Report.Write("comparison.csv", Comparison());
        Report.Write("profile.txt", Profile());
    }
}
