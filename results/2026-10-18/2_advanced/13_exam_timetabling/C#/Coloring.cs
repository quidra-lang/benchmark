#nullable enable
using System;
using System.Linq;
using System.Collections.Generic;

sealed record Chosen(string Course, int Saturation);

sealed class Attempt
{
    private readonly List<string> courses;
    private readonly ConflictGraph graph;
    private readonly int limit;
    private readonly Func<string, Dictionary<string, int>, List<int>> candidateSlots;
    public int DeadEnds { get; private set; }
    public string? DeadEndCourse { get; private set; }
    public bool Aborted { get; private set; }
    public List<Chosen> Chosen { get; } = new();

    public Attempt(List<string> courses, ConflictGraph graph, int limit,
        Func<string, Dictionary<string, int>, List<int>> candidateSlots)
    {
        this.courses = courses;
        this.graph = graph;
        this.limit = limit;
        this.candidateSlots = candidateSlots;
    }

    private int Saturation(string id, Dictionary<string, int> assignment) =>
        graph.Neighbours(id).Keys.Where(assignment.ContainsKey).Select(other => assignment[other]).Distinct().Count();

    public bool Search(Dictionary<string, int> assignment)
    {
        string? id = courses.Where(course => !assignment.ContainsKey(course))
            .OrderByDescending(course => Saturation(course, assignment)).ThenByDescending(graph.Degree)
            .ThenBy(course => course, StringComparer.Ordinal).FirstOrDefault();
        if (id is null) return true;
        Chosen.Add(new Chosen(id, Saturation(id, assignment)));
        foreach (int slot in candidateSlots(id, assignment))
        {
            assignment[id] = slot;
            if (Search(assignment)) return true;
            assignment.Remove(id);
            if (Aborted) return false;
        }
        Chosen.RemoveAt(Chosen.Count - 1);
        DeadEnds++;
        DeadEndCourse = id;
        Aborted = DeadEnds > limit;
        return false;
    }
}

static class Coloring
{
    public static int GreedyNumbering(IEnumerable<string> order, ConflictGraph graph)
    {
        var numbers = new Dictionary<string, int>(StringComparer.Ordinal);
        int maximum = 0;
        foreach (string id in order)
        {
            var taken = graph.Neighbours(id).Keys.Where(numbers.ContainsKey)
                .Select(other => numbers[other]).ToHashSet();
            int number = 1;
            while (taken.Contains(number)) number++;
            numbers[id] = number;
            maximum = Math.Max(maximum, number);
        }
        return maximum;
    }
}
