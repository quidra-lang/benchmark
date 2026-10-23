using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;

class Program
{
    class ForthError(string word, string reason, long? code) : Exception(reason)
    {
        public string Word = word, Reason = reason;
        public long? Code = code;
    }

    static void Error(string word, string reason, long code) => throw new ForthError(word, reason, code);

    static void Syntax(string word, string reason) => throw new ForthError(word, reason, null);

    static string Upper(string text) => string.Concat(text.Select(c => c is >= 'a' and <= 'z' ? (char)(c - 'a' + 'A') : c));
    const string CompileOnly = "IF ELSE THEN DO ?DO LOOP +LOOP LEAVE UNLOOP I J BEGIN UNTIL WHILE REPEAT AGAIN CASE OF ENDOF ENDCASE EXIT RECURSE DOES> ; >R R> R@ ABORT\" ['] {:";
    const string InterpretOnly = ": :NONAME FORGET";
    const string Both = ".\" ( \\ TO IS";

    static bool Listed(string word, string list) => list.Split(' ').Contains(word);

    static T RemoveLast<T>(List<T> list)
    {
        T value = list[^1];
        list.RemoveAt(list.Count - 1);
        return value;
    }

    class Word(string name, string raw, string kind, long here)
    {
        public string Name = name, Raw = raw, Kind = kind;
        public long Here = here, Value, Address, Deferred, Xt;
        public Word? DoesOwner, Previous;
        public int DictionaryIndex = -1;
        public int DoesStart;
        public List<Instruction> Instructions = new();
        public Dictionary<string, int> Locals = new(StringComparer.Ordinal);
        public int LocalCount;
    }

    class Instruction(string kind, string spelling)
    {
        public string Kind = kind, Spelling = spelling;
        public string Text = "";
        public long Value;
        public int Target, Local;
        public int[] Locals = Array.Empty<int>();
        public Word? Word;
    }

    class Control(string kind, int index, int begin)
    {
        public string Kind = kind;
        public int Index = index, Begin = begin;
        public List<int> Exits = new();
    }
    readonly Dictionary<string, Word> builtins = new(StringComparer.Ordinal), newest = new(StringComparer.Ordinal);
    readonly List<Word> dictionary = new(), tokens = new();
    readonly List<long> data = new(), returns = new(), memory = new() { 10 };

    class Pending
    {
        readonly StringBuilder text = new();
        long spaces;
        public long Length => text.Length + spaces;
        public Pending Append(object value)
        {
            foreach (char c in Convert.ToString(value, CultureInfo.InvariantCulture)!)
            {
                if (c == ' ') spaces++;
                else
                {
                    text.Append(' ', (int)spaces);
                    spaces = 0;
                    text.Append(c);
                }
            }
            return this;
        }
        public Pending Append(char value, int count)
        {
            if (value == ' ') spaces += count;
            else for (int i = 0; i < count; i++) Append(value);
            return this;
        }
        public void Flush()
        {
            Console.WriteLine(text);
            text.Clear();
            spaces = 0;
        }
    }
    readonly Pending pending = new();
    readonly List<Control> controls = new();
    Word? compiling;
    string line = "";
    int position, depth;
    Program()
    {
        const string names = "+ - * / MOD /MOD */ */MOD NEGATE ABS MIN MAX 1+ 1- 2* 2/ = <> < > 0= 0<> 0< 0> WITHIN TRUE FALSE AND OR XOR INVERT DUP ?DUP DROP SWAP OVER ROT -ROT NIP TUCK 2DUP 2DROP 2SWAP 2OVER DEPTH PICK ROLL . .R .S ? CR EMIT SPACE SPACES BL ! @ +! , ALLOT HERE CELLS CELL+ BASE HEX DECIMAL CREATE VARIABLE CONSTANT VALUE DEFER ' EXECUTE CATCH THROW ABORT WORDS";
        foreach (string name in names.Split(' ')) builtins[name] = new Word(name, name, "builtin", 0);
    }
    string? ReadWord()
    {
        while (position < line.Length && line[position] == ' ') position++;
        if (position == line.Length) return null;
        int start = position;
        while (position < line.Length && line[position] != ' ') position++;
        return line[start..position];
    }

