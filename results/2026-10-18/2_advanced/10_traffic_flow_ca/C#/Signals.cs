sealed record Phase(int Duration, string Token, HashSet<string> Greens);
sealed class Junction
{
    public string Node;
    public int Offset, Cycle;
    public List<Phase> Phases = [];
    public List<Segment> Incoming = [];
    public Junction(string node, int offset, IEnumerable<string> tokens)
    {
        Node = node; Offset = offset;
        foreach (string token in tokens) { string[] pair = token.Split(':'); int duration = int.Parse(pair[0]); Phases.Add(new(duration,pair[1],pair[1] == "-" ? [] : pair[1].Split(',').ToHashSet())); Cycle += duration; }
    }
    public bool Green(string segment, int step)
    {
        if (Phases.Count == 0) return true; int time = (step - 1 + Offset) % Cycle;
        foreach (Phase phase in Phases) { if (time < phase.Duration) return phase.Greens.Contains(segment); time -= phase.Duration; } return false;
    }
    public List<string> PlanLines()
    {
        if (Phases.Count == 0) return [$"JUNCTION {Node} unsignalized"];
        List<string> result = [$"JUNCTION {Node} signal cycle {Cycle} offset {Offset}"]; int start = 0;
        for (int i = 0; i < Phases.Count; i++) { int end = start + Phases[i].Duration - 1; result.Add($"  PHASE {i + 1} {start}-{end} {Phases[i].Token}"); start = end + 1; } return result;
    }
}
