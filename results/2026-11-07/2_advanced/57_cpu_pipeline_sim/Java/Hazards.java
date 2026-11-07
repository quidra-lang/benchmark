import java.util.*;

final class Hazards {
    record Source(int register, int producer) {}
    static List<List<Source>> dependencies(List<Main.Instruction> instructions) {
        int[] writers = new int[32];
        Arrays.fill(writers, -1);
        List<List<Source>> result = new ArrayList<>();
        for (int i = 0; i < instructions.size(); i++) {
            Main.Instruction t = instructions.get(i);
            List<Source> current = new ArrayList<>();
            for (int register : new int[] {t.rs1(), t.rs2()})
                if (register > 0)
                    current.add(new Source(register, writers[register]));
            result.add(current);
            if (t.rd() > 0)
                writers[t.rd()] = i;
        }
        return result;
    }
    static boolean idResolved(Main.Instruction t, TraceIO.Variant v) {
        return t.kind() == 5 && t.rs1() < 0 || t.control() && v.stage().equals("ID");
    }
    static int ready(Main.Instruction t, Main.Instruction producer, Pipeline.Time p, TraceIO.Variant v) {
        if (!v.forwarding())
            return p.w() + 1;
        return (producer.kind() == 2 ? p.w() : p.m()) + (idResolved(t, v) ? 1 : 0);
    }
    static int path(Main.Instruction t, Pipeline.Time producer, Pipeline.Time time, TraceIO.Variant v) {
        if (producer == null || !v.forwarding())
            return 0;
        boolean early = idResolved(t, v);
        int use = time.x() - (early ? 1 : 0);
        if (producer.m() == use)
            return 1;
        if (!early && producer.w() == use)
            return 2;
        return 0;
    }
}
