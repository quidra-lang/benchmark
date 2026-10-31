using System;
using System.Collections.Generic;

static class Components
{
    sealed class Frame
    {
        public readonly int node;
        public int position;
        public Frame(int node) { this.node = node; }
    }
    public static List<List<int>> strong(List<List<int>> adjacency)
    {
        int count = adjacency.Count, counter = 0;
        int[] order = new int[count], low = new int[count];
        Array.Fill(order, -1);
        bool[] onStack = new bool[count];
        var stack = new Stack<int>();
        var groups = new List<List<int>>();
        for (int root = 0; root < count; root++)
        {
            if (order[root] >= 0) continue;
            order[root] = low[root] = counter++;
            stack.Push(root); onStack[root] = true;
            var work = new Stack<Frame>();
            work.Push(new Frame(root));
            while (work.Count > 0)
            {
                Frame frame = work.Peek();
                int node = frame.node;
                if (frame.position < adjacency[node].Count)
                {
                    int child = adjacency[node][frame.position++];
                    if (order[child] < 0)
                    {
                        order[child] = low[child] = counter++;
                        stack.Push(child); onStack[child] = true; work.Push(new Frame(child));
                    }
                    else if (onStack[child]) low[node] = Math.Min(low[node], order[child]);
                    continue;
                }
                work.Pop();
                if (work.Count > 0) low[work.Peek().node] = Math.Min(low[work.Peek().node], low[node]);
                if (low[node] == order[node])
                {
                    var group = new List<int>();
                    int member;
                    do { member = stack.Pop(); onStack[member] = false; group.Add(member); } while (member != node);
                    groups.Add(group);
                }
            }
        }
        return groups;
    }
    public static bool[] reachable(List<List<int>> adjacency, List<int> starts)
    {
        bool[] seen = new bool[adjacency.Count];
        var stack = new Stack<int>();
        foreach (int start in starts) if (!seen[start]) { seen[start] = true; stack.Push(start); }
        while (stack.Count > 0) foreach (int neighbor in adjacency[stack.Pop()]) if (!seen[neighbor]) { seen[neighbor] = true; stack.Push(neighbor); }
        return seen;
    }
    public static int[] distances(List<List<int>> adjacency, List<int> starts)
    {
        int[] distance = new int[adjacency.Count];
        Array.Fill(distance, -1);
        var queue = new Queue<int>();
        foreach (int start in starts) if (distance[start] < 0) { distance[start] = 0; queue.Enqueue(start); }
        while (queue.Count > 0)
        {
            int node = queue.Dequeue();
            foreach (int neighbor in adjacency[node]) if (distance[neighbor] < 0) { distance[neighbor] = distance[node] + 1; queue.Enqueue(neighbor); }
        }
        return distance;
    }
    public static int[] weak(List<List<int>> neighbors)
    {
        int[] labels = new int[neighbors.Count];
        Array.Fill(labels, -1);
        int count = 0;
        for (int start = 0; start < labels.Length; start++)
        {
            if (labels[start] >= 0) continue;
            labels[start] = count;
            var stack = new Stack<int>();
            stack.Push(start);
            while (stack.Count > 0) foreach (int neighbor in neighbors[stack.Pop()]) if (labels[neighbor] < 0) { labels[neighbor] = count; stack.Push(neighbor); }
            count++;
        }
        return labels;
    }
}
