import java.util.*;
final class Codegen {
    enum Op {
        PUSH,
        POP,
        LOADG,
        STOREG,
        LOADL,
        STOREL,
        LOADA,
        STOREA,
        ADD,
        SUB,
        MUL,
        DIV,
        MOD,
        LT,
        LE,
        GT,
        GE,
        EQ,
        NE,
        NEG,
        NOT,
        JUMP,
        JUMPF,
        JUMPT,
        CALL,
        ENTER,
        RET,
        RETV,
        READ,
        PRINT,
        HALT
    }
    record Instruction(Op op, int first, int second, String callee, Lexer.Position position) {
        Instruction(Op op, Lexer.Position position) { this(op, 0, 0, null, position); }
        Instruction(Op op, int first, Lexer.Position position) {
            this(op, first, 0, null, position);
        }
        Instruction target(int target) {
            return new Instruction(op, target, second, callee, position);
        }
        Instruction operation(Op operation) {
            return new Instruction(operation, first, second, callee, position);
        }
    }
    static final Map<String, Op> BINARY =
        Map.ofEntries(Map.entry("+", Op.ADD), Map.entry("-", Op.SUB), Map.entry("*", Op.MUL),
                      Map.entry("/", Op.DIV), Map.entry("%", Op.MOD), Map.entry("<", Op.LT),
                      Map.entry("<=", Op.LE), Map.entry(">", Op.GT), Map.entry(">=", Op.GE),
                      Map.entry("==", Op.EQ), Map.entry("!=", Op.NE));
    static final Set<Op> JUMPS = Set.of(Op.JUMP, Op.JUMPF, Op.JUMPT),
                         CONDITIONAL = Set.of(Op.JUMPF, Op.JUMPT),
                         TRANSFERS = Set.of(Op.JUMP, Op.RET, Op.RETV, Op.HALT);
    static Op inverse(Op op) { return op == Op.JUMPF ? Op.JUMPT : Op.JUMPF; }
    static Op negated(Op op) {
        return switch (op) {
            case LT -> Op.GE;
            case LE -> Op.GT;
            case GT -> Op.LE;
            case GE -> Op.LT;
            case EQ -> Op.NE;
            case NE -> Op.EQ;
            default -> null;
        };
    }
    static final class Label {
        int position = -1;
        List<Integer> fixups = new ArrayList<>();
    }
    record Loop(Label end, Label continuation) {}
    record Block(int start, int end, List<Integer> following) {}
    static final class Unit {
        String name;
        Parser.Function function;
        List<Parser.VariableDecl> slots;
        List<Instruction> before, after;
        int beforeStart, afterStart, depth;
        List<Block> blocks = new ArrayList<>();
        boolean recursive;
        Unit(String name, Parser.Function function, List<Parser.VariableDecl> slots,
             List<Instruction> before) {
            this.name = name;
            this.function = function;
            this.slots = slots;
            this.before = before;
        }
    }
    List<Instruction> code = new ArrayList<>();
    Deque<Loop> loops = new ArrayDeque<>();
    void emit(Op op, Lexer.Position position) { code.add(new Instruction(op, position)); }
    void emit(Op op, int value, Lexer.Position position) {
        code.add(new Instruction(op, value, position));
    }
    void emit(Op op, int first, int second, Lexer.Position position) {
        code.add(new Instruction(op, first, second, null, position));
    }
    void call(String name, int arguments, Lexer.Position position) {
        code.add(new Instruction(Op.CALL, 0, arguments, name, position));
    }
    void jump(Op op, Label target, Lexer.Position position) {
        int index = code.size();
        code.add(new Instruction(op, target.position < 0 ? 0 : target.position, position));
        if (target.position < 0)
            target.fixups.add(index);
    }
    void mark(Label label) {
        label.position = code.size();
        for (int index : label.fixups)
            code.set(index, code.get(index).target(label.position));
        label.fixups.clear();
    }
    void expression(Parser.Expr expression) {
        Lexer.Position position = expression.position;
        switch (expression) {
        case Parser.Literal literal -> emit(Op.PUSH, literal.value, position);
        case Parser.Variable variable ->
            emit(variable.referent.storage == Parser.Storage.GLOBAL ? Op.LOADG : Op.LOADL,
                 variable.referent.storage == Parser.Storage.GLOBAL ? variable.referent.address
                                                                    : variable.referent.slot,
                 position);
        case Parser.ArrayElement array -> {
            expression(array.index);
            emit(Op.LOADA, array.referent.address, array.referent.size, position);
        }
        case Parser.Read ignored -> emit(Op.READ, position);
        case Parser.Call call -> {
            for (Parser.Expr argument : call.arguments)
                expression(argument);
            call(call.referent.name, call.arguments.size(), position);
        }
        case Parser.Unary unary -> {
            expression(unary.operand);
            emit(unary.operator.equals("-") ? Op.NEG : Op.NOT, position);
        }
        case Parser.Binary binary -> {
            if (Set.of("&&", "||").contains(binary.operator)) {
                Label shortcut = new Label(), end = new Label();
                expression(binary.left);
                jump(binary.operator.equals("&&") ? Op.JUMPF : Op.JUMPT, shortcut, position);
                expression(binary.right);
                jump(Op.JUMP, end, position);
                mark(shortcut);
                emit(Op.PUSH, binary.operator.equals("||") ? 1 : 0, position);
                mark(end);
            } else {
                expression(binary.left);
                expression(binary.right);
                emit(BINARY.get(binary.operator), position);
            }
        }
        }
    }
    void statement(Parser.Statement statement) {
        Lexer.Position position = statement.position();
        switch (statement) {
        case Parser.VariableDecl variable -> {
            if (variable.initializer == null)
                emit(Op.PUSH, 0, variable.namePosition);
            else
                expression(variable.initializer);
            emit(Op.STOREL, variable.slot, variable.namePosition);
        }
        case Parser.Assignment assignment -> {
            if (assignment.index != null)
                expression(assignment.index);
            expression(assignment.value);
            Parser.VariableDecl referent = assignment.referent;
            if (assignment.index != null)
                emit(Op.STOREA, referent.address, referent.size, position);
            else
                emit(referent.storage == Parser.Storage.GLOBAL ? Op.STOREG : Op.STOREL,
                     referent.storage == Parser.Storage.GLOBAL ? referent.address : referent.slot,
                     position);
        }
        case Parser.CallStatement call -> {
            expression(call.expression);
            if (call.expression.type != Parser.Type.VOID)
                emit(Op.POP, position);
        }
        case Parser.Print print -> {
            for (Parser.Expr argument : print.arguments)
                expression(argument);
            emit(Op.PRINT, print.arguments.size(), position);
        }
        case Parser.If conditional -> {
            Label alternative = new Label(), end = new Label();
            expression(conditional.condition);
            jump(Op.JUMPF, alternative, position);
            statement(conditional.thenStatement);
            if (conditional.otherwise == null)
                mark(alternative);
            else {
                jump(Op.JUMP, end, position);
                mark(alternative);
                statement(conditional.otherwise);
                mark(end);
            }
        }
        case Parser.While loop -> {
            Label start = new Label(), end = new Label();
            mark(start);
            expression(loop.condition);
            jump(Op.JUMPF, end, position);
            loops.push(new Loop(end, start));
            statement(loop.body);
            loops.pop();
            jump(Op.JUMP, start, position);
            mark(end);
        }
        case Parser.For loop -> {
            Label start = new Label(), update = new Label(), end = new Label();
            if (loop.initial != null)
                statement(loop.initial);
            mark(start);
            if (loop.condition != null) {
                expression(loop.condition);
                jump(Op.JUMPF, end, position);
            }
            loops.push(new Loop(end, update));
            statement(loop.body);
            loops.pop();
            mark(update);
            if (loop.update != null)
                statement(loop.update);
            jump(Op.JUMP, start, position);
            mark(end);
        }
        case Parser.Flow flow ->
            jump(Op.JUMP,
                 flow.kind().equals("continue") ? loops.peek().continuation() : loops.peek().end(),
                 position);
        case Parser.Return returned -> {
            if (returned.value == null)
                emit(Op.RET, position);
            else {
                expression(returned.value);
                emit(Op.RETV, position);
            }
        }
        case Parser.Block block -> {
            for (Parser.Statement child : block.statements)
                statement(child);
        }
        case Parser.Empty ignored -> {
        }
        }
    }
    static List<Parser.VariableDecl> assignSlots(Parser.Function function) {
        List<Parser.VariableDecl> declarations = new ArrayList<>();
        Deque<Parser.Statement> pending = new ArrayDeque<>();
        pending.push(function.body);
        while (!pending.isEmpty()) {
            Parser.Statement statement = pending.pop();
            if (statement instanceof Parser.VariableDecl variable)
                declarations.add(variable);
            for (Parser.Statement child : Parser.statementChildren(statement))
                pending.push(child);
        }
        declarations.sort(Comparator.comparing(variable -> variable.namePosition));
        List<Parser.VariableDecl> slots = new ArrayList<>(function.parameters);
        slots.addAll(declarations);
        for (int i = 0; i < slots.size(); i++)
            slots.get(i).slot = i;
        return slots;
    }
    record Generated(List<Unit> units, int globalSize) {}
    static Generated generate(List<Parser.VariableDecl> globals, List<Parser.Function> functions,
                              Parser.Function main) {
        int address = 0;
        for (Parser.VariableDecl variable : globals) {
            variable.address = address;
            address += variable.size == null ? 1 : variable.size;
        }
        Codegen initialization = new Codegen();
        for (Parser.VariableDecl variable : globals)
            if (variable.initializer != null) {
                initialization.expression(variable.initializer);
                initialization.emit(Op.STOREG, variable.address, variable.namePosition);
            }
        initialization.call("main", 0, main.namePosition);
        initialization.emit(Op.HALT, main.namePosition);
        List<Unit> units = new ArrayList<>();
        units.add(new Unit("<init>", null, List.of(), initialization.code));
        for (Parser.Function function : functions) {
            List<Parser.VariableDecl> slots = assignSlots(function);
            Codegen generator = new Codegen();
            generator.emit(Op.ENTER, slots.size(), function.namePosition);
            generator.statement(function.body);
            if (function.type == Parser.Type.VOID)
                generator.emit(Op.RET, function.body.endPosition);
            units.add(new Unit(function.name, function, slots, generator.code));
        }
        return new Generated(units, address);
    }
}
