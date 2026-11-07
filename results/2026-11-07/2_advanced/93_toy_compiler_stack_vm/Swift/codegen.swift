struct Instruction {
    var op: String, operands: [Int], callee: Int?
    let position: Position
    init(_ op: String, _ operands: [Int], _ position: Position, _ callee: Int? = nil) {
        self.op = op;
        self.operands = operands;
        self.position = position;
        self.callee = callee
    }
}
struct Unit {
    let name: String, function: Function?, slots: [Variable];
    var code: [Instruction]
}
final class Label {
    var position: Int?, patches: [Int] = []
}
final class Codegen {
    let semantic: Semantic;
    var code: [Instruction] = []
    init(_ semantic: Semantic) {
        self.semantic = semantic
    }
    func emit(_ op: String, _ args: [Int] = [], _ position: Position, _ callee: Int? = nil) {
        code.append(Instruction(op, args, position, callee))
    }
    func jump(_ op: String, _ label: Label, _ position: Position) {
        let i = code.count;
        emit(op, [label.position ?? 0], position);
        if label.position == nil {
            label.patches.append(i)
        }
    }
    func mark(_ label: Label) {
        label.position = code.count;
        for i in label.patches {
            code[i].operands[0] = code.count
        }
    }
    func expression(_ expression: Expr) {
        switch expression.kind {
            case .integer(let value): emit("PUSH", [value], expression.position)
            case .boolean(let value): emit("PUSH", [value ? 1 : 0], expression.position)
            case .read: emit("READ", [], expression.position)
            case .variable: let variable = semantic.symbols[expression.reference!].variable!;
            emit(variable.address >= 0 ? "LOADG" : "LOADL", [variable.address >= 0 ? variable.address : variable.slot], expression.position)
            case .element(_, let index): self.expression(index);
            let variable = semantic.symbols[expression.reference!].variable!;
            emit("LOADA", [variable.address, variable.size!], expression.position)
            case .call(_, let arguments): for argument in arguments {
                self.expression(argument)
            };
            emit("CALL", [0, arguments.count], expression.position, expression.reference!)
            case .unary(let op, let value): self.expression(value);
            emit(op == "-" ? "NEG" : "NOT", [], expression.position)
            case .binary(let op, let a, let b):
            self.expression(a)
            if op == "&&" || op == "||" {
                let alternate = Label(), end = Label();
                jump(op == "&&" ? "JUMPF" : "JUMPT", alternate, expression.position);
                self.expression(b);
                jump("JUMP", end, expression.position);
                mark(alternate);
                emit("PUSH", [op == "&&" ? 0 : 1], expression.position);
                mark(end)
            } else {
                self.expression(b);
                emit(["+": "ADD", "-": "SUB", "*": "MUL", "/": "DIV", "%": "MOD", "<": "LT", "<=": "LE", ">": "GT", ">=": "GE", "==": "EQ", "!=": "NE"][op]!, [], expression.position)
            }
        }
    }
    func statement(_ statement: Stmt, _ breakLabel: Label? = nil, _ continueLabel: Label? = nil) {
        switch statement.kind {
            case .empty: break
            case .block(let values, _): for value in values {
                self.statement(value, breakLabel, continueLabel)
            }
            case .declaration(let variable): if let initializer = variable.initializer {
                expression(initializer)
            } else {
                emit("PUSH", [0], variable.name.position)
            };
            emit("STOREL", [variable.slot], variable.name.position)
            case .assignment(_, let index, let value):
            let variable = semantic.symbols[statement.reference!].variable!
            if let index {
                expression(index)
            };
            expression(value)
            if index != nil {
                emit("STOREA", [variable.address, variable.size!], statement.position)
            }
            else {
                emit(variable.address >= 0 ? "STOREG" : "STOREL", [variable.address >= 0 ? variable.address : variable.slot], statement.position)
            }
            case .call(let value): expression(value);
            if value.type != .void {
                emit("POP", [], statement.position)
            }
            case .print(let values): for value in values {
                expression(value)
            };
            emit("PRINT", [values.count], statement.position)
            case .conditional(let condition, let yes, let no):
            let alternate = Label();
            expression(condition);
            jump("JUMPF", alternate, statement.position);
            self.statement(yes, breakLabel, continueLabel)
            if let no {
                let end = Label();
                jump("JUMP", end, statement.position);
                mark(alternate);
                self.statement(no, breakLabel, continueLabel);
                mark(end)
            } else {
                mark(alternate)
            }
            case .whileLoop(let condition, let body): let start = Label(), end = Label();
            mark(start);
            expression(condition);
            jump("JUMPF", end, statement.position);
            self.statement(body, end, start);
            jump("JUMP", start, statement.position);
            mark(end)
            case .forLoop(let initial, let condition, let update, let body):
            if let initial {
                self.statement(initial, breakLabel, continueLabel)
            };
            let start = Label(), next = Label(), end = Label();
            mark(start)
            if let condition {
                expression(condition);
                jump("JUMPF", end, statement.position)
            };
            self.statement(body, end, next);
            mark(next);
            if let update {
                self.statement(update, breakLabel, continueLabel)
            };
            jump("JUMP", start, statement.position);
            mark(end)
            case .breakLoop: jump("JUMP", breakLabel!, statement.position)
            case .continueLoop: jump("JUMP", continueLabel!, statement.position)
            case .returnValue(let value): if let value {
                expression(value);
                emit("RETV", [], statement.position)
            } else {
                emit("RET", [], statement.position)
            }
        }
    }
    func declarations(_ statement: Stmt) -> [Variable] {
        switch statement.kind {
            case .declaration(let variable): return [variable];
            case .block(let values, _): return values.flatMap(declarations);
            case .conditional(_, let yes, let no): return declarations(yes) + (no.map(declarations) ?? []);
            case .whileLoop(_, let body): return declarations(body);
            case .forLoop(let initial, _, let update, let body): return (initial.map(declarations) ?? []) + declarations(body) + (update.map(declarations) ?? []);
            default: return []
        }
    }
    func generate(_ program: Program, _ reachable: Set<Int>) -> ([Unit], Int) {
        var area = 0, units: [Unit] = []
        for declaration in program.declarations {
            if case .variable(let variable) = declaration {
                variable.address = area;
                area += variable.size ?? 1
            }
        }
        for declaration in program.declarations {
            if case .variable(let variable) = declaration, let initializer = variable.initializer {
                expression(initializer);
                emit("STOREG", [variable.address], variable.name.position)
            }
        }
        let mainID = semantic.globals["main"]!, main = semantic.symbols[mainID].function!
        emit("CALL", [0, 0], main.name.position, mainID);
        emit("HALT", [], main.name.position);
        units.append(Unit(name: "<init>", function: nil, slots: [], code: code))
        for declaration in program.declarations {
            if case .function(let function) = declaration, reachable.contains(function.id) {
                let slots = function.parameters + declarations(function.body)
                for (i, variable) in slots.enumerated() {
                    variable.slot = i
                }
                code = [];
                emit("ENTER", [slots.count], function.name.position);
                statement(function.body)
                if function.type == .void, case .block(_, let close) = function.body.kind {
                    emit("RET", [], close)
                };
                units.append(Unit(name: function.name.text, function: function, slots: slots, code: code))
            }
        };
        return (units, area)
    }
}
