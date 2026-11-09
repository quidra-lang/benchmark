using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

sealed record CollectorEntry(string name, string type, int young, int age);
sealed class Config {
    public int heap, width;
    public readonly List<CollectorEntry> collectors = new();
    public List<string> maps = new();
    public readonly List<int> windows = new();
}
sealed class Command {
    public readonly int line;
    public readonly string name;
    public int pointers, data, slot, field, count;
    public int source = -1;
    public string label = "";
    public Command(int line, string name) {
        this.line = line;
        this.name = name;
    }
}
sealed record Parsed(Command command, string error);
static class Mutator {
    public static readonly string[] NAMES = { "ALLOC", "PUSH",      "LOAD",      "POP",
                                              "SET",   "OVERWRITE", "CHECKPOINT" };
    public static List<string>
    Lines(string name) => File.ReadAllLines(Path.Combine("input", name), Encoding.ASCII).ToList();
    public static Config ReadConfig() {
        Config config = new();
        foreach (string line in Lines("config.txt")) {
            string[] fields = line.Split(' ');
            switch (fields[0]) {
            case "HEAP":
                config.heap = int.Parse(fields[1]);
                break;
            case "COLLECTOR":
                config.collectors.Add(new CollectorEntry(fields[1], fields[2],
                                                         fields.Length > 3 ? int.Parse(fields[3]) : 0,
                                                         fields.Length > 4 ? int.Parse(fields[4]) : 0));
                break;
            case "MAPS":
                config.maps = fields[1..].ToList();
                break;
            case "MMU":
                for (int i = 1; i < fields.Length; i++)
                    config.windows.Add(int.Parse(fields[i]));
                break;
            default:
                config.width = int.Parse(fields[1]);
                break;
            }
        }
        return config;
    }
    public static Parsed Parse(int line, string text) {
        string[] tokens = text.Split(' ', StringSplitOptions.None);
        string form = tokens[0] switch { "ALLOC" or "LOAD" => "nn",
                                         "OVERWRITE" => "nr",
                                         "PUSH" => "r",
                                         "POP" => "n",
                                         "SET" => "nnr",
                                         "CHECKPOINT" => "l",
                                         _ => "" };
        if (form.Length == 0 || tokens.Length != form.Length + 1)
            return new Parsed(null, "syntax");
        for (int i = 0; i < form.Length; i++) {
            string token = tokens[i + 1];
            char kind = form[i];
            if (kind == 'l') {
                if (!Regex.IsMatch(token, @"\A[a-z0-9_]{1,16}\z"))
                    return new Parsed(null, "syntax");
            } else if (!(kind == 'r' && token == "-") && !Regex.IsMatch(token, @"\A(?:0|[1-9][0-9]{0,3})\z"))
                return new Parsed(null, "syntax");
        }
        Command command = new(line, tokens[0]);
        switch (command.name) {
        case "ALLOC":
            command.pointers = int.Parse(tokens[1]);
            command.data = int.Parse(tokens[2]);
            break;
        case "PUSH":
            command.source = tokens[1] == "-" ? -1 : int.Parse(tokens[1]);
            break;
        case "POP":
            command.count = int.Parse(tokens[1]);
            break;
        case "LOAD":
        case "SET":
            command.slot = int.Parse(tokens[1]);
            command.field = int.Parse(tokens[2]);
            if (command.name == "SET")
                command.source = tokens[3] == "-" ? -1 : int.Parse(tokens[3]);
            break;
        case "OVERWRITE":
            command.slot = int.Parse(tokens[1]);
            command.source = tokens[2] == "-" ? -1 : int.Parse(tokens[2]);
            break;
        default:
            command.label = tokens[1];
            break;
        }
        if ((command.name == "ALLOC" && (command.pointers > 6 || command.data > 24)) ||
            (command.name == "POP" && command.count == 0))
            return new Parsed(command, "range");
        return new Parsed(command, "");
    }
}
