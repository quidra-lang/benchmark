using System;
using System.Collections.Generic;
using System.Linq;
readonly record struct CallEdge(int Caller, int Callee);
sealed record Frame(List<long> Locals, int ReturnAddress);
sealed record VMResult(List<string> Output, int[] Counts, int[] Calls, Dictionary<CallEdge, int> Edges, int Executed, int MaxStack, int MaxDepth, int? ErrorPC, string? Message, List<int> Callers);
static class VM {
    public static VMResult Run(List<Instruction> code, List<int> owners, List<int> starts, int area, List<long> input) {
        Dictionary<int, int> unitAt = starts.Select((start, i) => (start, i)).ToDictionary(pair => pair.start, pair => pair.i);
        long[] globals = new long[area];
        List<long> stack = new();
        List<Frame> frames = new();
        int[] counts = new int[code.Count], calls = new int[starts.Count];
        Dictionary<CallEdge, int> edges = new();
        List<string> output = new();
        int pc = 0, read = 0, executed = 0, maxStack = 0, maxDepth = 0;
        string? message = null;
        int? errorPC = null;
        long Pop() {
            long value = stack[^1];
            stack.RemoveAt(stack.Count - 1);
            return value;
        }
        while (true) {
            if (executed == 100000) {
                message = "instruction limit exceeded";
                errorPC = pc;
                break;
            }
            Instruction instruction = code[pc];
            string op = instruction.Op;
            List<long> args = instruction.Operands;
            counts[pc]++;
            executed++;
            int next = pc + 1;
            bool halted = false;
            switch (op) {
                case "PUSH": stack.Add(args[0]);
                break;
                case "POP": Pop();
                break;
                case "LOADG": stack.Add(globals[(int)args[0]]);
                break;
                case "STOREG": globals[(int)args[0]] = Pop();
                break;
                case "LOADL": stack.Add(frames[^1].Locals[(int)args[0]]);
                break;
                case "STOREL": frames[^1].Locals[(int)args[0]] = Pop();
                break;
                case "LOADA": case "STOREA": {
                    long value = op == "STOREA" ? Pop() : 0, index = Pop();
                    if (index < 0 || index >= args[1]) message = $"index {index} out of bounds for array of size {args[1]}";
                    else if (op == "LOADA") stack.Add(globals[(int)(args[0] + index)]);
                    else globals[(int)(args[0] + index)] = value;
                    break;
                }
                case "ADD": case "SUB": case "MUL": case "DIV": case "MOD": {
                    long b = Pop(), a = Pop();
                    if (op is "DIV" or "MOD" && b == 0) message = "division by zero";
                    else {
                        long value = op switch {
                            "ADD" => a + b, "SUB" => a - b, "MUL" => a * b, "DIV" => a / b, _ => a - b * (a / b)
                        };
                        if (value is >= int.MinValue and <= int.MaxValue) stack.Add(value);
                        else message = "integer overflow";
                    } break;
                }
                case "NEG": {
                    long value = -Pop();
                    if (value is >= int.MinValue and <= int.MaxValue) stack.Add(value);
                    else message = "integer overflow";
                    break;
                }
                case "NOT": {
                    long value = Pop();
                    stack.Add(value == 0 ? 1 : 0);
                    break;
                }
                case "LT": case "LE": case "GT": case "GE": case "EQ": case "NE": {
                    long b = Pop(), a = Pop();
                    bool value = op switch {
                        "LT" => a < b, "LE" => a <= b, "GT" => a > b, "GE" => a >= b, "EQ" => a == b, _ => a != b
                    };
                    stack.Add(value ? 1 : 0);
                    break;
                }
                case "JUMP": next = (int)args[0];
                break;
                case "JUMPF": case "JUMPT": {
                    long value = Pop();
                    if (op == "JUMPF" ? value == 0 : value != 0) next = (int)args[0];
                    break;
                }
                case "CALL": if (frames.Count == 100) message = "call depth limit exceeded";
                else {
                    int n = (int)args[1];
                    List<long> values = stack.Skip(stack.Count - n).ToList();
                    stack.RemoveRange(stack.Count - n, n);
                    frames.Add(new(values, pc + 1));
                    next = (int)args[0];
                    int unit = unitAt[next];
                    calls[unit]++;
                    CallEdge edge = new(owners[pc], unit);
                    edges[edge] = edges.GetValueOrDefault(edge) + 1;
                } break;
                case "ENTER": while (frames[^1].Locals.Count < args[0]) frames[^1].Locals.Add(0);
                break;
                case "RET": case "RETV": next = frames[^1].ReturnAddress;
                frames.RemoveAt(frames.Count - 1);
                break;
                case "READ": if (read == input.Count) message = "read past end of input";
                else stack.Add(input[read++]);
                break;
                case "PRINT": {
                    int n = (int)args[0];
                    List<long> values = stack.Skip(stack.Count - n).ToList();
                    stack.RemoveRange(stack.Count - n, n);
                    output.Add(string.Join(" ", values));
                    break;
                }
                case "HALT": halted = true;
                break;
            }
            if (message != null) {
                errorPC = pc;
                break;
            } maxStack = Math.Max(maxStack, stack.Count);
            maxDepth = Math.Max(maxDepth, frames.Count);
            if (halted) break;
            pc = next;
        }
        return new(output, counts, calls, edges, executed, maxStack, maxDepth, errorPC, message, frames.Skip(1).Reverse().Select(frame => frame.ReturnAddress - 1).ToList());
    }
}
