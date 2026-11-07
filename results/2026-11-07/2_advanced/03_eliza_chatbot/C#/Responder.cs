using System.Collections.Generic;
using System.Linq;
using System.Text;

static class Responder
{
    public static List<string> Reflect(IEnumerable<string> words, Dictionary<string, List<string>> substitutions)
    {
        List<string> result = [];
        foreach (string word in words) if (substitutions.TryGetValue(word, out var replacement)) result.AddRange(replacement); else result.Add(word);
        return result;
    }
    public static string Build(string text, List<List<string>> bindings, Dictionary<string, List<string>> post)
    {
        StringBuilder reply = new();
        for (int index = 0; index < text.Length;)
        {
            if (index + 3 <= text.Length && ScriptLoader.IsReference(text.Substring(index, 3)))
            {
                int n = text[index + 1] - '0';
                if (n >= 1 && n <= bindings.Count) reply.Append(string.Join(" ", Reflect(bindings[n - 1], post)));
                index += 3;
            }
            else reply.Append(text[index++]);
        }
        string result = string.Join(" ", Helpers.Words(reply.ToString()));
        return result.Length > 0 && result[0] is >= 'a' and <= 'z' ? char.ToUpperInvariant(result[0]) + result[1..] : result;
    }
    public static List<string> Restate(IEnumerable<string> arguments, List<List<string>> bindings)
    {
        List<string> result = [];
        foreach (string argument in arguments)
        {
            if (!ScriptLoader.IsReference(argument)) result.Add(argument);
            else { int n = argument[1] - '0'; if (n >= 1 && n <= bindings.Count) result.AddRange(bindings[n - 1]); }
        }
        return result;
    }
    public static List<string> Wrap(string text)
    {
        List<string> lines = [];
        foreach (string word in Helpers.Words(text))
        {
            if (lines.Count == 0) lines.Add("ELIZA: " + word);
            else if (lines[^1].Length + 1 + word.Length <= 72) lines[^1] += " " + word;
            else lines.Add("       " + word);
        }
        return lines;
    }
}
