final class Symbol {
    let name: Name, type: ToyType, variable: Variable?, function: Function?, parameter: Bool
    var references: [Position] = [], reads = 0
    init(_ variable: Variable, _ parameter: Bool = false) {
        name = variable.name;
        type = variable.type;
        self.variable = variable;
        function = nil;
        self.parameter = parameter
    }
    init(_ function: Function) {
        name = function.name;
        type = function.type;
        variable = nil;
        self.function = function;
        parameter = false
    }
}
func canComplete(_ statement: Stmt) -> Bool {
    switch statement.kind {
        case .returnValue, .breakLoop, .continueLoop: return false;
        case .block(let values, _): return values.allSatisfy(canComplete);
        case .conditional(_, let yes, let no): return no == nil || canComplete(yes) || canComplete(no!);
        default: return true
    }
}
final class Semantic {
    var symbols: [Symbol] = [], globals: [String: Int] = [:], scopes: [[String: Int]] = [], calls: [Int: Set<Int>] = [:], current: Function?
    func fail(_ position: Position, _ message: String) -> CompileError {
        CompileError(kind: "semantic", position: position, message: message)
    }
    func add(_ variable: Variable, _ parameter: Bool = false) -> Int {
        let id = symbols.count;
        variable.id = id;
        symbols.append(Symbol(variable, parameter));
        return id
    }
    func add(_ function: Function) -> Int {
        let id = symbols.count;
        function.id = id;
        symbols.append(Symbol(function));
        return id
    }
    func forbidden(_ expression: Expr) -> [Position] {
        switch expression.kind {
            case .variable, .read: return [expression.position];
            case .element(_, let index): return [expression.position] + forbidden(index);
            case .call(_, let arguments): return [expression.position] + arguments.flatMap(forbidden);
            case .unary(_, let value): return forbidden(value);
            case .binary(_, let a, let b): return forbidden(a) + forbidden(b);
            default: return []
        }
    }
    func analyze(_ program: Program) throws {
        for declaration in program.declarations {
            switch declaration {
                case .variable(let variable):
                let name = variable.name
                if let size = variable.size {
                    if variable.type != .int {
                        throw fail(name.position, "array '\(name.text)' must have element type int")
                    }
                    if size == 0 {
                        throw fail(variable.sizePosition!, "array '\(name.text)' must have a positive size")
                    }
                } else if variable.type == .void {
                    throw fail(name.position, "variable '\(name.text)' cannot have type void")
                }
                if globals[name.text] != nil {
                    throw fail(name.position, "redeclaration of '\(name.text)'")
                }
                if let initializer = variable.initializer {
                    if let position = forbidden(initializer).min() {
                        throw fail(position, "global initializer must be constant")
                    }
                    if try expression(initializer) != variable.type {
                        throw fail(name.position, "type mismatch in initialization of '\(name.text)'")
                    }
                }
                globals[name.text] = add(variable)
                case .function(let function):
                if globals[function.name.text] != nil {
                    throw fail(function.name.position, "redeclaration of '\(function.name.text)'")
                }
                var names: Set<String> = []
                for parameter in function.parameters {
                    if parameter.type == .void {
                        throw fail(parameter.name.position, "parameter '\(parameter.name.text)' cannot have type void")
                    }
                    if !names.insert(parameter.name.text).inserted {
                        throw fail(parameter.name.position, "redeclaration of '\(parameter.name.text)'")
                    }
                };
                globals[function.name.text] = add(function)
            }
        }
        guard let id = globals["main"], let main = symbols[id].function else {
            throw fail(program.end, "no main function")
        }
        if main.type != .void || !main.parameters.isEmpty {
            throw fail(main.name.position, "main must be declared as 'void main()'")
        }
        for declaration in program.declarations {
            if case .function(let function) = declaration {
                current = function;
                scopes = [[:]];
                calls[function.id] = []
                for parameter in function.parameters {
                    scopes[0][parameter.name.text] = add(parameter, true)
                }
                if case .block(let statements, _) = function.body.kind {
                    for value in statements {
                        try statement(value, 0)
                    }
                }
                if function.type != .void && canComplete(function.body) {
                    throw fail(function.name.position, "missing return in function '\(function.name.text)'")
                }
            }
        };
        current = nil;
        scopes = []
    }
    func lookup(_ name: Name, _ read: Bool, _ call: Bool = false) throws -> Int {
        let local = scopes.reversed().compactMap {
            $0[name.text]
        }.first, id = local ?? globals[name.text]
        guard let id else {
            throw fail(name.position, "undeclared \(call ? "function" : "identifier") '\(name.text)'")
        }
        symbols[id].references.append(name.position);
        if read {
            symbols[id].reads += 1
        };
        return id
    }
    func variable(_ name: Name, _ array: Bool, _ read: Bool) throws -> Int {
        let id = try lookup(name, read), symbol = symbols[id]
        if symbol.function != nil {
            throw fail(name.position, "'\(name.text)' is a function, not a variable")
        }
        if !array && symbol.variable!.size != nil {
            throw fail(name.position, "array '\(name.text)' used without index")
        }
        if array && symbol.variable!.size == nil {
            throw fail(name.position, "'\(name.text)' is not an array")
        };
        return id
    }
    @discardableResult func expression(_ expression: Expr, _ callStatement: Bool = false) throws -> ToyType {
        let type: ToyType
        switch expression.kind {
            case .integer, .read: type = .int
            case .boolean: type = .bool
            case .variable(let name): let id = try variable(name, false, true);
            expression.reference = id;
            type = symbols[id].type
            case .element(let name, let index):
            let id = try variable(name, true, true);
            expression.reference = id
            if try self.expression(index) != .int {
                throw fail(name.position, "index of '\(name.text)' must be int")
            };
            type = .int
            case .call(let name, let arguments):
            let id = try lookup(name, true, true);
            expression.reference = id
            guard let function = symbols[id].function else {
                throw fail(name.position, "'\(name.text)' is not a function")
            }
            if arguments.count != function.parameters.count {
                throw fail(name.position, "wrong number of arguments to '\(name.text)' (expected \(function.parameters.count), found \(arguments.count))")
            }
            for (k, argument) in arguments.enumerated() {
                if try self.expression(argument) != function.parameters[k].type {
                    throw fail(name.position, "argument \(k + 1) of '\(name.text)' must be \(function.parameters[k].type.rawValue)")
                }
            }
            if !callStatement && function.type == .void {
                throw fail(name.position, "void function '\(name.text)' used as a value")
            }
            if let current {
                calls[current.id, default: []].insert(id)
            };
            type = function.type
            case .unary(let op, let value):
            type = try self.expression(value);
            let required: ToyType = op == "-" ? .int : .bool
            if type != required {
                throw fail(expression.position, "operator '\(op)' requires \(required.rawValue) operand")
            }
            case .binary(let op, let left, let right):
            let a = try self.expression(left), b = try self.expression(right)
            if ["+", "-", "*", "/", "%", "<", "<=", ">", ">="].contains(op) {
                if a != .int || b != .int {
                    throw fail(expression.position, "operator '\(op)' requires int operands")
                };
                type = ["+", "-", "*", "/", "%"].contains(op) ? .int : .bool
            } else if ["==", "!="].contains(op) {
                if a != b {
                    throw fail(expression.position, "operator '\(op)' requires operands of the same type")
                };
                type = .bool
            } else {
                if a != .bool || b != .bool {
                    throw fail(expression.position, "operator '\(op)' requires bool operands")
                };
                type = .bool
            }
        };
        expression.type = type;
        return type
    }
    func statement(_ statement: Stmt, _ loops: Int) throws {
        switch statement.kind {
            case .declaration(let variable):
            let name = variable.name
            if variable.type == .void {
                throw fail(name.position, "variable '\(name.text)' cannot have type void")
            }
            if scopes[scopes.count - 1][name.text] != nil {
                throw fail(name.position, "redeclaration of '\(name.text)'")
            }
            if let initializer = variable.initializer, try expression(initializer) != variable.type {
                throw fail(name.position, "type mismatch in initialization of '\(name.text)'")
            }
            let id = add(variable);
            scopes[scopes.count - 1][name.text] = id
            case .assignment(let name, let index, let value):
            let id = try variable(name, index != nil, false);
            statement.reference = id
            if let index, try expression(index) != .int {
                throw fail(name.position, "index of '\(name.text)' must be int")
            }
            if try expression(value) != symbols[id].type {
                throw fail(name.position, "type mismatch in assignment to '\(name.text)'")
            }
            case .call(let value): try expression(value, true)
            case .conditional(let condition, let yes, let no):
            if try expression(condition) != .bool {
                throw fail(statement.position, "condition of 'if' must be bool")
            };
            try self.statement(yes, loops);
            if let no {
                try self.statement(no, loops)
            }
            case .whileLoop(let condition, let body):
            if try expression(condition) != .bool {
                throw fail(statement.position, "condition of 'while' must be bool")
            };
            try self.statement(body, loops + 1)
            case .forLoop(let initial, let condition, let update, let body):
            scopes.append([:]);
            if let initial {
                try self.statement(initial, loops)
            };
            if let condition, try expression(condition) != .bool {
                throw fail(statement.position, "condition of 'for' must be bool")
            };
            if let update {
                try self.statement(update, loops)
            };
            try self.statement(body, loops + 1);
            scopes.removeLast()
            case .breakLoop: if loops == 0 {
                throw fail(statement.position, "'break' outside loop")
            }
            case .continueLoop: if loops == 0 {
                throw fail(statement.position, "'continue' outside loop")
            }
            case .returnValue(let value):
            let function = current!
            if function.type == .void && value != nil {
                throw fail(statement.position, "function '\(function.name.text)' must not return a value")
            }
            if function.type != .void {
                guard let value else {
                    throw fail(statement.position, "function '\(function.name.text)' must return a value")
                }
                if try expression(value) != function.type {
                    throw fail(statement.position, "return value of '\(function.name.text)' must be \(function.type.rawValue)")
                }
            }
            case .print(let values): for (k, value) in values.enumerated() {
                if try expression(value) != .int {
                    throw fail(statement.position, "argument \(k + 1) of 'print' must be int")
                }
            }
            case .block(let values, _): scopes.append([:]);
            for value in values {
                try self.statement(value, loops)
            };
            scopes.removeLast()
            case .empty: break
        }
    }
}
