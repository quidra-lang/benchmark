import Foundation

struct SqlError: Error {
    let reason: String
}

func fail(_ s: String) throws -> Never {
    throw SqlError(reason:s)
}

enum Value: Hashable {
    case null, int(Int64), text(String)
    var type: String {
        switch self {
            case .null: return "NULL"
            case .int: return "INT"
            case .text: return "TEXT"
        }
    }
    var written: String {
        switch self {
            case .null: return "NULL"
            case .int(let n): return String(n)
            case .text(let s): return s
        }
    }
    var integer: Int64 {
        if case .int(let n) = self {
            return n
        }
        return 0
    }
    var truth: Bool {
        self != .null && integer != 0
    }
}
let reserved = Set("SELECT DISTINCT FROM AS JOIN INNER LEFT OUTER ON WHERE GROUP BY HAVING ORDER ASC DESC LIMIT OFFSET INSERT INTO VALUES UPDATE SET DELETE CREATE TABLE DROP PRIMARY KEY NOT NULL INT TEXT AND OR IS IN BETWEEN LIKE COUNT SUM MIN MAX AVG EXIT".components(separatedBy:" "))
let aggregates = ["COUNT","SUM","MIN","MAX","AVG"]
let comparisons = ["=","<>","!=","<","<=",">",">="]

struct Token {
    let kind: String
    let text: String
    let key: String
}

func tokenize(_ text: String) throws -> [Token] {
    let a = Array(text)
    let n = a.count
    var i = 0
    var tokens: [Token] = []
    func letter(_ c: Character) -> Bool {
        c.isASCII && (c.isLetter || c == "_")
    }
    while i < n {
        let c = a[i]
        let start = i
        if c == " " || c == "\n" {
            i += 1
            continue
        }
        if c == "-" && i+1 < n && a[i+1] == "-" {
            while i < n && a[i] != "\n" {
                i += 1
            }
            continue
        }
        var kind = "symbol"
        if c == "'" {
            i += 1
            while i < n && a[i] != "'" {
                i += 1
            }
            i += 1
            kind = "string"
        }
        else if c.isNumber {
            i += 1
            while i < n && a[i].isNumber {
                i += 1
            }
            kind = "integer"
        }
        else if letter(c) {
            i += 1
            while i < n && (letter(a[i]) || a[i].isNumber) {
                i += 1
            }
            kind = "name"
        }
        else if i+1 < n && ["<>","!=","<=",">=","||"].contains(String(a[i...i+1])) {
            i += 2
        }
        else if "(),.;*/%+-=<>".contains(c) {
            i += 1
        }
        else {
            try fail("unexpected character '\(c)'")
        }
        let s = String(a[start..<i])
        if kind == "name" && reserved.contains(s.uppercased()) {
            kind = "keyword"
        }
        tokens.append(Token(kind:kind,text:s,key:kind == "keyword" ? s.uppercased() : s))
    }
    return tokens
}

final class Expr {
    let kind: String
    var op: String
    var children: [Expr]
    var literal: Value
    var table: String?
    var column: String
    var written: String
    var index = -1
    var negated = false
    var distinct = false
    init(_ kind: String, _ op: String = "", _ children: [Expr] = [], _ literal: Value = .null, table: String? = nil, column: String = "", written: String = "") {
        self.kind=kind
        self.op=op
        self.children=children
        self.literal=literal
        self.table=table
        self.column=column
        self.written=written
    }
    var hasAggregate: Bool {
        kind == "aggregate" || children.contains {
            $0.hasAggregate
        }
    }
}

struct Column {
    let name: String
    let type: String
    let notNull: Bool
    let keys: Int
}

struct Table {
    let name: String
    let columns: [Column]
    var rows: [[Value]] = []
    var primary: Int? {
        columns.firstIndex {
            $0.keys > 0
        }
    }
}

struct TableRef {
    let name: String
    let alias: String?
    var scopeName: String {
        alias ?? name
    }
}

struct Join {
    let table: TableRef
    let outer: Bool
    let condition: Expr
}

struct Item {
    let expr: Expr
    let alias: String?
    let heading: String
}

struct Order {
    let expr: Expr
    let tokens: [Token]
    let descending: Bool
}