    string ReadName(string owner)
    {
        string? name = ReadWord();
        if (name == null) Error(owner, "missing name", -16);
        return name!;
    }

    Word? Find(string name)
    {
        name = Upper(name);
        return newest.GetValueOrDefault(name) ?? builtins.GetValueOrDefault(name);
    }

    void AddUser(Word word)
    {
        word.Previous = newest.GetValueOrDefault(word.Name);
        word.DictionaryIndex = dictionary.Count;
        dictionary.Add(word);
        newest[word.Name] = word;
    }

    static long? ParseNumber(string raw, long radix)
    {
        if (raw.Length == 3 && raw[0] == '\'' && raw[2] == '\'') return raw[1];
        string text = Upper(raw);
        if (text.Length > 0 && "$#%".Contains(text[0]))
        {
            radix = text[0] == '$' ? 16 : text[0] == '#' ? 10 : 2;
            text = text[1..];
        }
        else if (radix < 2 || radix > 36) return null;
        bool negative = text.StartsWith('-');
        if (negative) text = text[1..];
        if (text.Length == 0) return null;
        foreach (char c in text)
        {
            int digit = c is >= '0' and <= '9' ? c - '0' : c is >= 'A' and <= 'Z' ? c - 'A' + 10 : 36;
            if (digit >= radix) return null;
        }
        long value = 0;
        foreach (char c in text) value = value * radix + (c <= '9' ? c - '0' : c - 'A' + 10);
        return negative ? -value : value;
    }
    long? Number(string raw)
    {
        bool direct = raw.Length == 3 && raw[0] == '\'' && raw[2] == '\'' || raw.Length > 0 && "$#%".Contains(raw[0]);
        long radix = memory[0];
        if (!direct && (radix < 2 || radix > 36)) Error(raw, "invalid base", -40);
        return ParseNumber(raw, radix);
    }

    static void CheckName(string raw)
    {
        string name = Upper(raw);
        if (Listed(name, CompileOnly) || Listed(name, InterpretOnly) || Listed(name, Both) || ParseNumber(raw, 10).HasValue) Error(raw, "invalid name", -19);
    }

    void Push(long value, string word)
    {
        if (data.Count == 1000) Error(word, "stack overflow", -3);
        data.Add(value);
    }
    long[] Pop(int count, string word)
    {
        if (data.Count < count) Error(word, "stack underflow", -4);
        int first = data.Count - count;
        long[] result = data.GetRange(first, count).ToArray();
        data.RemoveRange(first, count);
        return result;
    }

    void ReturnPush(long value, string word)
    {
        if (returns.Count == 1000) Error(word, "return stack overflow", -5);
        returns.Add(value);
    }

    void NeedReturn(int count, string word)
    {
        if (returns.Count < count) Error(word, "return stack underflow", -6);
    }

    int Address(long value, string word)
    {
        if (value < 0 || value % 8 != 0 || value / 8 >= memory.Count) Error(word, "invalid address", -9);
        return (int)(value / 8);
    }

    long Xt(Word word)
    {
        if (word.Xt == 0)
        {
            tokens.Add(word);
            word.Xt = tokens.Count;
        }
        return word.Xt;
    }

    Word Token(long value, string word)
    {
        if (value < 1 || value > tokens.Count) Error(word, "invalid argument", -24);
        return tokens[(int)value - 1];
    }

    string OutputNumber(long value, string word)
    {
        long radix = memory[0];
        if (radix < 2 || radix > 36) Error(word, "invalid base", -40);
        long magnitude = Math.Abs(value);
        StringBuilder text = new();
        do
        {
            int digit = (int)(magnitude % radix);
            text.Append((char)(digit < 10 ? '0' + digit : 'A' + digit - 10));
            magnitude /= radix;
        }
        while (magnitude != 0);
        if (value < 0) text.Append('-');
        return new string(text.ToString().Reverse().ToArray());
    }

