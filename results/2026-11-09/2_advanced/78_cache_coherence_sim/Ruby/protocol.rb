module Protocol
  DIRTY = %w[M O].freeze
  module_function

  def requester(protocol, old, operation, other_copy)
    if protocol == 'VI'
      return old == 'I' ? ['BusRd', 'V'] : [nil, 'V'] if operation == 'R'
      return ['BusWr', old == 'I' ? 'I' : 'V']
    end
    if old == 'I'
      return ['BusRdX', 'M'] if operation == 'W'
      return ['BusRd', protocol == 'MSI' || other_copy ? 'S' : 'E']
    end
    return [nil, old] if operation == 'R'
    %w[M E].include?(old) ? [nil, 'M'] : ['BusUpgr', 'M']
  end

  def snoop(protocol, old, transaction)
    return [transaction == 'BusRd' ? 'V' : 'I', false, false] if protocol == 'VI'
    if transaction == 'BusRd'
      return protocol == 'MOESI' ? ['O', true, false] : ['S', true, true] if old == 'M'
      return ['O', true, false] if old == 'O'
      return ['S', false, false]
    end
    ['I', transaction == 'BusRdX' && DIRTY.include?(old), false]
  end
end