final class Statement {
    var command = ""
    var name = ""
    var columns: [Column] = []
    var names: [String]? = nil
    var tuples: [[Expr]] = []
    var assignments: [(String,Expr)] = []
    var whereExpr: Expr? = nil
    var distinct = false
    var items: [Item]? = nil
    var source: TableRef? = nil
    var joins: [Join] = []
    var grouping: [Expr] = []
    var having: Expr? = nil
    var orders: [Order] = []
    var limit: Int? = nil
    var offset = 0
}

final class Parser {
    let tokens: [Token]
    var pos = 0
    init(_ t: [Token]) {
        tokens=t
    }
    var peek: Token {
        tokens[min(pos,tokens.count-1)]
    }
    func at(_ keys: [String]) -> Bool {
        (peek.kind == "keyword" || peek.kind == "symbol") && keys.contains(peek.key)
    }
    @discardableResult func take() -> Token {
        let t = peek
        pos += 1
        return t
    }
    func accept(_ key: String) -> Bool {
        if at([key]) {
            pos += 1
            return true
        }
        return false
    }
    func syntax() throws -> Never {
        try fail("syntax error at '\(peek.text)'")
    }
    func expect(_ key: String) throws {
        if !accept(key) {
            try syntax()
        }
    }
    func name() throws -> String {
        if peek.kind != "name" {
            try syntax()
        }
        return take().text
    }
    func integer() throws -> Int {
        if peek.kind != "integer" {
            try syntax()
        }
        return Int(take().text)!
    }
    func list<T>(_ parse: () throws -> T) throws -> [T] {
        var a = [try parse()]
        while accept(",") {
            a.append(try parse())
        }
        return a
    }
    func parenthesized<T>(_ parse: () throws -> T) throws -> [T] {
        try expect("(")
        let a = try list(parse)
        try expect(")")
        return a
    }
    func alias() throws -> String? {
        if accept("AS") {
            return try name()
        }
        return peek.kind == "name" ? take().text : nil
    }
    func ref() throws -> Expr {
        let first = try name()
        if accept(".") {
            let c = try name()
            return Expr("column",table:first,column:c,written:first+"."+c)
        }
        return Expr("column",column:first,written:first)
    }
    func tableRef() throws -> TableRef {
        let n = try name()
        return TableRef(name:n,alias:try alias())
    }
    func clause(_ key: String) throws -> Expr? {
        accept(key) ? try expr() : nil
    }
    func parse() throws -> Statement {
        let s = Statement()
        if accept("CREATE") {
            s.command="CREATE"
            try expect("TABLE")
            s.name=try name()
            s.columns=try parenthesized {
                let n = try self.name()
                if !self.at(["INT","TEXT"]) {
                    try self.syntax()
                }
                let type = self.take().key
                var keys=0
                var nn=false
                while self.at(["PRIMARY","NOT"]) {
                    if self.accept("PRIMARY") {
                        try self.expect("KEY")
                        keys += 1
                    } else {
                        try self.expect("NOT")
                        try self.expect("NULL")
                        nn=true
                    }
                }
                return Column(name:n,type:type,notNull:nn || keys > 0,keys:keys)
            }
        } else if accept("DROP") {
            s.command="DROP"
            try expect("TABLE")
            s.name=try name()
        }
        else if accept("INSERT") {
            s.command="INSERT"
            try expect("INTO")
            s.name=try name()
            if at(["("]) {
                s.names=try parenthesized {
                    try self.name()
                }
            }
            try expect("VALUES")
            s.tuples=try list {
                try self.parenthesized {
                    try self.expr()
                }
            }
        }
        else if accept("UPDATE") {
            s.command="UPDATE"
            s.name=try name()
            try expect("SET")
            s.assignments=try list {
                let n = try self.name()
                try self.expect("=")
                return (n,try self.expr())
            }
            s.whereExpr=try clause("WHERE")
        }
        else if accept("DELETE") {
            s.command="DELETE"
            try expect("FROM")
            s.name=try name()
            s.whereExpr=try clause("WHERE")
        }
        else if accept("SELECT") {
            s.command="SELECT"
            s.distinct=accept("DISTINCT")
            if !accept("*") {
                s.items=try list {
                    let start=self.pos
                    let e=try self.expr()
                    let t=Array(self.tokens[start..<self.pos])
                    let alias=try self.alias()
                    var h=""
                    for (i,v) in t.enumerated() {
                        if i > 0 && v.kind != "symbol" && t[i-1].kind != "symbol" {
                            h += " "
                        }
                        h += v.text
                    }
                    return Item(expr:e,alias:alias,heading:alias ?? (e.kind == "column" && t[0].kind == "name" ? e.column : h))
                }
            }
            try expect("FROM")
            s.source=try tableRef()
            while at(["JOIN","LEFT","INNER"]) {
                let outer=accept("LEFT")
                if outer {
                    _=accept("OUTER")
                } else {
                    _=accept("INNER")
                }
                try expect("JOIN")
                let t=try tableRef()
                try expect("ON")
                s.joins.append(Join(table:t,outer:outer,condition:try expr()))
            }
            s.whereExpr=try clause("WHERE")
            if accept("GROUP") {
                try expect("BY")
                s.grouping=try list {
                    try self.ref()
                }
            }
            s.having=try clause("HAVING")
            if accept("ORDER") {
                try expect("BY")
                s.orders=try list {
                    let start=self.pos
                    let e=try self.expr()
                    let t=Array(self.tokens[start..<self.pos])
                    let desc=self.accept("DESC")
                    if !desc {
                        _=self.accept("ASC")
                    }
                    return Order(expr:e,tokens:t,descending:desc)
                }
            }
            if accept("LIMIT") {
                s.limit=try integer()
                if accept("OFFSET") {
                    s.offset=try integer()
                }
            }
        } else if accept("EXIT") {
            s.command="EXIT"
        }
        try expect(";")
        return s
    }
    func binary(_ ops: [String], _ operand: () throws -> Expr) throws -> Expr {
        var e=try operand()
        while at(ops) {
            let op=take().key
            e=Expr("binary",op,[e,try operand()])
        }
        return e
    }
    func expr() throws -> Expr {
        try binary(["OR"]) {
            try self.andExpr()
        }
    }
    func andExpr() throws -> Expr {
        try binary(["AND"]) {
            try self.notExpr()
        }
    }
    func notExpr() throws -> Expr {
        if accept("NOT") {
            return Expr("unary","NOT",[try notExpr()])
        }
        return try comparison()
    }
    func comparison() throws -> Expr {
        let e=try additive()
        if at(comparisons) {
            let op=take().key
            return Expr("binary",op,[e,try additive()])
        }
        if accept("IS") {
            let n=accept("NOT")
            try expect("NULL")
            let r=Expr("isnull","",[e])
            r.negated=n
            return r
        }
        let n=accept("NOT")
        var r: Expr?
        if accept("IN") {
            r=Expr("in","",[e]+(try parenthesized {
                try self.expr()
            }))
        }
        else if accept("BETWEEN") {
            let low=try additive()
            try expect("AND")
            r=Expr("between","",[e,low,try additive()])
        }
        else if accept("LIKE") {
            r=Expr("like","",[e,try additive()])
        }
        else if n {
            try syntax()
        }
        if let r=r {
            r.negated=n
            return r
        }
        return e
    }
    func additive() throws -> Expr {
        try binary(["+","-","||"]) {
            try self.multiplicative()
        }
    }
    func multiplicative() throws -> Expr {
        try binary(["*","/","%"]) {
            try self.unary()
        }
    }
    func unary() throws -> Expr {
        if accept("-") {
            return Expr("unary","-",[try unary()])
        }
        return try primary()
    }
    func primary() throws -> Expr {
        if peek.kind == "integer" {
            return Expr("literal","",[],.int(Int64(take().text)!))
        }
        if peek.kind == "string" {
            return Expr("literal","",[],.text(String(take().text.dropFirst().dropLast())))
        }
        if accept("NULL") {
            return Expr("literal")
        }
        if peek.kind == "name" {
            return try ref()
        }
        if at(aggregates) {
            let n=take().key
            try expect("(")
            let e=Expr("aggregate",n)
            if n == "COUNT" && accept("*") {
            } else {
                e.distinct=accept("DISTINCT")
                e.children=[try expr()]
            }
            try expect(")")
            return e
        }
        if accept("(") {
            let e=try expr()
            try expect(")")
            return e
        }
        try syntax()
    }
}

