using System.Collections.Generic;
using System.Linq;

static class Matcher
{
    public static bool Wildcard(string element) => element is "*" or "#" || element[0] == '@';
    public static List<List<string>>? Match(List<string> pattern, List<string> words, Dictionary<string, HashSet<string>> groups)
    {
        List<List<string>> bindings = [];
        bool Visit(int position, int start)
        {
            if (position == pattern.Count) return start == words.Count;
            string element = pattern[position];
            int low = start, high = words.Count;
            if (element != "*")
            {
                if (start == words.Count) return false;
                bool fits = element == "#" || element == words[start];
                if (element[0] == '@') fits = groups.TryGetValue(element[1..], out var members) && members.Contains(words[start]);
                if (!fits) return false;
                low = high = start + 1;
            }
            for (int end = low; end <= high; end++)
            {
                if (Wildcard(element)) bindings.Add(words.GetRange(start, end - start));
                if (Visit(position + 1, end)) return true;
                if (Wildcard(element)) bindings.RemoveAt(bindings.Count - 1);
            }
            return false;
        }
        return Visit(0, 0) ? bindings : null;
    }
    public static bool Covers(List<string> earlier, List<string> later, Dictionary<string, HashSet<string>> groups)
    {
        bool One(string a, string b)
        {
            if (a == "#") return b != "*";
            if (a[0] != '@') return a == b;
            var members = groups[a[1..]];
            return b[0] == '@' ? groups[b[1..]].All(members.Contains) : members.Contains(b);
        }
        bool Visit(int position, int start)
        {
            if (position == earlier.Count) return start == later.Count;
            if (earlier[position] == "*") return Enumerable.Range(start, later.Count - start + 1).Any(end => Visit(position + 1, end));
            return start < later.Count && One(earlier[position], later[start]) && Visit(position + 1, start + 1);
        }
        return Visit(0, 0);
    }
}
