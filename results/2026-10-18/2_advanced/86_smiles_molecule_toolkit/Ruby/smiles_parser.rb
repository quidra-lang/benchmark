require_relative 'molecule'

module Chemistry
  def self.read_organic(text, position)
    pair = text[position, 2]
    return [pair, false, position + 2] if %w[Cl Br].include?(pair)
    char = text[position]
    return [char, false, position + 1] if char && 'BCNOPSFI'.include?(char)
    return [char.upcase, true, position + 1] if char && 'bcnops'.include?(char)
    nil
  end

  def self.read_bracket(content, elements, column)
    position = 0
    position += 1 while content[position]&.match?(/[0-9]/)
    if position >= 4 || (position.positive? && content[0] == '0') || position == content.length
      raise AnalysisError.new('bad bracket atom', column)
    end
    mass = content[0, position].to_i
    char = content[position]
    if 'bcnops'.include?(char)
      symbol, aromatic = char.upcase, true
      position += 1
    elsif char.match?(/[A-Z]/)
      pair = content[position, 2]
      if pair.length == 2 && pair[1].match?(/[a-z]/) && elements.key?(pair)
        symbol = pair
        position += 2
      elsif elements.key?(char)
        symbol = char
        position += 1
      else
        raise AnalysisError.new('unknown element', column)
      end
      aromatic = false
    else
      raise AnalysisError.new('bad bracket atom', column)
    end
    if content[position, 2] == '@@'
      position += 2
    elsif content[position] == '@'
      position += 1
    end
    hydrogens = 0
    if content[position] == 'H'
      position += 1
      hydrogens = 1
      if content[position]&.match?(/[0-9]/)
        hydrogens = content[position].to_i
        position += 1
      end
    end
    charge = 0
    if %w[+ -].include?(content[position])
      charge = content[position] == '+' ? 1 : -1
      position += 1
      if content[position]&.match?(/[1-9]/)
        charge *= content[position].to_i
        position += 1
      end
    end
    raise AnalysisError.new('bad bracket atom', column) unless position == content.length
    Atom.new(elements[symbol], aromatic, mass, charge, hydrogens, true, column)
  end

  def self.read_atom(text, position, elements)
    if text[position] == '['
      ending = text.index(']', position + 1)
      raise AnalysisError.new('unclosed bracket', position + 1) unless ending
      return [read_bracket(text[position + 1...ending], elements, position + 1), ending + 1]
    end
    organic = read_organic(text, position)
    raise AnalysisError.new('unexpected character', position + 1) unless organic
    symbol, aromatic, ending = organic
    [Atom.new(elements[symbol], aromatic, 0, 0, 0, false, position + 1), ending]
  end

  def self.parse_smiles(text, elements, pattern: false)
    molecule = Molecule.new(elements)
    symbols = pattern ? {'-' => 1, '=' => 2, '#' => 3, ':' => 4, '~' => 5} : BOND_TYPES
    current = pending = nil
    branches, rings = [], {}
    position = 0
    while position < text.length
      char, column = text[position], position + 1
      if symbols.key?(char)
        raise AnalysisError.new('misplaced bond', column) if current.nil? || pending
        pending = [char, column]
        position += 1
      elsif char == '('
        raise AnalysisError.new('misplaced branch', column) if current.nil? || pending || text[position - 1] == '('
        branches << [current, column]
        position += 1
      elsif char == ')'
        raise AnalysisError.new('unmatched parenthesis', column) if branches.empty?
        raise AnalysisError.new('dangling bond', pending[1]) if pending
        raise AnalysisError.new('empty branch', column) if text[position - 1] == '('
        current = branches.pop[0]
        position += 1
      elsif char.match?(/[0-9]/) || char == '%'
        raise AnalysisError.new('misplaced ring closure', column) if current.nil?
        if char == '%'
          digits = text[position + 1, 2]
          raise AnalysisError.new('bad ring number', column) unless digits&.match?(/\A[0-9]{2}\z/)
          ring = digits.to_i
          position += 3
        else
          ring = char.to_i
          position += 1
        end
        symbol = pending&.first
        pending = nil
        unless rings.key?(ring)
          rings[ring] = [current, symbol, column]
          next
        end
        first, initial, = rings[ring]
        raise AnalysisError.new('self bond', column) if first == current
        raise AnalysisError.new('ring bond mismatch', column) if initial && symbol && symbols[initial] != symbols[symbol]
        raise AnalysisError.new('duplicate bond', column) if molecule.neighbors[first].key?(current)
        molecule.add_bond(first, current, symbol || initial)
        rings.delete(ring)
      else
        atom, position = pattern ? read_pattern_atom(text, position, elements) : read_atom(text, position, elements)
        number = molecule.add_atom(atom)
        molecule.add_bond(current, number, pending&.first) unless current.nil?
        current, pending = number, nil
      end
    end
    raise AnalysisError.new('dangling bond', pending[1]) if pending
    raise AnalysisError.new('unmatched parenthesis', branches.first[1]) unless branches.empty?
    raise AnalysisError.new('unclosed ring', rings.values.map(&:last).min) unless rings.empty?
    molecule
  end
end