struct Entry {
    let name: String
    let table: Table
    let offset: Int
}

struct Scope {
    var entries: [Entry] = []
    var width=0
    mutating func add(_ name: String, _ table: Table) throws {
        if entries.contains(where: {
            $0.name == name
        }) {
            try fail("duplicate table name \(name)")
        }
        entries.append(Entry(name:name,table:table,offset:width))
        width += table.columns.count
    }
    func resolve(_ e: Expr) throws -> String {
        var candidates: [(Int,String)] = []
        var selected=entries
        if let table=e.table {
            selected=entries.filter {
                $0.name == table
            }
            if selected.isEmpty {
                try fail("unknown table \(table)")
            }
        }
        for entry in selected {
            for (i,c) in entry.table.columns.enumerated() where c.name == e.column {
                candidates.append((entry.offset+i,c.type))
            }
        }
        if candidates.isEmpty {
            try fail("unknown column \(e.written)")
        }
        if candidates.count > 1 {
            try fail("ambiguous column \(e.column)")
        }
        e.index=candidates[0].0
        return candidates[0].1
    }
}

func require(_ a: String, _ b: String, _ op: String) throws {
    if a != b && a != "NULL" && b != "NULL" {
        try fail("type mismatch for \(op)")
    }
}

func check(_ e: Expr, _ scope: Scope, _ allowed: Bool = false, _ grouped: Set<Int>? = nil, _ inside: Bool = false) throws -> String {
    if e.kind == "literal" {
        return e.literal.type
    }
    if e.kind == "column" {
        let t=try scope.resolve(e)
        if let g=grouped, !inside && !g.contains(e.index) {
            try fail("column \(e.written) is not grouped")
        }
        return t
    }
    if e.kind == "aggregate" {
        if !allowed || inside {
            try fail("misuse of aggregate \(e.op)")
        }
        if e.children.isEmpty {
            return "INT"
        }
        let t=try check(e.children[0],scope,allowed,grouped,true)
        if ["SUM","AVG"].contains(e.op) {
            try require(t,"INT",e.op)
        }
        return ["MIN","MAX"].contains(e.op) ? t : "INT"
    }
    let types=try e.children.map {
        try check($0,scope,allowed,grouped,inside)
    }
    switch e.kind {
        case "unary": try require(types[0],"INT",e.op)
        case "binary":
        if comparisons.contains(e.op) {
            try require(types[0],types[1],e.op)
        }
        else {
            let t=e.op == "||" ? "TEXT" : "INT"
            for a in types {
                try require(a,t,e.op)
            }
            return t
        }
        case "in","between": for t in types.dropFirst() {
            try require(t,types[0],e.kind == "in" ? "IN" : "BETWEEN")
        }
        case "like": for t in types {
            try require(t,"TEXT","LIKE")
        }
        default: break
    }
    return "INT"
}