    void Flush() => pending.Flush();

    Instruction Emit(string kind, string spelling)
    {
        Instruction instruction = new(kind, spelling);
        compiling!.Instructions.Add(instruction);
        return instruction;
    }

    Control Top(string word, params string[] kinds)
    {
        if (controls.Count == 0 || !kinds.Contains(controls[^1].Kind)) Syntax(word, "control structure mismatch");
        return controls[^1];
    }

    void Compile(string raw)
    {
        string word = Upper(raw);
        int at = compiling!.Instructions.Count;
        switch (word)
        {
            case "IF":
                Emit("zerojump", raw);
                controls.Add(new("IF", at, 0));
                break;
            case "ELSE":
            {
                Control c = Top(raw, "IF");
                Emit("jump", raw);
                compiling.Instructions[c.Index].Target = at + 1;
                c.Kind = "ELSE";
                c.Index = at;
                break;
            }
            case "THEN":
            {
                Control c = Top(raw, "IF", "ELSE");
                compiling.Instructions[c.Index].Target = at;
                RemoveLast(controls);
                break;
            }
            case "BEGIN":
                controls.Add(new("BEGIN", at, at));
                break;
            case "UNTIL":
            case "AGAIN":
            {
                Control c = Top(raw, "BEGIN");
                Emit(word == "UNTIL" ? "zerojump" : "jump", raw).Target = c.Begin;
                RemoveLast(controls);
                break;
            }
            case "WHILE":
            {
                Control c = Top(raw, "BEGIN");
                Emit("zerojump", raw);
                c.Kind = "WHILE";
                c.Index = at;
                break;
            }
            case "REPEAT":
            {
                Control c = Top(raw, "WHILE");
                Emit("jump", raw).Target = c.Begin;
                compiling.Instructions[c.Index].Target = at + 1;
                RemoveLast(controls);
                break;
            }
            case "DO":
            case "?DO":
                Emit(word, raw);
                controls.Add(new(word, at, at + 1));
                break;
            case "LOOP":
            case "+LOOP":
            {
                Control c = Top(raw, "DO", "?DO");
                Emit(word, raw).Target = c.Begin;
                compiling.Instructions[c.Index].Target = at + 1;
                foreach (int leave in c.Exits) compiling.Instructions[leave].Target = at + 1;
                RemoveLast(controls);
                break;
            }
            case "LEAVE":
            {
                Control? loop = controls.LastOrDefault(c => c.Kind is "DO" or "?DO");
                if (loop == null) Syntax(raw, "control structure mismatch");
                Emit("LEAVE", raw);
                loop!.Exits.Add(at);
                break;
            }
            case "CASE":
                controls.Add(new("CASE", at, 0));
                break;
            case "OF":
                Top(raw, "CASE");
                Emit("OF", raw);
                controls.Add(new("OF", at, 0));
                break;
            case "ENDOF":
            {
                Control of = Top(raw, "OF");
                RemoveLast(controls);
                Control c = Top(raw, "CASE");
                Emit("jump", raw);
                compiling.Instructions[of.Index].Target = at + 1;
                c.Exits.Add(at);
                break;
            }
            case "ENDCASE":
            {
                Control c = Top(raw, "CASE");
                Emit("DROP", raw);
                foreach (int jump in c.Exits) compiling.Instructions[jump].Target = at + 1;
                RemoveLast(controls);
                break;
            }
            case "EXIT":
                Emit("EXIT", raw);
                break;
            case "RECURSE":
                Emit("call", raw).Word = compiling;
                break;
            case "DOES>":
                if (controls.Count > 0) Syntax(raw, "control structure mismatch");
                Emit("DOES>", raw);
                break;
            case ">R":
            case "R>":
            case "R@":
            case "I":
            case "J":
            case "UNLOOP":
                Emit(word, raw);
                break;
            case "[']":
            {
                string name = ReadName(raw);
                Word? target = Find(name);
                if (target == null) Error(name, "undefined word", -13);
                Emit("push", raw).Value = Xt(target!);
                break;
            }
            case "{:":
            {
                List<string> names = new();
                string? name;
                bool closed = false;
                while ((name = ReadWord()) != null)
                {
                    if (Upper(name) == ":}")
                    {
                        closed = true;
                        break;
                    }
                    names.Add(name);
                }
                if (!closed) Syntax(raw, "unterminated locals");
                List<int> locals = new();
                foreach (string local in names)
                {
                    if (local == "--") break;
                    CheckName(local);
                    int index = compiling.LocalCount++;
                    compiling.Locals[Upper(local)] = index;
                    locals.Add(index);
                }
                Emit("locals", raw).Locals = locals.ToArray();
                break;
            }
            case ";":
            {
                if (controls.Count > 0)
                {
                    string kind = controls[^1].Kind;
                    if (kind == "ELSE") kind = "IF";
                    if (kind == "WHILE") kind = "BEGIN";
                    Syntax(raw, "unclosed " + kind);
                }
                Word complete = compiling;
                compiling = null;
                if (complete.Name == ":NONAME") Push(Xt(complete), raw);
                else AddUser(complete);
                break;
            }
            default:
                if (compiling.Locals.TryGetValue(word, out int localIndex)) Emit("local", raw).Local = localIndex;
                else
                {
                    Word? target = Find(word);
                    if (target != null) Emit("call", raw).Word = target;
                    else
                    {
                        long? value = Number(raw);
                        if (!value.HasValue) Error(raw, "undefined word", -13);
                        Emit("push", raw).Value = value!.Value;
                    }
                }
                break;
        }
    }

