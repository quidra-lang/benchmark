abstract record Operand {
    public abstract string Text {
        get;
    }
    public string? Variable => this is VariableOperand v ? v.Name : null;
    public long? Constant => this is ConstantOperand c ? c.Value : null;
    public static Operand Parse(string text) => text[0] == '-' || char.IsAsciiDigit(text[0]) ? new ConstantOperand(long.Parse(text)) : new VariableOperand(text);
}
sealed record ConstantOperand(long Value) : Operand {
    public override string Text => Value.ToString();
}
sealed record VariableOperand(string Name) : Operand {
    public override string Text => Name;
}
sealed record TacExpression(string Kind, string Operation, Operand A, Operand? B) {
    public string Text => Kind == "load" ? $"{Operation}[{A.Text}]" : A.Text + Operation + B!.Text;
    public bool Uses(string name) => A.Variable == name || B?.Variable == name;
}
sealed record Instruction(string Kind) {
    public string? Destination;
    public Operand? A, B;
    public string Operation = "", Target = "", Array = "", Function = "";
    public int Count;
    public List<Operand> Operands => new[] {
        A, B
    }.OfType<Operand>().ToList();
    public List<string> Used => Operands.Select(operand => operand.Variable).OfType<string>().ToList();
    public TacExpression? Expression => Kind is "bin" or "load" ? new(Kind, Kind == "bin" ? Operation : Array, A!, B) : null;
    public string Text {
        get {
            string a = A?.Text ?? "", b = B?.Text ?? "", d = Destination ?? "";
            return Kind switch {
                "copy" => $"{d} = {a}", "bin" => $"{d} = {a} {Operation} {b}", "load" => $"{d} = {Array}[{a}]", "store" => $"{Array}[{a}] = {b}", "goto" => "goto " + Target, "if" => $"if {a} {Operation} {b} goto {Target}", "read" => "read " + d, "return" => A == null ? "return" : "return " + a, "call" => (Destination == null ? "" : d + " = ") + $"call {Function} {Count}", _ => Kind + " " + a
            };
        }
    }
    public static Instruction Move(string destination, Operand a) => new("copy") {
        Destination = destination, A = a
    };
}
abstract record CodeLine;
sealed record LabelLine(string Name) : CodeLine;
sealed record InstructionLine(Instruction Instruction) : CodeLine;
sealed class Function(string name, List<string> parameters, List<CodeLine> code) {
    public string Name = name;
    public List<string> Parameters = parameters;
    public List<CodeLine> Code = code;
    public int Temporary, Preheader;
    public List<Instruction> Instructions => Code.OfType<InstructionLine>().Select(line => line.Instruction).ToList();
    public List<string> Text => new[] {
        "func " + Name + string.Concat(Parameters.Select(parameter => " " + parameter))
    }.Concat(Code.Select(line => line is LabelLine label ? label.Name + ":" : "    " + ((InstructionLine)line).Instruction.Text)).Append("end").ToList();
    public Function DeepCopy() => new(Name, Parameters.ToList(), Code.Select(line => line is InstructionLine instruction ? new InstructionLine(instruction.Instruction with {
    }) : line).ToList()) {
        Temporary = this.Temporary, Preheader = this.Preheader
    };
}
sealed class TacProgram(List<(string Name, int Size)> arrays, List<Function> functions) {
    public List<(string Name, int Size)> Arrays = arrays;
    public List<Function> Functions = functions;
    public List<string> Text {
        get {
            List<string> lines = Arrays.Select(array => $"array {array.Name} {array.Size}").ToList();
            foreach (Function function in Functions) {
                if (lines.Count > 0) lines.Add("");
                lines.AddRange(function.Text);
            } return lines;
        }
    }
}
static class TacParser {
    static (string, Operand) Indexed(string text) {
        int i = text.IndexOf('[');
        return (text[..i], Operand.Parse(text[(i + 1)..^1]));
    }
    public static TacProgram Parse(string text) {
        List<(string, int)> arrays = new();
        List<Function> functions = new();
        foreach (string line in text.Split((char)10)) {
            string[] w = line.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            if (w.Length == 0 || w[0].StartsWith('#')) continue;
            if (w[0] == "array") {
                arrays.Add((w[1], int.Parse(w[2])));
                continue;
            } if (w[0] == "func") {
                functions.Add(new(w[1], w.Skip(2).ToList(), new()));
                continue;
            } if (w[0] == "end") continue;
            Function f = functions.Last();
            if (w.Length == 1 && w[0].EndsWith(':')) {
                f.Code.Add(new LabelLine(w[0][..^1]));
                continue;
            }
            Instruction instruction = new("copy");
            switch (w[0]) {
                case "goto": instruction = new("goto") {
                    Target = w[1]
                };
                break;
                case "if": instruction = new("if") {
                    A = Operand.Parse(w[1]), Operation = w[2], B = Operand.Parse(w[3]), Target = w[5]
                };
                break;
                case "param": case "return": case "read": case "print": instruction = new(w[0]);
                if (w.Length > 1) {
                    if (w[0] == "read") instruction.Destination = w[1];
                    else instruction.A = Operand.Parse(w[1]);
                } break;
                default:
                if (w[0].Contains('[')) {
                    var (array, index) = Indexed(w[0]);
                    instruction = new("store") {
                        Array = array, A = index, B = Operand.Parse(w[2])
                    };
                }
                else {
                    int start = w[0] == "call" ? 0 : 2;
                    string? destination = start == 2 ? w[0] : null;
                    if (w[start] == "call") instruction = new("call") {
                        Destination = destination, Function = w[start + 1], Count = int.Parse(w[start + 2])
                    };
                    else if (w.Length == 5) instruction = new("bin") {
                        Destination = destination, A = Operand.Parse(w[2]), Operation = w[3], B = Operand.Parse(w[4])
                    };
                    else if (w[2].Contains('[')) {
                        var (array, index) = Indexed(w[2]);
                        instruction = new("load") {
                            Destination = destination, Array = array, A = index
                        };
                    }
                    else instruction = Instruction.Move(destination!, Operand.Parse(w[2]));
                }
                break;
            }
            f.Code.Add(new InstructionLine(instruction));
        }
        return new(arrays, functions);
    }
    public static long Operation(string op, long a, long b) => op switch {
        "+" => a + b, "-" => a - b, "*" => a * b, "/" => a / b, "%" => a % b, "<" => a < b ? 1 : 0, "<=" => a <= b ? 1 : 0, ">" => a > b ? 1 : 0, ">=" => a >= b ? 1 : 0, "==" => a == b ? 1 : 0, _ => a != b ? 1 : 0
    };
    public static Dictionary<string, int> Labels(Function function) {
        Dictionary<string, int> labels = new(StringComparer.Ordinal);
        int index = 0;
        foreach (CodeLine line in function.Code) {
            if (line is LabelLine label) labels[label.Name] = index;
            else index++;
        } return labels;
    }
}
