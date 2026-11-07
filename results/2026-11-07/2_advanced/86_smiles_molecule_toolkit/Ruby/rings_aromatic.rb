require_relative 'molecule'

module Chemistry
  def self.breadth_first(molecule, root)
    parents, queue = {root => nil}, [root]
    queue.each do |atom|
      molecule.neighbors[atom].keys.sort.each do |neighbor|
        next if parents.key?(neighbor)
        parents[neighbor] = atom
        queue << neighbor
      end
    end
    paths = parents.keys.to_h do |atom|
      path, current = [], atom
      until current.nil?
        path << current
        current = parents[current]
      end
      [atom, path]
    end
    [parents, paths]
  end

  def self.ring_edges(sequence)
    sequence.each_index.map { |index| [sequence[index - 1], sequence[index]].sort }.to_set
  end

  def self.ring_sequence(sequence)
    forward = sequence.rotate(sequence.index(sequence.min))
    [forward, [forward.first] + forward.drop(1).reverse].min
  end

  def self.find_rings(molecule)
    candidates, seen = [], Set.new
    bonds = molecule.bonds.keys.sort
    molecule.atoms.each_index do |root|
      parents, paths = breadth_first(molecule, root)
      bonds.each do |first, second|
        next if parents[first] == second || parents[second] == first
        next unless (paths[first] & paths[second]) == [root]
        sequence = paths[first].reverse + paths[second][0...-1]
        edges = ring_edges(sequence)
        next if seen.include?(edges)
        seen << edges
        candidates << [sequence, edges]
      end
    end
    basis, rings = {}, []
    candidates.each_with_index.sort_by { |(sequence, _), index| [sequence.length, index] }.each do |(sequence, original), _|
      reduced = original.dup
      until reduced.empty?
        pivot = reduced.max
        unless basis.key?(pivot)
          basis[pivot] = reduced
          rings << ring_sequence(sequence)
          break
        end
        reduced = (reduced - basis[pivot]) | (basis[pivot] - reduced)
      end
    end
    molecule.rings = rings.sort_by { |ring| [ring.length, ring] }
    molecule.rings.each do |ring|
      molecule.ring_atoms.merge(ring)
      ring_edges(ring).each { |edge| molecule.bonds[edge].ring = true }
    end
  end

  def self.aromatic_systems(molecule, needing)
    remaining, systems = needing.to_set, []
    until remaining.empty?
      start = remaining.min
      remaining.delete(start)
      queue = [start]
      queue.each do |atom|
        molecule.neighbors[atom].sort.each do |neighbor, bond|
          next unless bond.kind == 4 && remaining.include?(neighbor)
          remaining.delete(neighbor)
          queue << neighbor
        end
      end
      systems << queue.to_set
    end
    systems
  end

  def self.match_system(molecule, system)
    unpaired, pairs = system.dup, []
    search = lambda do
      return true if unpaired.empty?
      first = unpaired.min
      unpaired.delete(first)
      molecule.neighbors[first].sort.each do |second, bond|
        next unless unpaired.include?(second) && bond.kind == 4
        unpaired.delete(second)
        pairs << bond.ends
        return true if search.call
        pairs.pop
        unpaired.add(second)
      end
      unpaired.add(first)
      false
    end
    search.call ? pairs : nil
  end

  def self.kekulize(molecule, needing)
    selected = Set.new
    aromatic_systems(molecule, needing).each do |system|
      pairs = match_system(molecule, system)
      raise AnalysisError.new('kekulization failed', molecule.atoms[system.min].column) unless pairs
      selected.merge(pairs)
    end
    molecule.bonds.each_value do |bond|
      bond.multiplicity = bond.kind == 4 ? (selected.include?(bond.ends) ? 2 : 1) : bond.kind
    end
  end
end
