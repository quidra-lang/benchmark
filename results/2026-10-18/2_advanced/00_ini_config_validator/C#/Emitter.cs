#nullable enable
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public sealed class OutputKey
{
    public Definition Definition { get; }
    public Spec? Spec { get; }
    public object Value { get; }
    public string Notation { get; }

    public OutputKey(Definition definition, Spec? spec, object value)
    {
        Definition = definition;
        Spec = spec;
        Value = value;
        Notation = Emitter.ValueNotation(spec?.Kind ?? "string", spec?.Item ?? "string", value);
    }
}

public static class Emitter
{
    public const string Mask = "********";

    public static string StringNotation(string text)
    {
        var result = new StringBuilder("\"");
        foreach (char c in text)
            result.Append(c switch
            {
                '\\' => "\\\\", '"' => "\\\"", '\n' => "\\n", '\t' => "\\t", _ => c.ToString()
            });
        return result.Append('"').ToString();
    }

    public static string ValueNotation(string kind, string item, object value) => kind switch
    {
        "string" => StringNotation((string)value),
        "bool" => (bool)value ? "true" : "false",
        "list" => "[" + string.Join(", ", ((List<object>)value).Select(v => ValueNotation(item, "string", v))) + "]",
        "int" or "size" or "duration" => ((long)value).ToString(CultureInfo.InvariantCulture),
        _ => (string)value
    };

    public static string Shown(OutputKey output) => output.Spec?.Secret == true ? Mask : output.Notation;

    private static IEnumerable<string> Normalized(Profile profile)
    {
        yield return "profile " + profile.Name;
        string? previous = null;
        foreach (string key in KeyNames.Sorted(profile.Outputs.Keys))
        {
            string section = KeyNames.Section(key);
            if (section != previous)
            {
                yield return "[" + section + "]";
                previous = section;
            }
            yield return KeyNames.Name(key) + " = " + Shown(profile.Outputs[key]);
        }
    }

    private static IEnumerable<string> Diagnostics(Profile profile)
    {
        yield return $"profile {profile.Name} errors {profile.Errors} warnings {profile.Warnings}";
        foreach (Diagnostic diagnostic in profile.Diagnostics)
            yield return $"{diagnostic.Origin} {diagnostic.Code} {diagnostic.Message}";
    }

    private static IEnumerable<string> Diff(ProfileDiff diff)
    {
        yield return $"diff {diff.First} -> {diff.Second}: {diff.Added} added, {diff.Removed} removed, {diff.Changed} changed";
        foreach (DiffEntry entry in diff.Entries)
            yield return entry.Sign switch
            {
                '+' => $"+ {entry.Key} = {Shown(entry.After!)}",
                '-' => $"- {entry.Key} = {Shown(entry.Before!)}",
                _ => $"~ {entry.Key}: {Shown(entry.Before!)} -> {Shown(entry.After!)}"
            };
    }

    private static IEnumerable<string> Report(Profile profile)
    {
        yield return "profile " + profile.Name;
        yield return "includes";
        foreach (var line in profile.Tree)
            yield return new string(' ', 2 + 2 * line.Depth) + line.Text;
        yield return "overridden";
        foreach (var entry in profile.Overridden)
            yield return "  " + entry.Key + ": " + string.Join(" -> ", entry.History);
        if (profile.Overridden.Count == 0)
            yield return "  (none)";
        yield return $"keys {profile.Outputs.Count} documents {profile.DocumentKeys} manifest {profile.ManifestKeys} defaults {profile.DefaultKeys}";
        yield return $"dropped {profile.Dropped}";
        yield return $"errors {profile.Errors} warnings {profile.Warnings}";
    }

    private static void Write(string path, IEnumerable<IEnumerable<string>> blocks) =>
        File.WriteAllText(path, string.Join("\n\n", blocks.Select(block => string.Join('\n', block))) + "\n", new UTF8Encoding(false));

    public static void WriteOutputs(string directory, IEnumerable<Profile> profiles, IEnumerable<ProfileDiff> diffs)
    {
        Directory.CreateDirectory(directory);
        Write(Path.Combine(directory, "normalized.txt"), profiles.Select(Normalized));
        Write(Path.Combine(directory, "diagnostics.txt"), profiles.Select(Diagnostics));
        Write(Path.Combine(directory, "diff.txt"), diffs.Select(Diff));
        Write(Path.Combine(directory, "report.txt"), profiles.Select(Report));
    }
}
