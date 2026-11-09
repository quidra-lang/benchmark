using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Hazards {
    public record Source(int register, int producer) {
    }
    public static List<List<Source>> Dependencies(List<Program.Instruction> instructions) {
        int[] writers = new int[32];
        Array.Fill(writers, -1);
        List<List<Source>> result = new();
        for (int i = 0; i < instructions.Count; i++) {
            Program.Instruction t = instructions[i];
            List<Source> current = new();
            foreach (int register in new int[] { t.rs1, t.rs2 })
                if (register > 0)
                    current.Add(new Source(register, writers[register]));
            result.Add(current);
            if (t.rd > 0)
                writers[t.rd] = i;
        }
        return result;
    }
    public static bool IdResolved(Program.Instruction t, TraceIO.Variant v) {
        return t.kind == 5 && t.rs1 < 0 || t.Control() && v.stage.Equals("ID");
    }
    public static int Ready(Program.Instruction t, Program.Instruction producer, Pipeline.Time p,
                            TraceIO.Variant v) {
        if (!v.forwarding)
            return p.w + 1;
        return (producer.kind == 2 ? p.w : p.m) + (IdResolved(t, v) ? 1 : 0);
    }
    public static int Path(Program.Instruction t, Pipeline.Time producer, Pipeline.Time time,
                           TraceIO.Variant v) {
        if (producer == null || !v.forwarding)
            return 0;
        bool early = IdResolved(t, v);
        int use = time.x - (early ? 1 : 0);
        if (producer.m == use)
            return 1;
        if (!early && producer.w == use)
            return 2;
        return 0;
    }
}
