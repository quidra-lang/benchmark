# frozen_string_literal: true

module Rules
  Rule = Struct.new(:antecedent, :consequent, :count, :support, :confidence, :lift,
                    :leverage, :conviction, :improvement, :rank, keyword_init: true)

  def self.build(antecedent, consequent, n_x, n_y, n_z, total)
    Rule.new(antecedent: antecedent, consequent: consequent, count: n_z,
             support: Rational(n_z, total), confidence: Rational(n_z, n_x),
             lift: Rational(total * n_z, n_x * n_y),
             leverage: Rational(total * n_z - n_x * n_y, total * total),
             conviction: n_x == n_z ? nil : Rational((total - n_y) * n_x, total * (n_x - n_z)))
  end

  def self.passes?(rule, confidence, lift)
    rule.confidence >= confidence && rule.lift >= lift
  end

  def self.compare(left, right)
    order = right.confidence <=> left.confidence
    return order unless order.zero?

    order = right.lift <=> left.lift
    return order unless order.zero?

    order = right.count <=> left.count
    return order unless order.zero?

    order = left.antecedent <=> right.antecedent
    order.zero? ? left.consequent <=> right.consequent : order
  end
end
