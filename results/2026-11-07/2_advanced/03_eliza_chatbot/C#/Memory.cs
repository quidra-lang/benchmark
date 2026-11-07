using System.Collections.Generic;

sealed class Memory(int capacity)
{
    public int Capacity { get; } = capacity;
    public List<string> Texts = [], Log = [];
    public Memory Copy() => new(Capacity) { Texts = new(Texts), Log = new(Log) };
    public bool Store(string prefix, string keyword, string text)
    {
        if (Texts.Contains(text)) { Log.Add(prefix + " SKIP " + keyword + " " + text); return false; }
        if (Texts.Count == Capacity) { Log.Add(prefix + " DROP " + Texts[0]); Texts.RemoveAt(0); }
        Texts.Add(text); Log.Add(prefix + " STORE " + keyword + " " + text); return true;
    }
    public string Recall(string prefix)
    {
        string text = Texts[0]; Texts.RemoveAt(0); Log.Add(prefix + " RECALL " + text); return text;
    }
    public void Clear(string prefix)
    {
        if (Texts.Count > 0) Log.Add(prefix + " CLEAR " + Texts.Count);
        Texts.Clear();
    }
}