func condition(_ e: Expr?, _ scope: Scope, _ clause: String, _ allowed: Bool = false, _ grouped: Set<Int>? = nil) throws {
    if let e=e {
        try require(check(e,scope,allowed,grouped),"INT",clause)
    }
}

func compare(_ a: Value, _ b: Value) -> Int {
    if a == b {
        return 0
    }
    if a == .null {
        return -1
    }
    if b == .null {
        return 1
    }
    if case .int(let x)=a, case .int(let y)=b {
        return x < y ? -1 : 1
    }
    return a.written < b.written ? -1 : 1
}

func boolean(_ b: Bool) -> Value {
    .int(b ? 1 : 0)
}

func logicalNot(_ v: Value) -> Value {
    v == .null ? .null : boolean(!v.truth)
}

func operation(_ op: String, _ a: Value, _ b: Value) -> Value {
    if op == "AND" {
        return a == .int(0) || b == .int(0) ? .int(0) : (a == .null || b == .null ? .null : .int(1))
    }
    if op == "OR" {
        return a.truth || b.truth ? .int(1) : (a == .null || b == .null ? .null : .int(0))
    }
    if a == .null || b == .null {
        return .null
    }
    let x=a.integer
    let y=b.integer
    switch op {
        case "+": return .int(x+y)
        case "-": return .int(x-y)
        case "*": return .int(x*y)
        case "/": return y == 0 ? .null : .int(x/y)
        case "%": return y == 0 ? .null : .int(x%y)
        case "||": return .text(a.written+b.written)
        case "=": return boolean(a == b)
        case "!=","<>": return boolean(a != b)
        case "<": return boolean(compare(a,b) < 0)
        case "<=": return boolean(compare(a,b) <= 0)
        case ">": return boolean(compare(a,b) > 0)
        default: return boolean(compare(a,b) >= 0)
    }
}