    void Assign(string raw, bool deferred)
    {
        string name = ReadName(raw);
        if (!deferred && compiling != null && compiling.Locals.TryGetValue(Upper(name), out int local))
        {
            Emit("setlocal", raw).Local = local;
            return;
        }
        Word? target = Find(name);
        if (target == null) Error(name, "undefined word", -13);
        if (target!.Kind != (deferred ? "defer" : "value")) Syntax(name, deferred ? "not deferred" : "not a value");
        if (compiling != null) Emit(deferred ? "is" : "to", raw).Word = target;
        else
        {
            long value = Pop(1, raw)[0];
            if (deferred)
            {
                Token(value, raw);
                target.Deferred = value;
            }
            else memory[(int)(target.Address / 8)] = value;
        }
    }

    void Process(string raw)
    {
        string word = Upper(raw);
        if (word == "\\")
        {
            position = line.Length;
            return;
        }
        if (word == "(")
        {
            int end = line.IndexOf(')', position);
            if (end < 0) Syntax(raw, "unterminated comment");
            position = end + 1;
            return;
        }
        if (compiling == null && Listed(word, CompileOnly)) Syntax(raw, "compile only");
        if (compiling != null && Listed(word, InterpretOnly)) Syntax(raw, "interpret only");
        if (word is ".\"" or "ABORT\"")
        {
            int end = position < line.Length ? line.IndexOf('"', position + 1) : -1;
            if (end < 0) Syntax(raw, "unterminated string");
            string text = line[(position + 1)..end];
            position = end + 1;
            if (compiling != null) Emit(word == ".\"" ? "write" : "abortstring", raw).Text = text;
            else pending.Append(text);
            return;
        }
        if (word is "TO" or "IS")
        {
            Assign(raw, word == "IS");
            return;
        }
        if (word is ":" or ":NONAME")
        {
            string name = word == ":" ? ReadName(raw) : raw;
            if (word == ":") CheckName(name);
            compiling = new Word(word == ":" ? Upper(name) : ":NONAME", name, "colon", memory.Count * 8L);
            controls.Clear();
            return;
        }
        if (word == "FORGET")
        {
            string name = ReadName(raw);
            Word? target = newest.GetValueOrDefault(Upper(name));
            if (target == null) Error(name, "undefined word", -13);
            int index = target!.DictionaryIndex;
            long here = target.Here;
            for (int i = dictionary.Count - 1; i >= index; i--)
            {
                Word removed = dictionary[i];
                if (removed.Previous == null) newest.Remove(removed.Name);
                else newest[removed.Name] = removed.Previous;
            }
            dictionary.RemoveRange(index, dictionary.Count - index);
            memory.RemoveRange((int)(here / 8), memory.Count - (int)(here / 8));
            return;
        }
        if (compiling != null)
        {
            Compile(raw);
            return;
        }
        Word? target = Find(word);
        if (target != null) Execute(target, raw);
        else
        {
            long? value = Number(raw);
            if (!value.HasValue) Error(raw, "undefined word", -13);
            Push(value!.Value, raw);
        }
    }

