abstract record Operand;
sealed record AssignmentOperand(string Name, string Value) : Operand;
sealed record FileOperand(string Name, int Index) : Operand;
sealed class FileCount(string name) {
    public string Name = name;
    public int Records;
}
sealed class Arguments {
    public List<(string Name, string Value)> Options = new();
    public List<Operand> Operands = new();
    public List<FileCount> Files = new();
    public static Arguments Parse(string text) {
        Arguments result = new();
        static (string Name, string Value)? Assignment(string source) {
            int i = source.IndexOf('=');
            return i < 0 ? null : (source[..i], source[(i + 1)..]);
        }
        static bool Variable(string name) => name.Length > 0 && (Lexer.Letter(name[0]) || name[0] == '_') && name.All(c => Lexer.Letter(c) || Lexer.Digit(c) || c == '_');
        foreach (string line in text.Split((char)10).Where(line => line.Length > 0)) {
            if (line.StartsWith("-F ", StringComparison.Ordinal)) result.Options.Add(("FS", line[3..]));
            else if (line.StartsWith("-v ", StringComparison.Ordinal)) result.Options.Add(Assignment(line[3..])!.Value);
            else {
                var pair = Assignment(line);
                if (pair.HasValue && Variable(pair.Value.Name)) result.Operands.Add(new AssignmentOperand(pair.Value.Name, pair.Value.Value));
                else {
                    result.Operands.Add(new FileOperand(line, result.Files.Count));
                    result.Files.Add(new(line));
                }
            }
        }
        return result;
    }
}
sealed class OutputStream(string name) {
    public string Name = name, Text = "";
    public int Writes;
    public bool Open;
}
sealed class InputStream(string name) {
    public string Name = name;
    public List<string>? Lines;
    public int Position, Reads;
    public bool Opened, Open;
}
sealed class Streams {
    public string Stdout = "";
    public int Writes;
    public List<OutputStream> Outputs = new();
    public List<InputStream> Inputs = new();
    public static bool ValidFile(string text) => text.Length > 0 && !text.StartsWith('.') && text.All(c => Lexer.Letter(c) || Lexer.Digit(c) || "._-".Contains(c));
    public static List<string>? ReadFile(string name) => ValidFile(name) && File.Exists("input/" + name) ? File.ReadAllLines("input/" + name).ToList() : null;
    public void Output(string? name, bool append, string text) {
        if (name == null) {
            Stdout += text;
            Writes++;
            return;
        }
        OutputStream output = Outputs.FirstOrDefault(candidate => candidate.Name == name) ?? new(name);
        if (!Outputs.Contains(output)) Outputs.Add(output);
        if (!output.Open) {
            output.Open = true;
            if (!append) output.Text = "";
        } output.Text += text;
        output.Writes++;
    }
    public (int Status, string? Line) Getline(string name) {
        InputStream input = Inputs.FirstOrDefault(candidate => candidate.Name == name) ?? new(name);
        if (!Inputs.Contains(input)) Inputs.Add(input);
        if (!input.Open) {
            input.Lines = ReadFile(name);
            input.Position = 0;
            if (input.Lines != null) {
                input.Open = true;
                input.Opened = true;
            }
        }
        if (input.Lines == null) return (-1, null);
        if (input.Position == input.Lines.Count) return (0, null);
        string line = input.Lines[input.Position++];
        input.Reads++;
        return (1, line);
    }
    public int Close(string name) {
        bool closed = false;
        OutputStream? output = Outputs.FirstOrDefault(candidate => candidate.Name == name);
        if (output != null) {
            closed |= output.Open;
            output.Open = false;
        }
        InputStream? input = Inputs.FirstOrDefault(candidate => candidate.Name == name);
        if (input != null) {
            closed |= input.Open;
            input.Open = false;
        } return closed ? 0 : -1;
    }
    public void Save() {
        Directory.CreateDirectory("output");
        File.WriteAllText("output/stdout.txt", Stdout);
        foreach (OutputStream output in Outputs) File.WriteAllText("output/" + output.Name, output.Text);
    }
}