func like(_ text: String, _ pattern: String) -> Bool {
    let a=Array(text)
    var matched=[true]+Array(repeating:false,count:a.count)
    for c in pattern {
        if c == "%" {
            for i in 0..<a.count {
                matched[i+1] = matched[i+1] || matched[i]
            }
        }
        else {
            for i in stride(from:a.count,through:1,by:-1) {
                matched[i] = matched[i-1] && (c == "_" || c == a[i-1])
            }
            matched[0]=false
        }
    }
    return matched.last!
}

func evaluate(_ e: Expr, _ row: [Value], _ group: [[Value]] = []) -> Value {
    if e.kind == "literal" {
        return e.literal
    }
    if e.kind == "column" {
        return row[e.index]
    }
    if e.kind == "aggregate" {
        if e.children.isEmpty {
            return .int(Int64(group.count))
        }
        var values=group.map {
            evaluate(e.children[0],$0)
        }.filter {
            $0 != .null
        }
        if e.distinct {
            var seen=Set<Value>()
            values=values.filter {
                seen.insert($0).inserted
            }
        }
        if e.op == "COUNT" {
            return .int(Int64(values.count))
        }
        if values.isEmpty {
            return .null
        }
        if e.op == "MIN" {
            return values.min {
                compare($0,$1) < 0
            }!
        }
        if e.op == "MAX" {
            return values.max {
                compare($0,$1) < 0
            }!
        }
        let sum=values.reduce(Int64(0)) {
            $0+$1.integer
        }
        return .int(e.op == "AVG" ? sum/Int64(values.count) : sum)
    }
    let v=e.children.map {
        evaluate($0,row,group)
    }
    var result=Value.null
    switch e.kind {
        case "unary": return e.op == "NOT" ? logicalNot(v[0]) : (v[0] == .null ? .null : .int(-v[0].integer))
        case "binary": return operation(e.op,v[0],v[1])
        case "isnull": result=boolean(v[0] == .null)
        case "in": result=v[0] == .null ? .null : (v.dropFirst().contains(v[0]) ? .int(1) : (v.dropFirst().contains(.null) ? .null : .int(0)))
        case "between": result=operation("AND",operation(">=",v[0],v[1]),operation("<=",v[0],v[2]))
        case "like": result=v.contains(.null) ? .null : boolean(like(v[0].written,v[1].written))
        default: break
    }
    return e.negated ? logicalNot(result) : result
}
var database: [String:Table] = [:]

func lookup(_ n: String) throws -> Table {
    guard let t=database[n] else {
        try fail("unknown table \(n)")
    }
    return t
}

func targets(_ names: [String], _ t: Table) throws -> [Int] {
    var indices: [Int] = []
    for n in names {
        guard let i=t.columns.firstIndex(where: {
            $0.name == n
        }) else {
            try fail("unknown column \(n)")
        }
        if indices.contains(i) {
            try fail("duplicate column \(n)")
        }
        indices.append(i)
    }
    return indices
}

func constraints(_ t: Table, _ checked: [Int]) throws {
    for i in checked {
        for (j,c) in t.columns.enumerated() where c.notNull && t.rows[i][j] == .null {
            try fail("NULL value in column \(c.name)")
        }
        if let k=t.primary, t.rows.indices.contains(where: {
            $0 != i && t.rows[$0][k] == t.rows[i][k]
        }) {
            try fail("duplicate primary key \(t.rows[i][k].written)")
        }
    }
}

func countMessage(_ n: Int, _ verb: String) {
    print("\(n) \(n == 1 ? "row" : "rows") \(verb).")
}

