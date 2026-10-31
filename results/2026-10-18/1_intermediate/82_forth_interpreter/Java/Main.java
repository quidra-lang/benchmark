import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class Main {
    static class ForthError extends RuntimeException {
        final String word, reason;
        final Long code;
        ForthError(String word, String reason, Long code) {
            this.word = word;
            this.reason = reason;
            this.code = code;
        }
    }

    static void error(String word, String reason, long code) {
        throw new ForthError(word, reason, code);
    }

    static void syntax(String word, String reason) {
        throw new ForthError(word, reason, null);
    }

    static String upper(String text) {
        StringBuilder result = new StringBuilder();
        for (char c : text.toCharArray()) result.append(c >= 'a' && c <= 'z' ? (char)(c - 'a' + 'A') : c);
        return result.toString();
    }
    static final String COMPILE_ONLY = "IF ELSE THEN DO ?DO LOOP +LOOP LEAVE UNLOOP I J BEGIN UNTIL WHILE REPEAT AGAIN CASE OF ENDOF ENDCASE EXIT RECURSE DOES> ; >R R> R@ ABORT\" ['] {:";
    static final String INTERPRET_ONLY = ": :NONAME FORGET";
    static final String BOTH = ".\" ( \\ TO IS";

    static boolean listed(String word, String list) {
        return Arrays.asList(list.split(" ")).contains(word);
    }

    static class Word {
        String name, raw, kind;
        long here, value, address, deferred, xt;
        Word doesOwner, previous;
        int dictionaryIndex = -1;
        int doesStart;
        List<Instruction> instructions = new ArrayList<>();
        Map<String, Integer> locals = new HashMap<>();
        int localCount;
        Word(String name, String raw, String kind, long here) {
            this.name = name;
            this.raw = raw;
            this.kind = kind;
            this.here = here;
        }
    }

    static class Instruction {
        String kind, spelling, text;
        long value;
        int target, local;
        int[] locals;
        Word word;
        Instruction(String kind, String spelling) {
            this.kind = kind;
            this.spelling = spelling;
        }
    }

    static class Control {
        String kind;
        int index, begin;
        List<Integer> exits = new ArrayList<>();
        Control(String kind, int index, int begin) {
            this.kind = kind;
            this.index = index;
            this.begin = begin;
        }
    }
    final Map<String, Word> builtins = new HashMap<>(), newest = new HashMap<>();
    final List<Word> dictionary = new ArrayList<>(), tokens = new ArrayList<>();
    final List<Long> data = new ArrayList<>(), returns = new ArrayList<>(), memory = new ArrayList<>();

    static class Pending {
        final StringBuilder text = new StringBuilder();
        long spaces;
        Pending append(Object value) {
            String string = String.valueOf(value);
            for (char c : string.toCharArray()) {
                if (c == ' ') spaces++;
                else {
                    text.append(" ".repeat((int)spaces));
                    spaces = 0;
                    text.append(c);
                }
            }
            return this;
        }
        void spaces(long count) {
            if (count > 0) spaces += count;
        }
        boolean isEmpty() {
            return text.isEmpty() && spaces == 0;
        }
        void flush() {
            System.out.println(text);
            text.setLength(0);
            spaces = 0;
        }
    }
    final Pending pending = new Pending();
    final List<Control> controls = new ArrayList<>();
    Word compiling;
    String line;
    int position, depth;
    Main() {
        memory.add(10L);
        String names = "+ - * / MOD /MOD */ */MOD NEGATE ABS MIN MAX 1+ 1- 2* 2/ = <> < > 0= 0<> 0< 0> WITHIN TRUE FALSE AND OR XOR INVERT DUP ?DUP DROP SWAP OVER ROT -ROT NIP TUCK 2DUP 2DROP 2SWAP 2OVER DEPTH PICK ROLL . .R .S ? CR EMIT SPACE SPACES BL ! @ +! , ALLOT HERE CELLS CELL+ BASE HEX DECIMAL CREATE VARIABLE CONSTANT VALUE DEFER ' EXECUTE CATCH THROW ABORT WORDS";
        for (String name : names.split(" ")) builtins.put(name, new Word(name, name, "builtin", 0));
    }

    String readWord() {
        while (position < line.length() && line.charAt(position) == ' ') position++;
        if (position == line.length()) return null;
        int start = position;
        while (position < line.length() && line.charAt(position) != ' ') position++;
        return line.substring(start, position);
    }

    String readName(String owner) {
        String name = readWord();
        if (name == null) error(owner, "missing name", -16);
        return name;
    }

    Word find(String name) {
        name = upper(name);
        return newest.getOrDefault(name, builtins.get(name));
    }

    void addUser(Word word) {
        word.previous = newest.get(word.name);
        word.dictionaryIndex = dictionary.size();
        dictionary.add(word);
        newest.put(word.name, word);
    }

    static Long parseNumber(String raw, long base) {
        if (raw.length() == 3 && raw.charAt(0) == '\'' && raw.charAt(2) == '\'') return (long)raw.charAt(1);
        String text = upper(raw);
        if (!text.isEmpty() && "$#%".indexOf(text.charAt(0)) >= 0) {
            base = text.charAt(0) == '$' ? 16 : text.charAt(0) == '#' ? 10 : 2;
            text = text.substring(1);
        } else if (base < 2 || base > 36) return null;
        boolean negative = text.startsWith("-");
        if (negative) text = text.substring(1);
        if (text.isEmpty()) return null;
        long result = 0;
        for (char c : text.toCharArray()) {
            int digit = c >= '0' && c <= '9' ? c - '0' : c >= 'A' && c <= 'Z' ? c - 'A' + 10 : 36;
            if (digit >= base) return null;
            result = result * base + digit;
        }
        return negative ? -result : result;
    }
    Long number(String raw) {
        boolean direct = raw.length() == 3 && raw.charAt(0) == '\'' && raw.charAt(2) == '\'' || !raw.isEmpty() && "$#%".indexOf(raw.charAt(0)) >= 0;
        long base = memory.get(0);
        if (!direct && (base < 2 || base > 36)) error(raw, "invalid base", -40);
        return parseNumber(raw, base);
    }

    void checkName(String raw) {
        String name = upper(raw);
        if (listed(name, COMPILE_ONLY) || listed(name, INTERPRET_ONLY) || listed(name, BOTH) || parseNumber(raw, 10) != null) error(raw, "invalid name", -19);
    }

    void push(long value, String word) {
        if (data.size() == 1000) error(word, "stack overflow", -3);
        data.add(value);
    }
    long[] pop(int count, String word) {
        if (data.size() < count) error(word, "stack underflow", -4);
        long[] result = new long[count];
        int first = data.size() - count;
        for (int i = 0; i < count; i++) result[i] = data.get(first + i);
        data.subList(first, data.size()).clear();
        return result;
    }

    void returnPush(long value, String word) {
        if (returns.size() == 1000) error(word, "return stack overflow", -5);
        returns.add(value);
    }

    void needReturn(int count, String word) {
        if (returns.size() < count) error(word, "return stack underflow", -6);
    }

    int address(long value, String word) {
        if (value < 0 || value % 8 != 0 || value / 8 >= memory.size()) error(word, "invalid address", -9);
        return (int)(value / 8);
    }

    long xt(Word word) {
        if (word.xt == 0) {
            tokens.add(word);
            word.xt = tokens.size();
        }
        return word.xt;
    }

    Word token(long value, String word) {
        if (value < 1 || value > tokens.size()) error(word, "invalid argument", -24);
        return tokens.get((int)value - 1);
    }

    String outputNumber(long value, String word) {
        long base = memory.get(0);
        if (base < 2 || base > 36) error(word, "invalid base", -40);
        return Long.toString(value, (int)base).toUpperCase(java.util.Locale.ROOT);
    }

    void flush() {
        pending.flush();
    }

    Instruction emit(String kind, String spelling) {
        Instruction instruction = new Instruction(kind, spelling);
        compiling.instructions.add(instruction);
        return instruction;
    }

    Control top(String word, String... kinds) {
        if (controls.isEmpty() || !Arrays.asList(kinds).contains(controls.getLast().kind)) syntax(word, "control structure mismatch");
        return controls.getLast();
    }

    Control removeControl() {
        return controls.removeLast();
    }

    void compile(String raw) {
        String word = upper(raw);
        int at = compiling.instructions.size();
        switch (word) {
            case "IF" -> {
                emit("zerojump", raw);
                controls.add(new Control("IF", at, 0));
            }
            case "ELSE" -> {
                Control c = top(raw, "IF");
                emit("jump", raw);
                compiling.instructions.get(c.index).target = at + 1;
                c.kind = "ELSE";
                c.index = at;
            }
            case "THEN" -> {
                Control c = top(raw, "IF", "ELSE");
                compiling.instructions.get(c.index).target = at;
                removeControl();
            }
            case "BEGIN" -> controls.add(new Control("BEGIN", at, at));
            case "UNTIL", "AGAIN" -> {
                Control c = top(raw, "BEGIN");
                emit(word.equals("UNTIL") ? "zerojump" : "jump", raw).target = c.begin;
                removeControl();
            }
            case "WHILE" -> {
                Control c = top(raw, "BEGIN");
                emit("zerojump", raw);
                c.kind = "WHILE";
                c.index = at;
            }
            case "REPEAT" -> {
                Control c = top(raw, "WHILE");
                emit("jump", raw).target = c.begin;
                compiling.instructions.get(c.index).target = at + 1;
                removeControl();
            }
            case "DO", "?DO" -> {
                emit(word, raw);
                controls.add(new Control(word, at, at + 1));
            }
            case "LOOP", "+LOOP" -> {
                Control c = top(raw, "DO", "?DO");
                emit(word, raw).target = c.begin;
                compiling.instructions.get(c.index).target = at + 1;
                for (int leave : c.exits) compiling.instructions.get(leave).target = at + 1;
                removeControl();
            }
            case "LEAVE" -> {
                Control loop = null;
                for (int i = controls.size() - 1; i >= 0; i--) if (controls.get(i).kind.equals("DO") || controls.get(i).kind.equals("?DO")) {
                    loop = controls.get(i);
                    break;
                }
                if (loop == null) syntax(raw, "control structure mismatch");
                emit("LEAVE", raw);
                loop.exits.add(at);
            }
            case "CASE" -> controls.add(new Control("CASE", at, 0));
            case "OF" -> {
                top(raw, "CASE");
                emit("OF", raw);
                controls.add(new Control("OF", at, 0));
            }
            case "ENDOF" -> {
                Control of = top(raw, "OF");
                removeControl();
                Control c = top(raw, "CASE");
                emit("jump", raw);
                compiling.instructions.get(of.index).target = at + 1;
                c.exits.add(at);
            }
            case "ENDCASE" -> {
                Control c = top(raw, "CASE");
                emit("DROP", raw);
                for (int jump : c.exits) compiling.instructions.get(jump).target = at + 1;
                removeControl();
            }
            case "EXIT" -> emit("EXIT", raw);
            case "RECURSE" -> emit("call", raw).word = compiling;
            case "DOES>" -> {
                if (!controls.isEmpty()) syntax(raw, "control structure mismatch");
                emit("DOES>", raw);
            }
            case ">R", "R>", "R@", "I", "J", "UNLOOP" -> emit(word, raw);
            case "[']" -> {
                String name = readName(raw);
                Word target = find(name);
                if (target == null) error(name, "undefined word", -13);
                emit("push", raw).value = xt(target);
            }
            case "{:" -> {
                List<String> names = new ArrayList<>();
                String name;
                boolean closed = false;
                while ((name = readWord()) != null) {
                    if (upper(name).equals(":}")) {
                        closed = true;
                        break;
                    }
                    names.add(name);
                }
                if (!closed) syntax(raw, "unterminated locals");
                List<Integer> locals = new ArrayList<>();
                for (String local : names) {
                    if (local.equals("--")) break;
                    checkName(local);
                    int index = compiling.localCount++;
                    compiling.locals.put(upper(local), index);
                    locals.add(index);
                }
                emit("locals", raw).locals = locals.stream().mapToInt(Integer::intValue).toArray();
            }
            case ";" -> {
                if (!controls.isEmpty()) {
                    String kind = controls.getLast().kind;
                    if (kind.equals("ELSE")) kind = "IF";
                    if (kind.equals("WHILE")) kind = "BEGIN";
                    syntax(raw, "unclosed " + kind);
                }
                Word complete = compiling;
                compiling = null;
                if (complete.name.equals(":NONAME")) push(xt(complete), raw);
                else addUser(complete);
            }
            default -> {
                Integer local = compiling.locals.get(word);
                if (local != null) emit("local", raw).local = local;
                else {
                    Word target = find(word);
                    if (target != null) emit("call", raw).word = target;
                    else {
                        Long value = number(raw);
                        if (value == null) error(raw, "undefined word", -13);
                        emit("push", raw).value = value;
                    }
                }
            }
        }
    }

    void assign(String raw, boolean deferred) {
        String name = readName(raw);
        Integer local = !deferred && compiling != null ? compiling.locals.get(upper(name)) : null;
        if (local != null) {
            emit("setlocal", raw).local = local;
            return;
        }
        Word target = find(name);
        if (target == null) error(name, "undefined word", -13);
        if (!target.kind.equals(deferred ? "defer" : "value")) syntax(name, deferred ? "not deferred" : "not a value");
        if (compiling != null) emit(deferred ? "is" : "to", raw).word = target;
        else {
            long value = pop(1, raw)[0];
            if (deferred) {
                token(value, raw);
                target.deferred = value;
            } else memory.set((int)(target.address / 8), value);
        }
    }

    void process(String raw) {
        String word = upper(raw);
        if (word.equals("\\")) {
            position = line.length();
            return;
        }
        if (word.equals("(")) {
            int end = line.indexOf(')', position);
            if (end < 0) syntax(raw, "unterminated comment");
            position = end + 1;
            return;
        }
        if (compiling == null && listed(word, COMPILE_ONLY)) syntax(raw, "compile only");
        if (compiling != null && listed(word, INTERPRET_ONLY)) syntax(raw, "interpret only");
        if (word.equals(".\"") || word.equals("ABORT\"")) {
            int end = position < line.length() ? line.indexOf('"', position + 1) : -1;
            if (end < 0) syntax(raw, "unterminated string");
            String text = line.substring(position + 1, end);
            position = end + 1;
            if (compiling != null) emit(word.equals(".\"") ? "write" : "abortstring", raw).text = text;
            else pending.append(text);
            return;
        }
        if (word.equals("TO") || word.equals("IS")) {
            assign(raw, word.equals("IS"));
            return;
        }
        if (word.equals(":") || word.equals(":NONAME")) {
            String name = word.equals(":") ? readName(raw) : raw;
            if (word.equals(":")) checkName(name);
            compiling = new Word(word.equals(":") ? upper(name) : ":NONAME", name, "colon", memory.size() * 8L);
            controls.clear();
            return;
        }
        if (word.equals("FORGET")) {
            String name = readName(raw);
            Word target = newest.get(upper(name));
            if (target == null) error(name, "undefined word", -13);
            int index = target.dictionaryIndex;
            long here = target.here;
            for (int i = dictionary.size() - 1; i >= index; i--) {
                Word removed = dictionary.get(i);
                if (removed.previous == null) newest.remove(removed.name);
                else newest.put(removed.name, removed.previous);
            }
            dictionary.subList(index, dictionary.size()).clear();
            memory.subList((int)(here / 8), memory.size()).clear();
            return;
        }
        if (compiling != null) {
            compile(raw);
            return;
        }
        Word target = find(word);
        if (target != null) execute(target, raw);
        else {
            Long value = number(raw);
            if (value == null) error(raw, "undefined word", -13);
            push(value, raw);
        }
    }

    void definition(Word word, int start, String spelling) {
        if (depth == 100) error(spelling, "nesting too deep", -7);
        depth++;
        int returnDepth = returns.size();
        long[] locals = new long[word.localCount];
        int pc = start;
        while (pc < word.instructions.size()) {
            Instruction instruction = word.instructions.get(pc++);
            String raw = instruction.spelling;
            switch (instruction.kind) {
                case "push" -> push(instruction.value, raw);
                case "local" -> push(locals[instruction.local], raw);
                case "setlocal" -> locals[instruction.local] = pop(1, raw)[0];
                case "locals" -> {
                    long[] values = pop(instruction.locals.length, raw);
                    for (int i = 0; i < values.length; i++) locals[instruction.locals[i]] = values[i];
                }
                case "call" -> execute(instruction.word, raw);
                case "write" -> pending.append(instruction.text);
                case "abortstring" -> {
                    if (pop(1, raw)[0] != 0) error(raw, instruction.text, -2);
                }
                case "jump" -> pc = instruction.target;
                case "zerojump" -> {
                    if (pop(1, raw)[0] == 0) pc = instruction.target;
                }
                case "DO", "?DO" -> {
                    long[] values = pop(2, raw);
                    if (instruction.kind.equals("?DO") && values[0] == values[1]) pc = instruction.target;
                    else {
                        returnPush(values[0], raw);
                        returnPush(values[1], raw);
                    }
                }
                case "LOOP", "+LOOP" -> {
                    long step = instruction.kind.equals("LOOP") ? 1 : pop(1, raw)[0];
                    needReturn(2, raw);
                    long index = returns.getLast(), limit = returns.get(returns.size() - 2), before = index - limit, after = index + step - limit;
                    if ((before < 0) != (after < 0)) returns.subList(returns.size() - 2, returns.size()).clear();
                    else {
                        returns.set(returns.size() - 1, index + step);
                        pc = instruction.target;
                    }
                }
                case "LEAVE" -> {
                    needReturn(2, raw);
                    returns.subList(returns.size() - 2, returns.size()).clear();
                    pc = instruction.target;
                }
                case "OF" -> {
                    long[] values = pop(2, raw);
                    if (values[0] != values[1]) {
                        push(values[0], raw);
                        pc = instruction.target;
                    }
                }
                case "DROP" -> pop(1, raw);
                case ">R" -> returnPush(pop(1, raw)[0], raw);
                case "R>" -> {
                    needReturn(1, raw);
                    push(returns.removeLast(), raw);
                }
                case "R@", "I" -> {
                    needReturn(1, raw);
                    push(returns.getLast(), raw);
                }
                case "J" -> {
                    needReturn(3, raw);
                    push(returns.get(returns.size() - 3), raw);
                }
                case "UNLOOP" -> {
                    needReturn(2, raw);
                    returns.subList(returns.size() - 2, returns.size()).clear();
                }
                case "to" -> memory.set((int)(instruction.word.address / 8), pop(1, raw)[0]);
                case "is" -> {
                    long value = pop(1, raw)[0];
                    token(value, raw);
                    instruction.word.deferred = value;
                }
                case "EXIT" -> pc = word.instructions.size();
                case "DOES>" -> {
                    if (dictionary.isEmpty() || !dictionary.getLast().kind.equals("create")) error(raw, "no CREATE word", -31);
                    Word created = dictionary.getLast();
                    created.doesOwner = word;
                    created.doesStart = pc;
                    pc = word.instructions.size();
                }
                default -> throw new IllegalStateException();
            }
        }
        if (returns.size() > returnDepth) returns.subList(returnDepth, returns.size()).clear();
        depth--;
    }

    void execute(Word word, String spelling) {
        while (word.kind.equals("defer")) {
            if (word.deferred == 0) error(spelling, "deferred word not set", -21);
            word = token(word.deferred, spelling);
            spelling = word.name;
        }
        switch (word.kind) {
            case "builtin" -> builtin(word.name, spelling);
            case "colon" -> definition(word, 0, spelling);
            case "constant" -> push(word.value, spelling);
            case "value" -> push(memory.get((int)(word.address / 8)), spelling);
            case "create", "variable" -> {
                push(word.address, spelling);
                if (word.doesOwner != null) definition(word.doesOwner, word.doesStart, spelling);
            }
            default -> throw new IllegalStateException();
        }
    }

    void builtin(String word, String raw) {
        switch (word) {
            case "+", "-", "*", "/", "MOD", "/MOD", "MIN", "MAX", "=", "<>", "<", ">", "AND", "OR", "XOR" -> {
                long[] v = pop(2, raw);
                long a = v[0], b = v[1];
                if (word.equals("/") || word.equals("MOD") || word.equals("/MOD")) {
                    if (b == 0) error(raw, "division by zero", -10);
                    long q = Math.floorDiv(a, b), r = a - b * q;
                    if (!word.equals("/")) push(r, raw);
                    if (!word.equals("MOD")) push(q, raw);
                } else push(switch (word) {
                    case "+" -> a + b;
                    case "-" -> a - b;
                    case "*" -> a * b;
                    case "MIN" -> Math.min(a, b);
                    case "MAX" -> Math.max(a, b);
                    case "=" -> a == b ? -1 : 0;
                    case "<>" -> a != b ? -1 : 0;
                    case "<" -> a < b ? -1 : 0;
                    case ">" -> a > b ? -1 : 0;
                    case "AND" -> a & b;
                    case "OR" -> a | b;
                    default -> a ^ b;
                }, raw);
            }
            case "*/", "*/MOD" -> {
                long[] v = pop(3, raw);
                if (v[2] == 0) error(raw, "division by zero", -10);
                long product = v[0] * v[1], quotient = Math.floorDiv(product, v[2]);
                if (word.equals("*/MOD")) push(product - v[2] * quotient, raw);
                push(quotient, raw);
            }
            case "NEGATE", "ABS", "1+", "1-", "2*", "2/", "0=", "0<>", "0<", "0>", "INVERT", "CELLS", "CELL+" -> {
                long a = pop(1, raw)[0];
                push(switch (word) {
                    case "NEGATE" -> -a;
                    case "ABS" -> Math.abs(a);
                    case "1+" -> a + 1;
                    case "1-" -> a - 1;
                    case "2*" -> 2 * a;
                    case "2/" -> Math.floorDiv(a, 2);
                    case "0=" -> a == 0 ? -1 : 0;
                    case "0<>" -> a != 0 ? -1 : 0;
                    case "0<" -> a < 0 ? -1 : 0;
                    case "0>" -> a > 0 ? -1 : 0;
                    case "INVERT" -> ~a;
                    case "CELLS" -> a * 8;
                    default -> a + 8;
                }, raw);
            }
            case "WITHIN" -> {
                long[] v = pop(3, raw);
                push(v[1] <= v[0] && v[0] < v[2] ? -1 : 0, raw);
            }
            case "TRUE", "FALSE", "BL", "BASE", "HERE", "DEPTH" -> push(word.equals("TRUE") ? -1 : word.equals("BL") ? 32 : word.equals("HERE") ? memory.size() * 8L : word.equals("DEPTH") ? data.size() : 0, raw);
            case "DUP", "?DUP", "DROP" -> {
                long a = pop(1, raw)[0];
                if (!word.equals("DROP")) {
                    push(a, raw);
                    if (word.equals("DUP") || a != 0) push(a, raw);
                }
            }
            case "SWAP", "OVER", "NIP", "TUCK", "2DUP", "2DROP" -> {
                long[] v = pop(2, raw);
                long a = v[0], b = v[1];
                switch (word) {
                    case "SWAP" -> {
                        push(b, raw);
                        push(a, raw);
                    }
                    case "OVER" -> {
                        push(a, raw);
                        push(b, raw);
                        push(a, raw);
                    }
                    case "NIP" -> push(b, raw);
                    case "TUCK" -> {
                        push(b, raw);
                        push(a, raw);
                        push(b, raw);
                    }
                    case "2DUP" -> {
                        push(a, raw);
                        push(b, raw);
                        push(a, raw);
                        push(b, raw);
                    }
                }
            }
            case "ROT", "-ROT" -> {
                long[] v = pop(3, raw);
                int[] order = word.equals("ROT") ? new int[]{1, 2, 0} : new int[]{2, 0, 1};
                for (int i : order) push(v[i], raw);
            }
            case "2SWAP", "2OVER" -> {
                long[] v = pop(4, raw);
                int[] order = word.equals("2SWAP") ? new int[]{2, 3, 0, 1} : new int[]{0, 1, 2, 3, 0, 1};
                for (int i : order) push(v[i], raw);
            }
            case "PICK", "ROLL" -> {
                long index = pop(1, raw)[0];
                if (index < 0) error(raw, "invalid argument", -24);
                if (index >= data.size()) error(raw, "stack underflow", -4);
                int at = data.size() - 1 - (int)index;
                long value = word.equals("ROLL") ? data.remove(at) : data.get(at);
                push(value, raw);
            }
            case "." -> pending.append(outputNumber(pop(1, raw)[0], raw)).append(' ');
            case ".R" -> {
                long[] v = pop(2, raw);
                String text = outputNumber(v[0], raw);
                if (v[1] > text.length()) pending.spaces(v[1] - text.length());
                pending.append(text);
            }
            case ".S" -> {
                String count = outputNumber(data.size(), raw);
                pending.append('<').append(count).append("> ");
                for (long value : data) pending.append(outputNumber(value, raw)).append(' ');
            }
            case "?" -> {
                int address = address(pop(1, raw)[0], raw);
                pending.append(outputNumber(memory.get(address), raw)).append(' ');
            }
            case "CR" -> flush();
            case "SPACE" -> pending.append(' ');
            case "SPACES" -> {
                long n = pop(1, raw)[0];
                if (n > 0) pending.spaces(n);
            }
            case "EMIT" -> {
                long value = pop(1, raw)[0];
                if (value < 32 || value > 126) error(raw, "invalid argument", -24);
                pending.append((char)value);
            }
            case "!", "+!" -> {
                long[] v = pop(2, raw);
                int at = address(v[1], raw);
                memory.set(at, word.equals("!") ? v[0] : memory.get(at) + v[0]);
            }
            case "@" -> {
                int at = address(pop(1, raw)[0], raw);
                push(memory.get(at), raw);
            }
            case "," -> memory.add(pop(1, raw)[0]);
            case "ALLOT" -> {
                long n = pop(1, raw)[0];
                if (n < 0 || n % 8 != 0) error(raw, "invalid argument", -24);
                for (long i = 0; i < n / 8; i++) memory.add(0L);
            }
            case "HEX", "DECIMAL" -> memory.set(0, word.equals("HEX") ? 16L : 10L);
            case "CREATE", "VARIABLE", "CONSTANT", "VALUE", "DEFER" -> {
                String name = readName(raw);
                checkName(name);
                long value = word.equals("CONSTANT") || word.equals("VALUE") ? pop(1, raw)[0] : 0;
                Word created = new Word(upper(name), name, word.toLowerCase(java.util.Locale.ROOT), memory.size() * 8L);
                created.address = created.here;
                created.value = value;
                addUser(created);
                if (word.equals("VARIABLE") || word.equals("VALUE")) memory.add(value);
            }
            case "'" -> {
                String name = readName(raw);
                Word target = find(name);
                if (target == null) error(name, "undefined word", -13);
                push(xt(target), raw);
            }
            case "EXECUTE" -> {
                Word target = token(pop(1, raw)[0], raw);
                execute(target, target.name);
            }
            case "CATCH" -> {
                Word target = token(pop(1, raw)[0], raw);
                List<Long> saved = new ArrayList<>(data);
                int returnDepth = returns.size(), savedDepth = depth;
                long code = 0;
                try {
                    execute(target, target.name);
                } catch (ForthError failure) {
                    if (failure.code == null) throw failure;
                    data.clear();
                    data.addAll(saved);
                    if (returns.size() > returnDepth) returns.subList(returnDepth, returns.size()).clear();
                    depth = savedDepth;
                    code = failure.code;
                }
                push(code, raw);
            }
            case "THROW" -> {
                long code = pop(1, raw)[0];
                if (code != 0) error(raw, "exception " + code, code);
            }
            case "ABORT" -> error(raw, "aborted", -1);
            case "WORDS" -> {
                for (int i = dictionary.size() - 1; i >= 0; i--) pending.append(dictionary.get(i).name).append(' ');
            }
            default -> throw new IllegalStateException();
        }
    }

    void input(String text) {
        line = text;
        position = 0;
        try {
            String raw;
            while ((raw = readWord()) != null) process(raw);
        } catch (ForthError failure) {
            if (!pending.isEmpty()) flush();
            System.out.println("ERROR " + failure.word + ": " + failure.reason);
            data.clear();
            returns.clear();
            depth = 0;
            compiling = null;
            controls.clear();
        }
        if (!pending.isEmpty()) flush();
    }
    public static void main(String[] args) throws Exception {
        Main forth = new Main();
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
        String line;
        while ((line = reader.readLine()) != null && !line.equals("BYE")) forth.input(line);
        if (forth.compiling != null) System.out.println("ERROR " + forth.compiling.raw + ": unterminated definition");
    }
}
