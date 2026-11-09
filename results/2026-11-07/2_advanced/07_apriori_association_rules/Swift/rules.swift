struct Fraction: Comparable {
    let numerator: Int
    let denominator: Int
    init(_ numerator: Int, _ denominator: Int = 1) {
        var a = abs(numerator)
        var b = denominator
        while b != 0 { let remainder = a % b; a = b; b = remainder }
        self.numerator = numerator / a
        self.denominator = denominator / a
    }
    static func < (first: Fraction, second: Fraction) -> Bool { first.numerator * second.denominator < second.numerator * first.denominator }
    static func - (first: Fraction, second: Fraction) -> Fraction { Fraction(first.numerator * second.denominator - second.numerator * first.denominator, first.denominator * second.denominator) }
    static prefix func - (value: Fraction) -> Fraction { Fraction(-value.numerator, value.denominator) }
}
final class Rule {
    let items: [String]
    let antecedent: [String]
    let consequent: [String]
    let count: Int
    let support: Fraction
    let confidence: Fraction
    let lift: Fraction
    let leverage: Fraction
    let conviction: Fraction?
    var improvement = Fraction(0)
    var rank = 0
    init(_ items: [String], _ antecedent: [String], _ consequent: [String], _ count: Int, _ total: Int, _ first: Int, _ second: Int) {
        self.items = items
        self.antecedent = antecedent
        self.consequent = consequent
        self.count = count
        support = Fraction(count, total)
        confidence = Fraction(count, first)
        lift = liftOf(total, count, first, second)
        leverage = Fraction(total * count - first * second, total * total)
        conviction = first == count ? nil : Fraction((total - second) * first, total * (first - count))
    }
}
struct RuleSet {
    let generated: Int
    let rules: [Rule]
    var productive: Int { rules.filter { $0.improvement > Fraction(0) }.count }
}
func liftOf(_ total: Int, _ together: Int, _ first: Int, _ second: Int) -> Fraction { Fraction(total * together, first * second) }
func meets(_ confidence: Fraction, _ lift: Fraction, _ params: Params) -> Bool { confidence >= params.minConfidence && lift >= params.minLift }
func rulesBefore(_ first: Rule, _ second: Rule) -> Bool {
    if first.confidence != second.confidence { return first.confidence > second.confidence }
    if first.lift != second.lift { return first.lift > second.lift }
    if first.count != second.count { return first.count > second.count }
    return first.antecedent == second.antecedent ? itemsBefore(first.consequent, second.consequent) : itemsBefore(first.antecedent, second.antecedent)
}