func printTable(_ items: [Item], _ types: [String], _ rows: [[Value]]) {
    let headings=items.map {
        $0.heading
    }
    var widths=headings.map {
        $0.count
    }
    for r in rows {
        for i in widths.indices {
            widths[i]=max(widths[i],r[i].written.count)
        }
    }
    let separator="+"+widths.map {
        String(repeating:"-",count:$0+2)+"+"
    }.joined()
    func line(_ values: [String], _ data: Bool) -> String {
        "|"+values.indices.map {
            i in let padding=String(repeating:" ",count:widths[i]-values[i].count)
            return " "+(data && types[i] == "INT" ? padding+values[i] : values[i]+padding)+" |"
        }.joined()
    }
    print(separator)
    print(line(headings,false))
    print(separator)
    for r in rows {
        print(line(r.map {
            $0.written
        },true))
    }
    print(separator)
    print("(\(rows.count) \(rows.count == 1 ? "row" : "rows"))")
}

func executeSelect(_ s: Statement) throws {
    var scope=Scope()
    var tables: [Table] = []
    let refs=[s.source!]+s.joins.map {
        $0.table
    }
    for (i,r) in refs.enumerated() {
        let t=try lookup(r.name)
        try scope.add(r.scopeName,t)
        tables.append(t)
        if i > 0 {
            try condition(s.joins[i-1].condition,scope,"ON")
        }
    }
    try condition(s.whereExpr,scope,"WHERE")
    for e in s.grouping {
        _=try scope.resolve(e)
    }
    let aggregate = !s.grouping.isEmpty || s.having != nil || (s.items ?? []).contains {
        $0.expr.hasAggregate
    } || s.orders.contains {
        $0.expr.hasAggregate
    }
    let grouped: Set<Int>? = aggregate ? Set(s.grouping.map {
        $0.index
    }) : nil
    var items=s.items ?? []
    if s.items == nil {
        for entry in scope.entries {
            for c in entry.table.columns {
                items.append(Item(expr:Expr("column",table:entry.name,column:c.name,written:c.name),alias:nil,heading:c.name))
            }
        }
    }
    let types=try items.map {
        try check($0.expr,scope,true,grouped)
    }
    try condition(s.having,scope,"HAVING",true,grouped)
    var keys: [Expr] = []
    for order in s.orders {
        if order.tokens.count == 1 && order.tokens[0].kind == "integer" {
            let k=Int(order.tokens[0].text)!
            if k < 1 || k > items.count {
                try fail("ORDER BY position \(k) is out of range")
            }
            keys.append(items[k-1].expr)
        } else if order.tokens.count == 1 && order.tokens[0].kind == "name", let item=items.first(where: {
            $0.alias == order.tokens[0].text
        }) {
            keys.append(item.expr)
        }
        else {
            _=try check(order.expr,scope,true,grouped)
            keys.append(order.expr)
        }
    }
    var rows=tables[0].rows
    for (j,join) in s.joins.enumerated() {
        var next: [[Value]] = []
        for l in rows {
            var matched=false
            for r in tables[j+1].rows {
                let combined=l+r
                if evaluate(join.condition,combined).truth {
                    next.append(combined)
                    matched=true
                }
            }
            if !matched && join.outer {
                next.append(l+Array(repeating:.null,count:tables[j+1].columns.count))
            }
        }
        rows=next
    }
    if let e=s.whereExpr {
        rows=rows.filter {
            evaluate(e,$0).truth
        }
    }
    var groups: [[[Value]]] = []
    if aggregate {
        if s.grouping.isEmpty {
            groups=[rows]
        }
        else {
            var indices: [[Value]:Int] = [:]
            for r in rows {
                let key=s.grouping.map {
                    r[$0.index]
                }
                if let i=indices[key] {
                    groups[i].append(r)
                } else {
                    indices[key]=groups.count
                    groups.append([r])
                }
            }
        }
    } else {
        groups=rows.map {
            [$0]
        }
    }
    var results: [(values:[Value],keys:[Value],ordinal:Int)] = []
    for g in groups {
        let row=g.first ?? Array(repeating:.null,count:scope.width)
        if let e=s.having, !evaluate(e,row,g).truth {
            continue
        }
        results.append((items.map {
            evaluate($0.expr,row,g)
        },keys.map {
            evaluate($0,row,g)
        },results.count))
    }
    if !keys.isEmpty {
        results.sort {
            a,b in for i in keys.indices {
                let c=compare(a.keys[i],b.keys[i])
                if c != 0 {
                    return s.orders[i].descending ? c > 0 : c < 0
                }
            }
            return a.ordinal < b.ordinal
        }
    }
    if s.distinct {
        var seen=Set<[Value]>()
        results=results.filter {
            seen.insert($0.values).inserted
        }
    }
    let selected=results.dropFirst(min(s.offset,results.count)).prefix(s.limit ?? results.count).map {
        $0.values
    }
    printTable(items,types,selected)
}

