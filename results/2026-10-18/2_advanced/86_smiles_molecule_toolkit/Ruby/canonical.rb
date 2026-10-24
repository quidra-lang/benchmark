require_relative 'molecule'

module Chemistry
  def self.dense_ranks(values)
    lookup = values.uniq.sort.each_with_index.to_h { |value, index| [value, index + 1] }
    values.map { |value| lookup[value] }
  end

  def self.refine(molecule, ranks)
    loop do
      values = molecule.neighbors.each_with_index.map do |neighbors, atom|
        [ranks[atom], neighbors.map { |neighbor, bond| [ranks[neighbor], bond.kind] }.sort]
      end
      updated = dense_ranks(values)
      return updated if updated.uniq.length == ranks.uniq.length
      ranks = updated
    end
  end

  def self.canonical_ranks(molecule)
    invariants = molecule.atoms.each_with_index.map do |atom, number|
      [molecule.degree(number), atom.element.number, atom.mass, atom.charge, atom.hydrogens, atom.aromatic ? 1 : 0]
    end
    ranks = refine(molecule, dense_ranks(invariants))
    classes = ranks.uniq.length
    until ranks.uniq.length == ranks.length
      tied = ranks.tally.select { |_, count| count > 1 }.keys.min
      first = ranks.index(tied)
      ranks = refine(molecule, dense_ranks(ranks.each_with_index.map { |rank, number| 2 * rank - (number == first ? 1 : 0) }))
    end
    [ranks, classes]
  end

  def self.atom_notation(molecule, number)
    atom = molecule.atoms[number]
    symbol = atom.element.symbol
    ordinary = ORGANIC.include?(symbol) && (!atom.aromatic || AROMATIC.include?(symbol)) && atom.mass.zero? && atom.charge.zero?
    if atom.aromatic
      ordinary &&= needs_pi(molecule, number) == needs_pi(molecule, number, 0)
      symbol = symbol.downcase
    end
    hydrogens = organic_hydrogens(atom, molecule.bond_total(number))
    return symbol if ordinary && !hydrogens.nil? && hydrogens == atom.hydrogens
    text = '[' + (atom.mass.zero? ? '' : atom.mass.to_s) + symbol
    text += 'H' + (atom.hydrogens == 1 ? '' : atom.hydrogens.to_s) if atom.hydrogens.positive?
    unless atom.charge.zero?
      text += atom.charge.positive? ? '+' : '-'
      text += atom.charge.abs.to_s if atom.charge.abs > 1
    end
    text + ']'
  end

  def self.bond_symbol(molecule, bond)
    in_ring = bond.ring && bond.ends.all? { |number| molecule.atoms[number].aromatic }
    case bond.kind
    when 1 then in_ring ? '-' : ''
    when 2 then '='
    when 3 then '#'
    else in_ring ? '' : ':'
    end
  end

  def self.canonical_smiles(molecule, ranks)
    visits, closures = {}, Set.new
    children = Array.new(molecule.atoms.length) { [] }
    visit = lambda do |atom, incoming|
      visits[atom] = visits.length + 1
      molecule.neighbors[atom].keys.sort_by { |number| ranks[number] }.each do |neighbor|
        bond = molecule.neighbors[atom][neighbor]
        next if bond.equal?(incoming) || closures.include?(bond.ends)
        if visits.key?(neighbor)
          closures << bond.ends
        else
          children[atom] << [neighbor, bond]
          visit.call(neighbor, bond)
        end
      end
    end
    root = ranks.index(1)
    visit.call(root, nil)
    assignments, occupied = {}, Set.new
    write = lambda do |atom|
      parts = [atom_notation(molecule, atom)]
      molecule.neighbors[atom].keys.sort_by { |number| visits[number] }.each do |neighbor|
        bond = molecule.neighbors[atom][neighbor]
        next unless closures.include?(bond.ends)
        if assignments.key?(bond.ends)
          number = assignments.delete(bond.ends)
          occupied.delete(number)
          symbol = ''
        else
          number = 1
          number += 1 while occupied.include?(number)
          assignments[bond.ends] = number
          occupied << number
          symbol = bond_symbol(molecule, bond)
        end
        parts << symbol + (number < 10 ? number.to_s : format('%%%02d', number))
      end
      children[atom].each_with_index do |(child, bond), index|
        continuation = bond_symbol(molecule, bond) + write.call(child)
        parts << (index + 1 < children[atom].length ? '(' + continuation + ')' : continuation)
      end
      parts.join
    end
    write.call(root)
  end

  def self.canonicalize(molecule)
    ranks, classes = canonical_ranks(molecule)
    [canonical_smiles(molecule, ranks), classes]
  end
end
