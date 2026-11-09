module Combining
  NA = 'NOT_APPLICABLE'
  IP = 'INDETERMINATE{P}'
  ID = 'INDETERMINATE{D}'
  IDP = 'INDETERMINATE{DP}'

  def self.combine(algorithm, children, evaluate, target)
    states = Array.new(children.length)
    if algorithm == 'only-one-applicable'
      matched = nil
      children.each_with_index do |child, index|
        result, reason = target.call(child)
        states[index] = [:checked, [result, reason]]
        return [IDP, reason, states] if result == 'INDETERMINATE'
        next unless result == 'MATCH'
        return [IDP, "multiple applicable #{children[matched].id} #{child.id}", states] if matched
        matched = index
      end
      return [NA, nil, states] unless matched
      result = evaluate.call(children[matched])
      states[matched] = [:evaluated, result]
      return [result.decision, result.reason, states]
    end
    decisions, first_error = [], nil
    children.each_with_index do |child, index|
      result = evaluate.call(child)
      states[index] = [:evaluated, result]
      decision = result.decision
      decisions << decision
      first_error ||= result.reason if decision.start_with?('INDETERMINATE')
      return [decision, result.reason, states] if algorithm == 'first-applicable' && decision != NA
      return ['DENY', nil, states] if %w[deny-overrides permit-unless-deny].include?(algorithm) && decision == 'DENY'
      return ['PERMIT', nil, states] if %w[permit-overrides deny-unless-permit].include?(algorithm) && decision == 'PERMIT'
    end
    return ['DENY', nil, states] if algorithm == 'deny-unless-permit'
    return ['PERMIT', nil, states] if algorithm == 'permit-unless-deny'
    return [NA, nil, states] if algorithm == 'first-applicable'
    other, uncertain, opposite = algorithm == 'deny-overrides' ? ['PERMIT', ID, IP] : ['DENY', IP, ID]
    decision = if decisions.include?(IDP) || (decisions.include?(uncertain) && (decisions.include?(opposite) || decisions.include?(other)))
                 IDP
               elsif decisions.include?(uncertain)
                 uncertain
               elsif decisions.include?(other)
                 other
               elsif decisions.include?(opposite)
                 opposite
               else
                 NA
               end
    [decision, decision.start_with?('INDETERMINATE') ? first_error : nil, states]
  end
end