func execute(_ s: Statement) throws {
    if s.command == "" || s.command == "EXIT" {
        return
    }
    if s.command == "SELECT" {
        try executeSelect(s)
        return
    }
    if s.command == "CREATE" {
        if database[s.name] != nil {
            try fail("table \(s.name) already exists")
        }
        var seen=Set<String>()
        var keys=0
        for c in s.columns {
            if seen.contains(c.name) {
                try fail("duplicate column \(c.name)")
            }
            seen.insert(c.name)
            keys += c.keys
            if keys > 1 {
                try fail("multiple primary keys")
            }
        }
        database[s.name]=Table(name:s.name,columns:s.columns)
        print("Table \(s.name) created.")
        return
    }
    var t=try lookup(s.name)
    if s.command == "DROP" {
        database.removeValue(forKey:s.name)
        print("Table \(s.name) dropped.")
        return
    }
    var scope=Scope()
    try scope.add(t.name,t)
    if s.command == "INSERT" {
        let columns=try targets(s.names ?? t.columns.map {
            $0.name
        },t)
        for tuple in s.tuples {
            if tuple.count != columns.count {
                try fail("expected \(columns.count) values, got \(tuple.count)")
            }
            for (e,i) in zip(tuple,columns) {
                try require(check(e,Scope()),t.columns[i].type,"column \(t.columns[i].name)")
            }
        }
        let start=t.rows.count
        for tuple in s.tuples {
            var row=Array(repeating:Value.null,count:t.columns.count)
            for (e,i) in zip(tuple,columns) {
                row[i]=evaluate(e,[])
            }
            t.rows.append(row)
        }
        try constraints(t,Array(start..<t.rows.count))
        database[s.name]=t
        countMessage(s.tuples.count,"inserted")
        return
    }
    var assigned: [Int] = []
    if s.command == "UPDATE" {
        assigned=try targets(s.assignments.map {
            $0.0
        },t)
        for (assignment,i) in zip(s.assignments,assigned) {
            try require(check(assignment.1,scope),t.columns[i].type,"column \(t.columns[i].name)")
        }
    }
    try condition(s.whereExpr,scope,"WHERE")
    let affected=t.rows.indices.filter {
        s.whereExpr == nil || evaluate(s.whereExpr!,t.rows[$0]).truth
    }
    if s.command == "DELETE" {
        let removed=Set(affected)
        t.rows=t.rows.enumerated().filter {
            !removed.contains($0.offset)
        }.map {
            $0.element
        }
    }
    else {
        for i in affected {
            let original=t.rows[i]
            for (assignment,j) in zip(s.assignments,assigned) {
                t.rows[i][j]=evaluate(assignment.1,original)
            }
        }
        try constraints(t,affected)
    }
    database[s.name]=t
    countMessage(affected.count,s.command == "DELETE" ? "deleted" : "updated")
}
let input=Array(String(data:FileHandle.standardInput.readDataToEndOfFile(),encoding:.utf8)!)
var start=0
var i=0
var quoted=false
var comment=false
while i < input.count {
    let c=input[i]
    if comment {
        if c == "\n" {
            comment=false
        }
    }
    else if c == "'" {
        quoted.toggle()
    }
    else if !quoted && c == "-" && i+1 < input.count && input[i+1] == "-" {
        comment=true
    }
    else if !quoted && c == ";" {
        do {
            let s=try Parser(tokenize(String(input[start...i]))).parse()
            if s.command == "EXIT" {
                break
            }
            try execute(s)
        } catch let e as SqlError {
            print("ERROR: \(e.reason)")
        } catch {
        }
        start=i+1
    }
    i += 1
}