    void Definition(Word word, int start, string spelling)
    {
        if (depth == 100) Error(spelling, "nesting too deep", -7);
        depth++;
        int returnDepth = returns.Count;
        long[] locals = new long[word.LocalCount];
        int pc = start;
        while (pc < word.Instructions.Count)
        {
            Instruction instruction = word.Instructions[pc++];
            string raw = instruction.Spelling;
            switch (instruction.Kind)
            {
                case "push":
                    Push(instruction.Value, raw);
                    break;
                case "local":
                    Push(locals[instruction.Local], raw);
                    break;
                case "setlocal":
                    locals[instruction.Local] = Pop(1, raw)[0];
                    break;
                case "locals":
                {
                    long[] values = Pop(instruction.Locals.Length, raw);
                    for (int i = 0; i < values.Length; i++) locals[instruction.Locals[i]] = values[i];
                    break;
                }
                case "call":
                    Execute(instruction.Word!, raw);
                    break;
                case "write":
                    pending.Append(instruction.Text);
                    break;
                case "abortstring":
                    if (Pop(1, raw)[0] != 0) Error(raw, instruction.Text, -2);
                    break;
                case "jump":
                    pc = instruction.Target;
                    break;
                case "zerojump":
                    if (Pop(1, raw)[0] == 0) pc = instruction.Target;
                    break;
                case "DO":
                case "?DO":
                {
                    long[] values = Pop(2, raw);
                    if (instruction.Kind == "?DO" && values[0] == values[1]) pc = instruction.Target;
                    else
                    {
                        ReturnPush(values[0], raw);
                        ReturnPush(values[1], raw);
                    }
                    break;
                }
                case "LOOP":
                case "+LOOP":
                {
                    long step = instruction.Kind == "LOOP" ? 1 : Pop(1, raw)[0];
                    NeedReturn(2, raw);
                    long index = returns[^1], limit = returns[^2], before = index - limit, after = index + step - limit;
                    if ((before < 0) != (after < 0)) returns.RemoveRange(returns.Count - 2, 2);
                    else
                    {
                        returns[^1] = index + step;
                        pc = instruction.Target;
                    }
                    break;
                }
                case "LEAVE":
                    NeedReturn(2, raw);
                    returns.RemoveRange(returns.Count - 2, 2);
                    pc = instruction.Target;
                    break;
                case "OF":
                {
                    long[] values = Pop(2, raw);
                    if (values[0] != values[1])
                    {
                        Push(values[0], raw);
                        pc = instruction.Target;
                    }
                    break;
                }
                case "DROP":
                    Pop(1, raw);
                    break;
                case ">R":
                    ReturnPush(Pop(1, raw)[0], raw);
                    break;
                case "R>":
                    NeedReturn(1, raw);
                    Push(RemoveLast(returns), raw);
                    break;
                case "R@":
                case "I":
                    NeedReturn(1, raw);
                    Push(returns[^1], raw);
                    break;
                case "J":
                    NeedReturn(3, raw);
                    Push(returns[^3], raw);
                    break;
                case "UNLOOP":
                    NeedReturn(2, raw);
                    returns.RemoveRange(returns.Count - 2, 2);
                    break;
                case "to":
                    memory[(int)(instruction.Word!.Address / 8)] = Pop(1, raw)[0];
                    break;
                case "is":
                {
                    long value = Pop(1, raw)[0];
                    Token(value, raw);
                    instruction.Word!.Deferred = value;
                    break;
                }
                case "EXIT":
                    pc = word.Instructions.Count;
                    break;
                case "DOES>":
                    if (dictionary.Count == 0 || dictionary[^1].Kind != "create") Error(raw, "no CREATE word", -31);
                    Word created = dictionary[^1];
                    created.DoesOwner = word;
                    created.DoesStart = pc;
                    pc = word.Instructions.Count;
                    break;
            }
        }
        if (returns.Count > returnDepth) returns.RemoveRange(returnDepth, returns.Count - returnDepth);
        depth--;
    }

