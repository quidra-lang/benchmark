require_relative 'smiles_parser'

module Chemistry
  PatternAtom = Struct.new(:choices, :aromatic) do
    def matches?(atom)
      choices ? choices.include?([atom.element.symbol, atom.aromatic]) : aromatic.nil? || aromatic == atom.aromatic
    end
  end

  def self.read_pattern_atom(text, position, _elements)
    char = text[position]
    return [PatternAtom.new(nil, char == '*' ? nil : char == 'a'), position + 1] if %w[* A a].include?(char)
    if char == '['
      ending = text.index(']', position + 1)
      raise AnalysisError.new('unclosed bracket', position + 1) unless ending
      raise AnalysisError.new('bad bracket atom', position + 1) if ending == position + 1
      choices = text[position + 1...ending].split(',', -1).map do |item|
        organic = read_organic(item, 0)
        raise AnalysisError.new('bad bracket atom', position + 1) unless organic && organic[2] == item.length
        organic[0, 2]
      end
      return [PatternAtom.new(choices.to_set, nil), ending + 1]
    end
    organic = read_organic(text, position)
    raise AnalysisError.new('unexpected character', position + 1) unless organic
    [PatternAtom.new([organic[0, 2]].to_set, nil), organic[2]]
  end

  def self.molecule_pattern(molecule)
    pattern = Molecule.new(molecule.elements)
    molecule.atoms.each { |atom| pattern.add_atom(PatternAtom.new([[atom.element.symbol, atom.aromatic]].to_set, nil)) }
    molecule.ordered_bonds.each { |bond| pattern.add_bond(*bond.ends, bond.kind) }
    pattern
  end

  def self.bond_matches?(pattern, target)
    symbol = pattern.symbol
    return [1, 4].include?(target.kind) if symbol.nil?
    return true if symbol == '~'
    target.kind == (symbol.is_a?(String) ? BOND_TYPES[symbol] : symbol)
  end

  def self.embeddings(pattern, molecule)
    return [0, 0, nil] if pattern.atoms.length > molecule.atoms.length
    candidates = pattern.atoms.each_with_index.map do |atom, index|
      molecule.atoms.each_index.select { |number| atom.matches?(molecule.atoms[number]) && molecule.degree(number) >= pattern.degree(index) }
    end
    earlier = pattern.neighbors.each_with_index.map { |neighbors, number| neighbors.select { |neighbor, _| neighbor < number } }
    mapping, used, unique = [], Set.new, Set.new
    count, first = 0, nil
    assign = lambda do |index|
      if index == pattern.atoms.length
        count += 1
        unique << used.to_a.sort
        first ||= mapping.dup
        return
      end
      candidates[index].each do |atom|
        next if used.include?(atom)
        next unless earlier[index].all? do |neighbor, bond|
          target = molecule.neighbors[atom][mapping[neighbor]]
          target && bond_matches?(bond, target)
        end
        mapping << atom
        used << atom
        assign.call(index + 1)
        used.delete(atom)
        mapping.pop
      end
    end
    assign.call(0)
    [count, unique.length, first]
  end

  def self.fingerprint(molecule)
    codes = molecule.atoms.each_with_index.map { |atom, number| 16 * atom.element.number + (atom.aromatic ? 8 : 0) + molecule.degree(number) }
    bits, used, count = Set.new, Set.new, 0
    extend_path = lambda do |atom, depth, value|
      count += 1
      bits << value % 1024
      return if depth == 5
      molecule.neighbors[atom].sort.each do |neighbor, bond|
        next if used.include?(neighbor)
        following = ((value * 31 + bond.kind) % 1_000_003 * 31 + codes[neighbor]) % 1_000_003
        used << neighbor
        extend_path.call(neighbor, depth + 1, following)
        used.delete(neighbor)
      end
    end
    codes.each_with_index do |code, atom|
      used << atom
      extend_path.call(atom, 0, code)
      used.delete(atom)
    end
    [bits, count]
  end

  def self.tanimoto(first, second)
    common = (first & second).length
    [common, first.length + second.length - common]
  end
end
