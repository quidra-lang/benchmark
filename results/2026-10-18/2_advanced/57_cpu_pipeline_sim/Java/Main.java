import java.util.*;

public final class Main {
    static final String[] CLASSES = {"ALU", "MUL", "LOAD", "STORE", "BRANCH", "JUMP", "NOP"};
    static final String[] MISS = {"direction", "btb_miss", "wrong_target"};
    static final int[][] USE = {{1, 1, 2}, {1, 1, 1}, {1, 1, 0}, {0, 1, 1}, {0, 1, 2}, {2, 2, 0}, {0, 0, 0}};
    record Instruction(int number, int line, int pc, int kind, int rd, int rs1, int rs2, boolean taken,
                       int target, int address) {
        boolean control() {
            return kind == 4 || kind == 5;
        }
        int next() {
            return taken ? target : pc + 4;
        }
    }
    record Detail(int predicted, int kind) {}
    static final class Prediction {
        TraceIO.Predictor definition;
        boolean[] flags;
        Detail[] details;
        int[] counts = new int[14];
        int bits;
        String accuracy(int kind) {
            int i = kind == 0 ? 0 : kind == 4 ? 2 : 4;
            return Report.percentage(counts[i] - counts[i + 1], counts[i]);
        }
    }
    record Combination(TraceIO.Variant variant, String predictor, Pipeline.Run run) {}
    record Pair(int producer, int waiting, int cause) {}
    record Span(int first, int last, char symbol, int stage) {}
    static final class Row {
        int number, pc;
        String kind, annotation;
        List<Span> spans = new ArrayList<>();
        Row(int number, int pc, String kind, String annotation) {
            this.number = number;
            this.pc = pc;
            this.kind = kind;
            this.annotation = annotation;
        }
        void add(int first, int last, char symbol, int stage) {
            if (first <= last)
                spans.add(new Span(first, last, symbol, stage));
        }
    }
    static TraceIO.Config config;
    static List<Instruction> instructions = new ArrayList<>();
    static Map<Integer, Instruction> statics = new TreeMap<>();
    static Map<Integer, List<Integer>> groups = new TreeMap<>();
    static List<String> rejects = new ArrayList<>(), gaps = new ArrayList<>();
    static Map<String, Prediction> predictions = new HashMap<>();
    static List<List<Hazards.Source>> sources;
    static List<Combination> combinations = new ArrayList<>();
    static Pipeline.Run primary;
    static int inputLines;
    static String check(String line, int lineNumber) {
        String[] w = line.split(" ", -1);
        if (w.length != 8 || Arrays.asList(w).contains(""))
            return "fields";
        int pc = TraceIO.hex(w[0]);
        if (pc < 0 || pc % 4 != 0)
            return "pc";
        int kind = Arrays.asList(CLASSES).indexOf(w[1]);
        if (kind < 0)
            return "class";
        int[] regs = new int[3];
        for (int i = 0; i < 3; i++) {
            regs[i] = TraceIO.register(w[i + 2]);
            if (regs[i] < 0 && !w[i + 2].equals("-"))
                return "register";
        }
        for (int i = 0; i < 3; i++)
            if (USE[kind][i] == 1 && regs[i] < 0 || USE[kind][i] == 0 && regs[i] >= 0)
                return "operands";
        boolean control = kind == 4 || kind == 5;
        if (kind == 4   ? !w[5].equals("T") && !w[5].equals("N")
            : kind == 5 ? !w[5].equals("T")
                        : !w[5].equals("-"))
            return "taken";
        int target = TraceIO.hex(w[6]);
        if (control ? (target < 0 || target % 4 != 0 || target == pc + 4) : !w[6].equals("-"))
            return "target";
        int address = TraceIO.hex(w[7]);
        if (kind == 2 || kind == 3) {
            if (address < 0 || address % 4 != 0)
                return "address";
        } else if (!w[7].equals("-"))
            return "address";
        Instruction first = statics.get(pc);
        if (first != null &&
            (kind != first.kind() || regs[0] != first.rd() || regs[1] != first.rs1() ||
             regs[2] != first.rs2() || ((kind == 4 || kind == 5 && regs[1] < 0) && target != first.target())))
            return "conflict";
        int n = instructions.size();
        Instruction t = new Instruction(n + 1, lineNumber, pc, kind, regs[0], regs[1], regs[2],
                                        w[5].equals("T"), target, address);
        if (n > 0 && instructions.get(n - 1).next() != pc)
            gaps.add("gap line " + lineNumber + " expected " + Report.hex(instructions.get(n - 1).next()) +
                     " found " + Report.hex(pc));
        instructions.add(t);
        statics.putIfAbsent(pc, t);
        groups.computeIfAbsent(pc, k -> new ArrayList<>()).add(n);
        return null;
    }
    static Prediction predict(TraceIO.Predictor definition) {
        Prediction p = new Prediction();
        p.definition = definition;
        p.flags = new boolean[instructions.size()];
        p.details = new Detail[instructions.size()];
        Predictors.BTB btb = new Predictors.BTB(config.btb);
        Predictors.RAS ras = new Predictors.RAS(config.ras);
        Predictors.Direction direction = new Predictors.Direction(definition);
        p.bits = direction.bits();
        for (int i = 0; i < instructions.size(); i++) {
            Instruction t = instructions.get(i);
            if (!t.control())
                continue;
            int candidate = btb.lookup(t.pc());
            if (candidate >= 0)
                p.counts[6]++;
            boolean isReturn = t.kind() == 5 && t.rd() < 0 && t.rs1() == 31,
                    isCall = t.kind() == 5 && t.rd() == 31;
            if (isReturn) {
                p.counts[8]++;
                int value = ras.pop();
                if (value >= 0) {
                    candidate = value;
                    p.counts[9]++;
                    if (value == t.target())
                        p.counts[10]++;
                }
            }
            if (isCall) {
                p.counts[7]++;
                ras.push(t.pc() + 4);
            }
            boolean taken = t.kind() != 4 || direction.prediction(t.pc(), t.target());
            int predicted = definition.scheme().equals("PERFECT") ? t.next()
                            : taken && candidate >= 0             ? candidate
                                                                  : t.pc() + 4;
            boolean missed = predicted != t.next();
            int miss = -1;
            if (missed) {
                miss = t.kind() == 4 && taken != t.taken() ? 0 : candidate < 0 ? 1 : 2;
                p.counts[11 + miss]++;
                p.counts[1]++;
            }
            p.flags[i] = missed;
            p.details[i] = new Detail(predicted, miss);
            p.counts[0]++;
            int k = t.kind() == 4 ? 2 : 4;
            p.counts[k]++;
            if (missed)
                p.counts[k + 1]++;
            if (t.kind() == 4)
                direction.update(t.pc(), t.taken());
            if (t.taken())
                btb.insert(t.pc(), t.target());
        }
        return p;
    }
    static void simulate() {
        for (TraceIO.Variant variant : config.variants)
            for (TraceIO.Predictor predictor : config.predictors) {
                Pipeline.Run run = Pipeline.simulate(instructions, sources, variant,
                                                     predictions.get(predictor.name()).flags);
                run.predictor = predictor.name();
                combinations.add(new Combination(variant, predictor.name(), run));
                if (variant.name().equals(config.primaryVariant) &&
                    predictor.name().equals(config.primaryPredictor))
                    primary = run;
            }
        combinations.sort((a, b) -> {
            int c = Integer.compare(a.run().total, b.run().total);
            if (c == 0)
                c = a.variant().name().compareTo(b.variant().name());
            return c != 0 ? c : a.predictor().compareTo(b.predictor());
        });
    }
    static List<Row> rows() {
        List<Row> rows = new ArrayList<>();
        StringBuilder[] annotations = new StringBuilder[instructions.size()];
        for (int i = 0; i < annotations.length; i++)
            annotations[i] = new StringBuilder();
        for (Pipeline.Stall stall : primary.records)
            if (stall.waiting() >= 0)
                annotations[stall.waiting()]
                    .append(" ")
                    .append(Pipeline.CAUSES[stall.cause()])
                    .append(" ")
                    .append(stall.cycles());
        Prediction p = predictions.get(primary.predictor);
        for (int i = 0; i < instructions.size(); i++) {
            Instruction t = instructions.get(i);
            Pipeline.Time time = primary.times.get(i);
            String annotation = annotations[i].toString();
            if (p.flags[i])
                annotation += " mispredict " + MISS[p.details[i].kind()];
            Row row = new Row(i + 1, t.pc(), CLASSES[t.kind()], annotation);
            row.add(time.f(), time.f(), 'F', 0);
            row.add(time.f() + 1, time.d() - 1, '*', 0);
            row.add(time.d(), time.d(), 'D', 1);
            row.add(time.d() + 1, time.x() - 1, '*', 1);
            row.add(time.x(), time.m() - 1, 'X', 2);
            row.add(time.m(), time.m(), 'M', 3);
            row.add(time.w(), time.w(), 'W', 4);
            rows.add(row);
            if (!p.flags[i])
                continue;
            boolean early = Hazards.idResolved(t, primary.variant);
            int cancel = time.x() + (early ? 0 : 1);
            Row wrong = new Row(-1, p.details[i].predicted(), "FLUSH", "");
            wrong.add(time.d(), time.d(), 'F', 0);
            wrong.add(time.d() + 1, time.x() - 1, '*', 0);
            wrong.add(cancel, cancel, 'x', -1);
            if (!early)
                wrong.add(time.x(), time.x(), 'D', 1);
            rows.add(wrong);
            if (!early) {
                Row second = new Row(-1, p.details[i].predicted() + 4, "FLUSH", "");
                second.add(time.x(), time.x(), 'F', 0);
                second.add(cancel, cancel, 'x', -1);
                rows.add(second);
            }
        }
        return rows;
    }
    static List<String> diagram(List<Row> rows) {
        int first = config.first, last = config.last, width = last - first + 1, visible = 0, stars = 0,
            flushed = 0, completed = 0;
        List<String> lines = new ArrayList<>();
        lines.add("pipeline variant=" + config.primaryVariant + " predictor=" + config.primaryPredictor +
                  " cycles " + first + "-" + last);
        lines.add(Report.heading(first, last));
        String[][] contents = new String[width][5];
        for (String[] content : contents)
            Arrays.fill(content, ".");
        for (Row row : rows) {
            char[] cells = new char[width];
            Arrays.fill(cells, '.');
            boolean show = false;
            for (Span span : row.spans)
                for (int c = Math.max(first, span.first()); c <= Math.min(last, span.last()); c++) {
                    cells[c - first] = span.symbol();
                    show = true;
                    if (span.stage() >= 0)
                        contents[c - first][span.stage()] =
                            row.number < 0 ? "w" : Integer.toString(row.number);
                }
            if (show) {
                visible++;
                for (char c : cells) {
                    if (c == '*')
                        stars++;
                    if (c == 'x')
                        flushed++;
                }
                lines.add(Report.row(row.number, row.pc, row.kind, new String(cells), row.annotation));
            }
        }
        for (Pipeline.Time time : primary.times)
            if (first <= time.w() && time.w() <= last)
                completed++;
        lines.add("rows " + visible + " completed " + completed + " stall_cells " + stars + " flushed " +
                  flushed);
        lines.add("");
        lines.add("stages");
        lines.add("cycle IF ID EX MEM WB");
        for (int c = first; c <= last; c++)
            lines.add(c + " " + String.join(" ", contents[c - first]));
        return lines;
    }
    static int sum(int[] values) {
        int s = 0;
        for (int value : values)
            s += value;
        return s;
    }
    static String causes(int[] values) {
        StringJoiner s = new StringJoiner(" ");
        for (int c = 0; c < 4; c++)
            s.add(Pipeline.CAUSES[c] + " " + values[c]);
        return s.toString();
    }
    static void part(List<String> lines, List<String> section) {
        if (!lines.isEmpty())
            lines.add("");
        lines.addAll(section);
    }
    static List<String> statistics(List<Row> rows) {
        int n = instructions.size(), c = primary.total;
        TraceIO.Variant v = primary.variant;
        List<String> lines = new ArrayList<>(), section = new ArrayList<>();
        section.add("input lines " + inputLines + " accepted " + n + " rejected " + rejects.size() +
                    " gaps " + gaps.size());
        section.addAll(rejects);
        section.addAll(gaps);
        part(lines, section);
        int[] mix = new int[7], distance = new int[6];
        int branchTaken = 0, backward = 0, indirect = 0, link = 0, staticBranch = 0, staticJump = 0,
            operands = 0;
        Set<Integer> addresses = new HashSet<>();
        for (int i = 0; i < n; i++) {
            Instruction t = instructions.get(i);
            mix[t.kind()]++;
            if (t.kind() == 4) {
                if (t.taken())
                    branchTaken++;
                if (t.target() < t.pc())
                    backward++;
            }
            if (t.kind() == 5) {
                if (t.rs1() >= 0)
                    indirect++;
                if (t.rd() >= 0)
                    link++;
            }
            if (t.kind() == 2 || t.kind() == 3)
                addresses.add(t.address());
            for (Hazards.Source source : sources.get(i)) {
                operands++;
                if (source.producer() >= 0)
                    distance[Math.min(5, i - source.producer())]++;
            }
        }
        for (Instruction t : statics.values()) {
            if (t.kind() == 4)
                staticBranch++;
            if (t.kind() == 5)
                staticJump++;
        }
        section =
            new ArrayList<>(List.of("trace", "instructions " + n, "static_instructions " + statics.size()));
        StringJoiner mixLine = new StringJoiner(" ", "mix ", "");
        for (int k = 0; k < 7; k++)
            mixLine.add(CLASSES[k] + " " + mix[k]);
        section.add(mixLine.toString());
        section.add("branches " + mix[4] + " taken " + branchTaken + " backward " + backward);
        section.add("jumps " + mix[5] + " indirect " + indirect + " link " + link);
        section.add("static_control branches " + staticBranch + " jumps " + staticJump);
        section.add("memory loads " + mix[2] + " stores " + mix[3] + " distinct_addresses " +
                    addresses.size());
        String dline = "operands " + operands + " with_producer " + sum(distance) + " distance";
        for (int k = 1; k <= 5; k++)
            dline += " " + (k == 5 ? "5+" : Integer.toString(k)) + " " + distance[k];
        section.add(dline);
        part(lines, section);
        section = new ArrayList<>(List.of("prediction"));
        for (TraceIO.Predictor definition : config.predictors) {
            Prediction p = predictions.get(definition.name());
            int[] a = p.counts;
            section.add(definition.name() + " " + definition.scheme() + " bits " + p.bits + " control " +
                        a[0] + " mispredicted " + a[1] + " accuracy " + p.accuracy(0) + " branches " +
                        p.accuracy(4) + " jumps " + p.accuracy(5) + " direction " + a[11] + " btb_miss " +
                        a[12] + " wrong_target " + a[13]);
        }
        int[] a = predictions.get(config.predictors.get(0).name()).counts;
        section.add("btb entries " + config.btb + " lookups " + a[0] + " hits " + a[6] + " misses " +
                    (a[0] - a[6]));
        section.add("ras depth " + config.ras + " calls " + a[7] + " returns " + a[8] + " predicted " + a[9] +
                    " correct " + a[10]);
        part(lines, section);
        int[] finish = new int[n];
        int height = 0;
        for (int i = 0; i < n; i++) {
            int start = 0;
            for (Hazards.Source source : sources.get(i))
                if (source.producer() >= 0)
                    start = Math.max(start, finish[source.producer()]);
            int kind = instructions.get(i).kind();
            finish[i] = start + (kind == 2 ? 2 : kind == 1 ? v.latency() : 1);
            height = Math.max(height, finish[i]);
        }
        int s = sum(primary.cycles), refetch = rows.size() - n;
        section = new ArrayList<>(
            List.of("timing variant=" + v.name() + " predictor=" + primary.predictor,
                    "forwarding " + (v.forwarding() ? "on" : "off") + " branch_stage " + v.stage() +
                        " mul_latency " + v.latency(),
                    "cycles " + c, "cpi " + Report.fraction(c, n) + " " + Report.decimal(c, n),
                    "ipc " + Report.decimal(n, c), "stall_cycles total " + s + " " + causes(primary.cycles),
                    "stall_events " + causes(primary.events), "flushed " + refetch,
                    "cycle_check " + n + " + 4 + " + s + " = " + (n + 4 + s)));
        String stack = "cpi_stack base 1.0000 fill " + Report.decimal(4, n);
        for (int k = 0; k < 4; k++)
            stack += " " + Pipeline.CAUSES[k] + " " + Report.decimal(primary.cycles[k], n);
        section.add(stack);
        String lengths = "stall_lengths";
        for (int k = 1; k <= 5; k++)
            lengths += " " + (k == 5 ? "5+" : Integer.toString(k)) + " " + primary.lengths[k];
        section.add(lengths);
        section.add("dataflow height " + height + " ilp " + Report.decimal(n, height));
        part(lines, section);
        section = new ArrayList<>(List.of("whatif"));
        String changedStage = v.stage().equals("EX") ? "ID" : "EX";
        TraceIO.Variant[] variants = {
            v, new TraceIO.Variant(v.name(), v.forwarding(), v.stage(), 1),
            new TraceIO.Variant(v.name(), !v.forwarding(), v.stage(), v.latency()),
            new TraceIO.Variant(v.name(), v.forwarding(), changedStage, v.latency())};
        String[] names = {"perfect_prediction", "single_cycle_mul",
                          v.forwarding() ? "forwarding_off" : "forwarding_on",
                          "branch_stage_" + changedStage};
        for (int k = 0; k < 4; k++) {
            boolean[] flags = k == 0 ? new boolean[n] : predictions.get(primary.predictor).flags;
            int total = Pipeline.simulate(instructions, sources, variants[k], flags).total;
            section.add(names[k] + " cycles " + total + " saved " + (c - total) + " speedup " +
                        Report.decimal(c, total));
        }
        part(lines, section);
        int[] classStalls = new int[7];
        Map<Integer, int[]> byPC = new HashMap<>();
        Map<Pair, int[]> pairs = new HashMap<>();
        for (Pipeline.Stall stall : primary.records) {
            Instruction responsible = instructions.get(stall.responsible());
            classStalls[responsible.kind()] += stall.cycles();
            byPC.computeIfAbsent(responsible.pc(), k -> new int[4])[stall.cause()] += stall.cycles();
            if (stall.cause() >= 2) {
                Pair key = new Pair(instructions.get(stall.producer()).pc(),
                                    instructions.get(stall.waiting()).pc(), stall.cause());
                int[] value = pairs.computeIfAbsent(key, k -> new int[2]);
                value[0] += stall.cycles();
                value[1]++;
            }
        }
        section = new ArrayList<>(List.of("classes"));
        for (int k = 0; k < 7; k++)
            section.add(CLASSES[k] + " count " + mix[k] + " stall_cycles " + classStalls[k] +
                        " per_instruction " + (mix[k] == 0 ? "-" : Report.decimal(classStalls[k], mix[k])));
        part(lines, section);
        int[] paths = new int[3];
        for (int i = 0; i < n; i++)
            for (Hazards.Source source : sources.get(i))
                paths[Hazards.path(instructions.get(i),
                                   source.producer() < 0 ? null : primary.times.get(source.producer()),
                                   primary.times.get(i), v)]++;
        part(lines,
             List.of("forwarding regfile " + paths[0] + " ex_mem " + paths[1] + " mem_wb " + paths[2]));
        int[][] occupancy = new int[5][2];
        for (Row row : rows)
            for (Span span : row.spans)
                if (span.stage() >= 0)
                    occupancy[span.stage()][row.number < 0 ? 1 : 0] += span.last() - span.first() + 1;
        section = new ArrayList<>(List.of("occupancy cycles " + c));
        for (int k = 0; k < 5; k++) {
            int correct = occupancy[k][0], wrong = occupancy[k][1];
            section.add(Pipeline.STAGES[k] + " correct " + correct + " wrong " + wrong + " idle " +
                        (c - correct - wrong) + " busy " + Report.percentage(correct + wrong, c));
        }
        part(lines, section);
        List<Integer> pcs = new ArrayList<>(byPC.keySet());
        pcs.sort((x, y) -> {
            int order = Integer.compare(sum(byPC.get(y)), sum(byPC.get(x)));
            return order != 0 ? order : Integer.compare(x, y);
        });
        section = new ArrayList<>(List.of("hotspots"));
        for (int k = 0; k < Math.min(config.top, pcs.size()); k++) {
            int pc = pcs.get(k);
            section.add((k + 1) + " " + Report.hex(pc) + " " + CLASSES[statics.get(pc).kind()] +
                        " stall_cycles " + sum(byPC.get(pc)) + " " + causes(byPC.get(pc)));
        }
        part(lines, section);
        List<Pair> keys = new ArrayList<>(pairs.keySet());
        keys.sort((x, y) -> {
            int order = Integer.compare(pairs.get(y)[0], pairs.get(x)[0]);
            if (order == 0)
                order = Integer.compare(x.producer(), y.producer());
            if (order == 0)
                order = Integer.compare(x.waiting(), y.waiting());
            return order != 0 ? order : Integer.compare(x.cause(), y.cause());
        });
        section = new ArrayList<>(List.of("dependencies total " + keys.size()));
        for (int k = 0; k < Math.min(config.top, keys.size()); k++) {
            Pair key = keys.get(k);
            int[] value = pairs.get(key);
            section.add((k + 1) + " " + Report.hex(key.producer()) + " " +
                        CLASSES[statics.get(key.producer()).kind()] + " -> " + Report.hex(key.waiting()) +
                        " " + CLASSES[statics.get(key.waiting()).kind()] + " " +
                        Pipeline.CAUSES[key.cause()] + " stall_cycles " + value[0] + " events " + value[1]);
        }
        part(lines, section);
        section = new ArrayList<>(List.of("intervals size " + config.interval));
        for (int first = 0; first < n; first += config.interval) {
            int last = Math.min(n, first + config.interval) - 1,
                total = primary.times.get(last).w() - (first == 0 ? 0 : primary.times.get(first - 1).w());
            section.add((first + 1) + "-" + (last + 1) + " cycles " + total + " cpi " +
                        Report.decimal(total, last - first + 1));
        }
        part(lines, section);
        String table = "cycles_table";
        for (TraceIO.Predictor p : config.predictors)
            table += " " + p.name();
        section = new ArrayList<>(List.of(table));
        for (TraceIO.Variant variant : config.variants) {
            String line = variant.name();
            for (TraceIO.Predictor p : config.predictors)
                for (Combination pair : combinations)
                    if (pair.variant().name().equals(variant.name()) && pair.predictor().equals(p.name()))
                        line += " " + pair.run().total;
            section.add(line);
        }
        part(lines, section);
        return lines;
    }
    static int misses(Prediction prediction, List<Integer> indices) {
        int count = 0;
        for (int i : indices)
            if (prediction.flags[i])
                count++;
        return count;
    }
    static List<String> branches() {
        List<String> lines =
            new ArrayList<>(List.of("predictor,pc,class,executions,taken,mispredictions,accuracy"));
        for (TraceIO.Predictor definition : config.predictors)
            for (int pc : groups.keySet()) {
                List<Integer> indices = groups.get(pc);
                Instruction t = statics.get(pc);
                if (!t.control())
                    continue;
                int taken = 0;
                for (int i : indices)
                    if (instructions.get(i).taken())
                        taken++;
                int miss = misses(predictions.get(definition.name()), indices);
                lines.add(definition.name() + "," + Report.hex(pc) + "," + CLASSES[t.kind()] + "," +
                          indices.size() + "," + taken + "," + miss + "," +
                          Report.percentage(indices.size() - miss, indices.size()));
            }
        return lines;
    }
    static List<String> comparison() {
        List<String> lines = new ArrayList<>(List.of(
            "rank,variant,predictor,cycles,cpi,speedup,accuracy,mispredictions,control,structural,load_use,raw"));
        for (int i = 0; i < combinations.size(); i++) {
            Combination pair = combinations.get(i);
            Prediction p = predictions.get(pair.predictor());
            Pipeline.Run run = pair.run();
            String line = (i + 1) + "," + pair.variant().name() + "," + pair.predictor() + "," + run.total +
                          "," + Report.decimal(run.total, instructions.size()) + "," +
                          Report.decimal(primary.total, run.total) + "," + p.accuracy(0) + "," + p.counts[1];
            for (int value : run.cycles)
                line += "," + value;
            lines.add(line);
        }
        return lines;
    }
    static List<String> profile() {
        List<String> lines = new ArrayList<>(), section = new ArrayList<>(List.of("branches"));
        for (int pc : groups.keySet()) {
            Instruction t = statics.get(pc);
            if (t.kind() != 4)
                continue;
            List<Integer> indices = groups.get(pc);
            int transitions = 0, longT = 0, longN = 0, length = 0, taken = 0;
            boolean previous = false;
            boolean first = true;
            for (int i : indices) {
                boolean outcome = instructions.get(i).taken();
                if (!first && outcome != previous)
                    transitions++;
                length = !first && outcome == previous ? length + 1 : 1;
                if (outcome) {
                    taken++;
                    longT = Math.max(longT, length);
                } else
                    longN = Math.max(longN, length);
                previous = outcome;
                first = false;
            }
            String best = "";
            int minimum = Integer.MAX_VALUE;
            for (TraceIO.Predictor definition : config.predictors)
                if (!definition.scheme().equals("PERFECT")) {
                    int count = misses(predictions.get(definition.name()), indices);
                    if (count < minimum) {
                        minimum = count;
                        best = definition.name();
                    }
                }
            section.add(Report.hex(pc) + " " + (t.target() < pc ? "backward" : "forward") + " executions " +
                        indices.size() + " taken " + taken + " transitions " + transitions +
                        " longest_taken " + longT + " longest_not_taken " + longN + " best " + best + " " +
                        minimum);
        }
        part(lines, section);
        section = new ArrayList<>(List.of("loops"));
        for (int pc : groups.keySet()) {
            Instruction t = statics.get(pc);
            if (t.kind() != 4 || t.target() >= pc)
                continue;
            int trips = 0, length = 0, longest = 0;
            List<Integer> indices = groups.get(pc);
            for (int i : indices) {
                length++;
                if (!instructions.get(i).taken()) {
                    trips++;
                    longest = Math.max(longest, length);
                    length = 0;
                }
            }
            if (length > 0) {
                trips++;
                longest = Math.max(longest, length);
            }
            section.add(Report.hex(t.target()) + "-" + Report.hex(pc) + " body " +
                        ((pc - t.target()) / 4 + 1) + " entries " + trips + " iterations " + indices.size() +
                        " avg_trip " + Report.decimal(indices.size(), trips) + " max_trip " + longest);
        }
        part(lines, section);
        Map<Integer, int[]> segments = new HashMap<>();
        int first = 0;
        for (int last = 0; last < instructions.size(); last++)
            if (instructions.get(last).control() || last == instructions.size() - 1) {
                int[] group = segments.computeIfAbsent(instructions.get(first).pc(), k -> new int[3]);
                group[0]++;
                group[1] += last - first + 1;
                group[2] += primary.times.get(last).w() - (first == 0 ? 0 : primary.times.get(first - 1).w());
                first = last + 1;
            }
        List<Integer> starts = new ArrayList<>(segments.keySet());
        starts.sort((x, y) -> {
            int c = Integer.compare(segments.get(y)[2], segments.get(x)[2]);
            return c != 0 ? c : Integer.compare(x, y);
        });
        section = new ArrayList<>(List.of("segments total " + segments.size()));
        for (int k = 0; k < Math.min(config.top, starts.size()); k++) {
            int pc = starts.get(k);
            int[] group = segments.get(pc);
            section.add((k + 1) + " " + Report.hex(pc) + " instances " + group[0] + " instructions " +
                        group[1] + " cycles " + group[2] + " cpi " + Report.decimal(group[2], group[1]));
        }
        part(lines, section);
        section = new ArrayList<>(List.of("indirect"));
        for (int pc : groups.keySet()) {
            Instruction t = statics.get(pc);
            if (t.kind() != 5 || t.rs1() < 0)
                continue;
            Map<Integer, Integer> counts = new HashMap<>();
            List<Integer> indices = groups.get(pc);
            for (int i : indices) {
                int target = instructions.get(i).target();
                counts.put(target, counts.getOrDefault(target, 0) + 1);
            }
            List<Integer> targets = new ArrayList<>(counts.keySet());
            targets.sort((x, y) -> {
                int c = Integer.compare(counts.get(y), counts.get(x));
                return c != 0 ? c : Integer.compare(x, y);
            });
            String value = "";
            for (int target : targets)
                value += " " + Report.hex(target) + ":" + counts.get(target);
            section.add(Report.hex(pc) + " executions " + indices.size() + " distinct " + targets.size() +
                        " targets" + value);
        }
        part(lines, section);
        section = new ArrayList<>(List.of("instructions"));
        Map<Integer, Integer> stalls = new HashMap<>();
        for (Pipeline.Stall stall : primary.records) {
            int pc = instructions.get(stall.responsible()).pc();
            stalls.put(pc, stalls.getOrDefault(pc, 0) + stall.cycles());
        }
        for (int pc : groups.keySet()) {
            Instruction t = statics.get(pc);
            section.add(Report.hex(pc) + " " + CLASSES[t.kind()] + " " + Report.register(t.rd()) + " " +
                        Report.register(t.rs1()) + " " + Report.register(t.rs2()) + " executions " +
                        groups.get(pc).size() + " stall_cycles " + stalls.getOrDefault(pc, 0));
        }
        part(lines, section);
        return lines;
    }
    public static void main(String[] args) throws Exception {
        config = TraceIO.read();
        List<String> input = TraceIO.lines("trace.txt");
        inputLines = input.size();
        for (int i = 0; i < input.size(); i++) {
            String reason = check(input.get(i), i + 1);
            if (reason != null)
                rejects.add("reject line " + (i + 1) + " " + reason);
        }
        sources = Hazards.dependencies(instructions);
        for (TraceIO.Predictor definition : config.predictors)
            predictions.put(definition.name(), predict(definition));
        simulate();
        List<Row> rows = rows();
        Report.write("pipeline.txt", diagram(rows));
        Report.write("stats.txt", statistics(rows));
        Report.write("branches.csv", branches());
        Report.write("comparison.csv", comparison());
        Report.write("profile.txt", profile());
    }
}