    void Execute(Word word, string spelling)
    {
        while (word.Kind == "defer")
        {
            if (word.Deferred == 0) Error(spelling, "deferred word not set", -21);
            word = Token(word.Deferred, spelling);
            spelling = word.Name;
        }
        switch (word.Kind)
        {
            case "builtin":
                Builtin(word.Name, spelling);
                break;
            case "colon":
                Definition(word, 0, spelling);
                break;
            case "constant":
                Push(word.Value, spelling);
                break;
            case "value":
                Push(memory[(int)(word.Address / 8)], spelling);
                break;
            case "create":
            case "variable":
                Push(word.Address, spelling);
                if (word.DoesOwner != null) Definition(word.DoesOwner, word.DoesStart, spelling);
                break;
        }
    }

    static long FloorDivide(long a, long b)
    {
        long quotient = a / b, remainder = a % b;
        return remainder != 0 && (remainder < 0) != (b < 0) ? quotient - 1 : quotient;
    }

    void Builtin(string word, string raw)
    {
        switch (word)
        {
            case "+":
            case "-":
            case "*":
            case "/":
            case "MOD":
            case "/MOD":
            case "MIN":
            case "MAX":
            case "=":
            case "<>":
            case "<":
            case ">":
            case "AND":
            case "OR":
            case "XOR":
            {
                long[] v = Pop(2, raw);
                long a = v[0], b = v[1];
                if (word is "/" or "MOD" or "/MOD")
                {
                    if (b == 0) Error(raw, "division by zero", -10);
                    long q = FloorDivide(a, b), r = a - b * q;
                    if (word != "/") Push(r, raw);
                    if (word != "MOD") Push(q, raw);
                }
                else Push(word switch
                {
                    "+" => a + b,
                    "-" => a - b,
                    "*" => a * b,
                    "MIN" => Math.Min(a, b),
                    "MAX" => Math.Max(a, b),
                    "=" => a == b ? -1 : 0,
                    "<>" => a != b ? -1 : 0,
                    "<" => a < b ? -1 : 0,
                    ">" => a > b ? -1 : 0,
                    "AND" => a & b,
                    "OR" => a | b,
                    _ => a ^ b
                }, raw);
                break;
            }
            case "*/":
            case "*/MOD":
            {
                long[] v = Pop(3, raw);
                if (v[2] == 0) Error(raw, "division by zero", -10);
                long product = v[0] * v[1], quotient = FloorDivide(product, v[2]);
                if (word == "*/MOD") Push(product - v[2] * quotient, raw);
                Push(quotient, raw);
                break;
            }
            case "NEGATE":
            case "ABS":
            case "1+":
            case "1-":
            case "2*":
            case "2/":
            case "0=":
            case "0<>":
            case "0<":
            case "0>":
            case "INVERT":
            case "CELLS":
            case "CELL+":
            {
                long a = Pop(1, raw)[0];
                Push(word switch
                {
                    "NEGATE" => -a,
                    "ABS" => Math.Abs(a),
                    "1+" => a + 1,
                    "1-" => a - 1,
                    "2*" => 2 * a,
                    "2/" => FloorDivide(a, 2),
                    "0=" => a == 0 ? -1 : 0,
                    "0<>" => a != 0 ? -1 : 0,
                    "0<" => a < 0 ? -1 : 0,
                    "0>" => a > 0 ? -1 : 0,
                    "INVERT" => ~a,
                    "CELLS" => a * 8,
                    _ => a + 8
                }, raw);
                break;
            }
            case "WITHIN":
            {
                long[] v = Pop(3, raw);
                Push(v[1] <= v[0] && v[0] < v[2] ? -1 : 0, raw);
                break;
            }
            case "TRUE":
            case "FALSE":
            case "BL":
            case "BASE":
            case "HERE":
            case "DEPTH":
                Push(word == "TRUE" ? -1 : word == "BL" ? 32 : word == "HERE" ? memory.Count * 8L : word == "DEPTH" ? data.Count : 0, raw);
                break;
            case "DUP":
            case "?DUP":
            case "DROP":
            {
                long a = Pop(1, raw)[0];
                if (word != "DROP")
                {
                    Push(a, raw);
                    if (word == "DUP" || a != 0) Push(a, raw);
                }
                break;
            }
            case "SWAP":
            case "OVER":
            case "NIP":
            case "TUCK":
            case "2DUP":
            case "2DROP":
            {
                long[] v = Pop(2, raw);
                long a = v[0], b = v[1];
                switch (word)
                {
                    case "SWAP":
                        Push(b, raw);
                        Push(a, raw);
                        break;
                    case "OVER":
                        Push(a, raw);
                        Push(b, raw);
                        Push(a, raw);
                        break;
                    case "NIP":
                        Push(b, raw);
                        break;
                    case "TUCK":
                        Push(b, raw);
                        Push(a, raw);
                        Push(b, raw);
                        break;
                    case "2DUP":
                        Push(a, raw);
                        Push(b, raw);
                        Push(a, raw);
                        Push(b, raw);
                        break;
                }
                break;
            }
            case "ROT":
            case "-ROT":
            {
                long[] v = Pop(3, raw);
                foreach (int i in word == "ROT" ? new[] { 1, 2, 0 } : new[] { 2, 0, 1 }) Push(v[i], raw);
                break;
            }
            case "2SWAP":
            case "2OVER":
            {
                long[] v = Pop(4, raw);
                foreach (int i in word == "2SWAP" ? new[] { 2, 3, 0, 1 } : new[] { 0, 1, 2, 3, 0, 1 }) Push(v[i], raw);
                break;
            }
            case "PICK":
            case "ROLL":
            {
                long index = Pop(1, raw)[0];
                if (index < 0) Error(raw, "invalid argument", -24);
                if (index >= data.Count) Error(raw, "stack underflow", -4);
                int at = data.Count - 1 - (int)index;
                long value = data[at];
                if (word == "ROLL") data.RemoveAt(at);
                Push(value, raw);
                break;
            }
            case ".":
                pending.Append(OutputNumber(Pop(1, raw)[0], raw)).Append(' ');
                break;
            case ".R":
            {
                long[] v = Pop(2, raw);
                string text = OutputNumber(v[0], raw);
                if (v[1] > text.Length) pending.Append(' ', (int)v[1] - text.Length);
                pending.Append(text);
                break;
            }
            case ".S":
            {
                string count = OutputNumber(data.Count, raw);
                pending.Append('<').Append(count).Append("> ");
                foreach (long value in data) pending.Append(OutputNumber(value, raw)).Append(' ');
                break;
            }
            case "?":
            {
                int at = Address(Pop(1, raw)[0], raw);
                pending.Append(OutputNumber(memory[at], raw)).Append(' ');
                break;
            }
            case "CR":
                Flush();
                break;
            case "SPACE":
                pending.Append(' ');
                break;
            case "SPACES":
            {
                long n = Pop(1, raw)[0];
                if (n > 0) pending.Append(' ', (int)n);
                break;
            }
            case "EMIT":
            {
                long value = Pop(1, raw)[0];
                if (value < 32 || value > 126) Error(raw, "invalid argument", -24);
                pending.Append((char)value);
                break;
            }
            case "!":
            case "+!":
            {
                long[] v = Pop(2, raw);
                int at = Address(v[1], raw);
                memory[at] = word == "!" ? v[0] : memory[at] + v[0];
                break;
            }
            case "@":
            {
                int at = Address(Pop(1, raw)[0], raw);
                Push(memory[at], raw);
                break;
            }
            case ",":
                memory.Add(Pop(1, raw)[0]);
                break;
            case "ALLOT":
            {
                long n = Pop(1, raw)[0];
                if (n < 0 || n % 8 != 0) Error(raw, "invalid argument", -24);
                for (long i = 0; i < n / 8; i++) memory.Add(0);
                break;
            }
            case "HEX":
            case "DECIMAL":
                memory[0] = word == "HEX" ? 16 : 10;
                break;
            case "CREATE":
            case "VARIABLE":
            case "CONSTANT":
            case "VALUE":
            case "DEFER":
            {
                string name = ReadName(raw);
                CheckName(name);
                long value = word is "CONSTANT" or "VALUE" ? Pop(1, raw)[0] : 0;
                Word created = new(Upper(name), name, word.ToLowerInvariant(), memory.Count * 8L);
                created.Address = created.Here;
                created.Value = value;
                AddUser(created);
                if (word is "VARIABLE" or "VALUE") memory.Add(value);
                break;
            }
            case "'":
            {
                string name = ReadName(raw);
                Word? target = Find(name);
                if (target == null) Error(name, "undefined word", -13);
                Push(Xt(target!), raw);
                break;
            }
            case "EXECUTE":
            {
                Word target = Token(Pop(1, raw)[0], raw);
                Execute(target, target.Name);
                break;
            }
            case "CATCH":
            {
                Word target = Token(Pop(1, raw)[0], raw);
                List<long> saved = new(data);
                int returnDepth = returns.Count, savedDepth = depth;
                long code = 0;
                try
                {
                    Execute(target, target.Name);
                }
                catch (ForthError failure)
                {
                    if (!failure.Code.HasValue) throw;
                    data.Clear();
                    data.AddRange(saved);
                    if (returns.Count > returnDepth) returns.RemoveRange(returnDepth, returns.Count - returnDepth);
                    depth = savedDepth;
                    code = failure.Code.Value;
                }
                Push(code, raw);
                break;
            }
            case "THROW":
            {
                long code = Pop(1, raw)[0];
                if (code != 0) Error(raw, "exception " + code, code);
                break;
            }
            case "ABORT":
                Error(raw, "aborted", -1);
                break;
            case "WORDS":
                for (int i = dictionary.Count - 1; i >= 0; i--) pending.Append(dictionary[i].Name).Append(' ');
                break;
        }
    }

    void Input(string text)
    {
        line = text;
        position = 0;
        try
        {
            string? raw;
            while ((raw = ReadWord()) != null) Process(raw);
        }
        catch (ForthError failure)
        {
            if (pending.Length > 0) Flush();
            Console.WriteLine($"ERROR {failure.Word}: {failure.Reason}");
            data.Clear();
            returns.Clear();
            depth = 0;
            compiling = null;
            controls.Clear();
        }
        if (pending.Length > 0) Flush();
    }

    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Program forth = new();
        string? line;
        while ((line = Console.ReadLine()) != null && line != "BYE") forth.Input(line);
        if (forth.compiling != null) Console.WriteLine($"ERROR {forth.compiling.Raw}: unterminated definition");
    }
}
