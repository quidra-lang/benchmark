require 'fileutils'
require_relative 'molecule'
require_relative 'smiles_parser'
require_relative 'rings_aromatic'
require_relative 'canonical'
require_relative 'search'

module Chemistry
  ARGUMENT_COUNTS = {'MATCH' => 1..1, 'CONTAINS' => 2..2, 'MATRIX' => 2..12,
                     'NEAREST' => 2..2, 'WITHIN' => 2..2, 'COMPARE' => 2..2, 'CLUSTER' => 1..1}.freeze
  SYSTEM_KINDS = %w[isolated fused spiro bridged].freeze

  def self.data_lines(path)
    File.readlines(path, chomp: true).each_with_index.filter_map do |line, index|
      [index + 1, line] unless line.empty? || line.start_with?('#')
    end
  end
  def self.valid_name?(value) = value && value.match?(/\A[A-Za-z0-9_-]{1,32}\z/)
  def self.valid_number?(value, minimum, maximum)
    value && value.match?(/\A(?:0|[1-9][0-9]*)\z/) && value.to_i.between?(minimum, maximum)
  end
  def self.read_threshold(value)
    parts = value.split('/', -1)
    return unless parts.length == 2 && valid_number?(parts[0], 0, 99) && valid_number?(parts[1], 1, 99)
    p, q = parts.map(&:to_i)
    [p, q] if p <= q
  end
  def self.fraction_text(value)
    p, q = value
    divisor = p.gcd(q)
    "#{p / divisor}/#{q / divisor}"
  end
  def self.fraction_compare(first, second) = (first[0] * second[1]) <=> (second[0] * first[1])
  def self.atom_numbers(atoms, separator = ',') = atoms.map { |atom| atom + 1 }.join(separator)
  def self.member_names(molecules) = molecules.map(&:name).join(',')

  def self.analyze(molecule)
    find_rings(molecule)
    molecule.bonds.each_value do |bond|
      aromatic = bond.ends.all? { |number| molecule.atoms[number].aromatic }
      bond.kind = bond.symbol ? BOND_TYPES[bond.symbol] : (aromatic && bond.ring ? 4 : 1)
    end
    needing = molecule.atoms.each_index.select { |number| needs_pi(molecule, number) }
    kekulize(molecule, needing)
    molecule.atoms.each_with_index do |atom, number|
      total = molecule.bond_total(number)
      if atom.bracket
        raise AnalysisError.new('bad valence', atom.column) if total + atom.hydrogens > atom.element.valences.last + atom.charge.abs
      else
        hydrogens = organic_hydrogens(atom, total)
        raise AnalysisError.new('bad valence', atom.column) if hydrogens.nil?
        atom.hydrogens = hydrogens
      end
    end
  end

  def self.molecular_properties(molecule)
    counts = Hash.new(0)
    molecule.atoms.each { |atom| counts[atom.element.symbol] += 1 }
    hydrogens = molecule.atoms.sum(&:hydrogens)
    counts['H'] += hydrogens
    symbols = counts.keys.select { |symbol| counts[symbol].positive? }.sort
    if counts['C'].positive?
      symbols.delete('C')
      prefix = ['C']
      prefix << 'H' if symbols.delete('H')
      symbols = prefix + symbols
    end
    formula = symbols.map { |symbol| symbol + (counts[symbol] == 1 ? '' : counts[symbol].to_s) }.join
    weight = molecule.atoms.sum { |atom| atom.mass.zero? ? atom.element.weight : atom.mass * 1000 }
    weight += hydrogens * molecule.elements['H'].weight
    heavy = molecule.atoms.count { |atom| atom.element.symbol != 'H' }
    heavy_degrees = molecule.neighbors.map { |neighbors| neighbors.keys.count { |number| molecule.atoms[number].element.symbol != 'H' } }
    triple = molecule.bonds.values.select { |bond| bond.multiplicity == 3 }.flat_map(&:ends).to_set
    rotatable = molecule.bonds.values.count do |bond|
      bond.multiplicity == 1 && !bond.ring && bond.ends.all? { |number| heavy_degrees[number] >= 2 && !triple.include?(number) }
    end
    donors = acceptors = 0
    molecule.atoms.each_with_index do |atom, number|
      next unless %w[N O].include?(atom.element.symbol)
      acceptors += 1
      attached = atom.hydrogens + molecule.neighbors[number].keys.count { |neighbor| molecule.atoms[neighbor].element.symbol == 'H' }
      donors += 1 if attached.positive?
    end
    violations = [weight > 500_000, donors > 5, acceptors > 10].count(true)
    {formula: formula, weight: weight, heavy: heavy, rotatable: rotatable, donors: donors,
     acceptors: acceptors, lipinski: violations <= 1 ? 'pass' : 'fail', charge: molecule.atoms.sum(&:charge)}
  end

  def self.scaffold_molecule(molecule)
    return if molecule.rings.empty?
    remaining = molecule.atoms.each_index.to_set
    loop do
      leaf = (remaining - molecule.ring_atoms).sort.find { |atom| molecule.neighbors[atom].keys.count { |neighbor| remaining.include?(neighbor) } == 1 }
      break if leaf.nil?
      remaining.delete(leaf)
    end
    kept = remaining.dup
    remaining.each do |atom|
      molecule.neighbors[atom].each { |neighbor, bond| kept << neighbor if !remaining.include?(neighbor) && bond.kind == 2 }
    end
    scaffold, renumber = Molecule.new(molecule.elements), {}
    kept.sort.each do |number|
      original = molecule.atoms[number]
      extra = molecule.neighbors[number].sum { |neighbor, bond| kept.include?(neighbor) ? 0 : bond.multiplicity }
      copy = original.dup
      copy.hydrogens += extra
      renumber[number] = scaffold.add_atom(copy)
    end
    molecule.ordered_bonds.each do |original|
      first, second = original.ends
      next unless kept.include?(first) && kept.include?(second)
      bond = scaffold.add_bond(renumber[first], renumber[second], original.symbol)
      bond.kind, bond.multiplicity, bond.ring = original.kind, original.multiplicity, original.ring
    end
    scaffold.rings = molecule.rings.map { |ring| ring.map { |atom| renumber[atom] } }
    scaffold.ring_atoms = molecule.ring_atoms.map { |atom| renumber[atom] }.to_set
    scaffold
  end

  def self.ring_systems(molecule)
    atom_sets = molecule.rings.map(&:to_set)
    connections, relations = Array.new(atom_sets.length) { Set.new }, {}
    atom_sets.each_index do |first|
      (first + 1...atom_sets.length).each do |second|
        shared = atom_sets[first] & atom_sets[second]
        next if shared.empty?
        connections[first] << second
        connections[second] << first
        relation = if shared.length == 1
                     'spiro'
                   elsif shared.length == 2 && molecule.bonds.key?(shared.to_a.sort)
                     'fused'
                   else
                     'bridged'
                   end
        relations[[first, second]] = relation
      end
    end
    systems, unseen = [], atom_sets.each_index.to_set
    until unseen.empty?
      queue = [unseen.min]
      unseen.delete(queue.first)
      queue.each do |ring|
        connections[ring].sort.each do |neighbor|
          next unless unseen.include?(neighbor)
          unseen.delete(neighbor)
          queue << neighbor
        end
      end
      kinds = relations.filter_map { |(first, second), kind| kind if queue.include?(first) && queue.include?(second) }
      kind = queue.length == 1 ? 'isolated' : (kinds.include?('bridged') ? 'bridged' : (kinds.include?('fused') ? 'fused' : 'spiro'))
      systems << {rings: queue.sort, atoms: queue.flat_map { |ring| atom_sets[ring].to_a }.uniq.length, kind: kind}
    end
    systems
  end

  def self.read_molecules(elements, causes)
    molecules, errors, reserved = [], [], Set.new
    lines = data_lines('input/molecules.smi')
    lines.each do |line_number, line|
      tokens = line.split(/ /, -1)
      if tokens.length != 2 || tokens[0].empty? || !valid_name?(tokens[1])
        errors << "line #{line_number}: bad line"
        causes['bad line'] += 1
        next
      end
      smiles, name = tokens
      if reserved.include?(name)
        errors << "line #{line_number} #{name}: duplicate name"
        causes['duplicate name'] += 1
        next
      end
      reserved << name
      begin
        molecule = parse_smiles(smiles, elements)
        analyze(molecule)
      rescue AnalysisError => error
        errors << "line #{line_number} #{name}: #{error.reason} at column #{error.column}"
        causes[error.reason] += 1
        next
      end
      molecule.name, molecule.order = name, molecules.length
      molecules << molecule
    end
    [molecules, ["MOLECULES lines=#{lines.length} valid=#{molecules.length} errors=#{errors.length}"] + errors]
  end

  def self.prepare_molecules(molecules)
    molecules.each do |molecule|
      molecule.properties = molecular_properties(molecule)
      molecule.canonical, molecule.classes = canonicalize(molecule)
      scaffold = scaffold_molecule(molecule)
      molecule.scaffold = canonicalize(scaffold).first if scaffold
      molecule.systems = ring_systems(molecule)
      molecule.aromatic_rings = molecule.rings.map { |ring| ring.all? { |atom| molecule.atoms[atom].aromatic } }
      molecule.bits, molecule.paths = fingerprint(molecule)
    end
  end

  def self.check_arguments(query, elements, by_name)
    kind, arguments = query.values_at(:type, :arguments)
    return 'bad arguments' unless ARGUMENT_COUNTS[kind].include?(arguments.length)
    case kind
    when 'MATCH'
      begin
        query[:pattern] = parse_smiles(arguments[0], elements, pattern: true)
      rescue AnalysisError => error
        return "bad pattern #{error.reason} at column #{error.column}"
      end
    when 'CLUSTER'
      query[:threshold] = read_threshold(arguments[0])
      return 'bad threshold' unless query[:threshold]
    when 'CONTAINS', 'MATRIX', 'COMPARE'
      arguments.each { |name| return "unknown molecule #{name}" unless by_name.key?(name) }
      return 'repeated molecule' unless arguments.uniq.length == arguments.length
    else
      return "unknown molecule #{arguments[0]}" unless by_name.key?(arguments[0])
      if kind == 'NEAREST'
        return 'bad count' unless valid_number?(arguments[1], 1, 99)
        query[:count] = arguments[1].to_i
      else
        query[:threshold] = read_threshold(arguments[1])
        return 'bad threshold' unless query[:threshold]
      end
    end
    nil
  end

  def self.read_queries(elements, by_name, causes)
    queries, errors, reserved = [], [], Set.new
    lines = data_lines('input/queries.txt')
    lines.each do |line_number, line|
      kind, identifier, *arguments = line.split(/ /, -1)
      reason = if !ARGUMENT_COUNTS.key?(kind)
                 'unknown query'
               elsif !valid_name?(identifier)
                 'bad id'
               elsif reserved.include?(identifier)
                 'duplicate id'
               else
                 reserved << identifier
                 query = {type: kind, id: identifier, arguments: arguments}
                 check_arguments(query, elements, by_name)
               end
      unless reason
        queries << query
        next
      end
      text = case reason
             when 'unknown query' then "line #{line_number}: unknown query"
             when 'bad id' then "line #{line_number} #{kind}: bad id"
             else "line #{line_number} #{kind} #{identifier}: #{reason}"
             end
      cause = reason.start_with?('bad pattern ') ? 'bad pattern' : (reason.start_with?('unknown molecule ') ? 'unknown molecule' : reason)
      causes[cause] += 1
      errors << text
    end
    [queries, ["QUERIES lines=#{lines.length} valid=#{queries.length} errors=#{errors.length}"] + errors]
  end

  def self.properties_lines(molecules)
    ['name,formula,weight,heavy_atoms,rings,rotatable,donors,acceptors,lipinski'] + molecules.map do |molecule|
      p = molecule.properties
      [molecule.name, p[:formula], format('%d.%03d', p[:weight] / 1000, p[:weight] % 1000),
       p[:heavy], molecule.rings.length, p[:rotatable], p[:donors], p[:acceptors], p[:lipinski]].join(',')
    end
  end

  def self.canonical_paragraphs(molecules)
    by_canonical = molecules.group_by(&:canonical)
    by_formula = molecules.group_by { |molecule| molecule.properties[:formula] }
    by_scaffold = molecules.reject { |molecule| molecule.scaffold.nil? }.group_by(&:scaffold)
    canonical = ["CANONICAL molecules=#{molecules.length} unique=#{by_canonical.length}"]
    molecules.each do |molecule|
      charge = molecule.properties[:charge]
      canonical << "#{molecule.name} #{molecule.canonical} classes=#{molecule.classes} charge=#{charge.positive? ? '+' : ''}#{charge}"
    end
    groups = by_canonical.select { |_, members| members.length >= 2 }
    duplicates = ["DUPLICATES groups=#{groups.length} molecules=#{groups.values.sum(&:length)}"]
    groups.each_with_index { |(smiles, members), index| duplicates << "group #{index + 1} #{smiles} members=#{member_names(members)}" }
    groups = by_formula.select { |_, members| members.map(&:canonical).uniq.length >= 2 }
    isomers = ["ISOMERS groups=#{groups.length}"]
    groups.each_with_index do |(formula, members), index|
      isomers << "isomer #{index + 1} #{formula} forms=#{members.map(&:canonical).uniq.length} members=#{member_names(members)}"
    end
    scaffolds = ["SCAFFOLDS distinct=#{by_scaffold.length} acyclic=#{molecules.count { |molecule| molecule.scaffold.nil? }}"]
    by_scaffold.sort_by { |smiles, members| [-members.length, smiles] }.each_with_index do |(smiles, members), index|
      scaffolds << "scaffold #{index + 1} #{smiles} count=#{members.length} members=#{member_names(members)}"
    end
    [canonical, duplicates, isomers, scaffolds]
  end

  def self.ring_paragraphs(molecules)
    paragraphs, sizes, kinds = [], Hash.new(0), Hash.new(0)
    total_aromatic = total_rings = 0
    molecules.each do |molecule|
      next if molecule.rings.empty?
      aromatic = molecule.aromatic_rings.count(true)
      total_aromatic += aromatic
      total_rings += molecule.rings.length
      paragraph = ["MOLECULE #{molecule.name} atoms=#{molecule.atoms.length} bonds=#{molecule.bonds.length} rings=#{molecule.rings.length} aromatic=#{aromatic} systems=#{molecule.systems.length} ring_atoms=#{molecule.ring_atoms.length} ring_bonds=#{molecule.bonds.values.count(&:ring)}"]
      molecule.rings.each_with_index do |ring, index|
        flag = molecule.aromatic_rings[index] ? 'yes' : 'no'
        hetero = ring.count { |atom| molecule.atoms[atom].element.symbol != 'C' }
        paragraph << "ring #{index + 1} size=#{ring.length} aromatic=#{flag} hetero=#{hetero} atoms=#{atom_numbers(ring, '-')}"
        sizes[ring.length] += 1
      end
      molecule.systems.each_with_index do |system, index|
        kinds[system[:kind]] += 1
        paragraph << "system #{index + 1} kind=#{system[:kind]} rings=#{atom_numbers(system[:rings])} atoms=#{system[:atoms]}"
      end
      doubles = molecule.ordered_bonds.select { |bond| bond.kind == 4 && bond.multiplicity == 2 }.map { |bond| atom_numbers(bond.ends, '=') }
      paragraph << 'kekule ' + (doubles.empty? ? '-' : doubles.join(' '))
      paragraphs << paragraph
    end
    paragraphs << ["SUMMARY molecules=#{molecules.length} cyclic=#{paragraphs.length} rings=#{total_rings} aromatic=#{total_aromatic}",
                   'sizes ' + (sizes.empty? ? '-' : sizes.sort.map { |size, count| "#{size}=#{count}" }.join(' ')),
                   'systems ' + SYSTEM_KINDS.map { |kind| "#{kind}=#{kinds[kind]}" }.join(' ')]
    paragraphs
  end

  def self.substructure_paragraphs(queries, molecules, by_name)
    paragraphs = []
    patterns = hits = contains = found = 0
    queries.each do |query|
      kind, id, args = query.values_at(:type, :id, :arguments)
      if kind == 'MATCH'
        patterns += 1
        pattern = query[:pattern]
        matches = molecules.filter_map do |molecule|
          count, unique, mapping = embeddings(pattern, molecule)
          [molecule, count, unique, mapping] if count.positive?
        end
        hits += matches.length
        paragraph = ["MATCH #{id} #{args[0]} atoms=#{pattern.atoms.length} bonds=#{pattern.bonds.length} hits=#{matches.length} embeddings=#{matches.sum { |match| match[1] }}"]
        matches.each { |molecule, count, unique, mapping| paragraph << "#{molecule.name} count=#{count} unique=#{unique} map=#{atom_numbers(mapping)}" }
        unless matches.empty?
          top = matches.each_with_index.min_by { |match, index| [-match[1], index] }.first
          paragraph << "top #{top[0].name} count=#{top[1]}"
        end
        paragraphs << paragraph
      elsif kind == 'CONTAINS'
        contains += 1
        first, second = args.map { |name| by_name[name] }
        count, unique, mapping = embeddings(molecule_pattern(first), second)
        text = "CONTAINS #{id} #{first.name} #{second.name} result="
        if count.positive?
          found += 1
          text += "yes count=#{count} unique=#{unique} map=#{atom_numbers(mapping)}"
        else
          text += 'no'
        end
        paragraphs << [text]
      end
    end
    paragraphs << ["SUMMARY patterns=#{patterns} hits=#{hits} contains=#{contains} found=#{found}"]
  end

  def self.similarity_paragraphs(queries, molecules, by_name)
    paragraphs = [["FINGERPRINTS molecules=#{molecules.length} size=1024 depth=5"] + molecules.map { |molecule| "#{molecule.name} bits=#{molecule.bits.length} paths=#{molecule.paths}" }]
    cache = {}
    similarity = ->(first, second) { cache[[first.order, second.order].sort] ||= tanimoto(first.bits, second.bits) }
    queries.each do |query|
      kind, id, args = query.values_at(:type, :id, :arguments)
      case kind
      when 'MATRIX'
        selected = args.map { |name| by_name[name] }
        paragraph = ["MATRIX #{id} size=#{selected.length}"]
        selected.each { |first| paragraph << "row #{first.name} " + selected.map { |second| fraction_text(similarity.call(first, second)) }.join(' ') }
        best_first, best_second = selected[0, 2]
        best = similarity.call(best_first, best_second)
        selected.each_with_index do |first, index|
          selected.drop(index + 1).each do |second|
            value = similarity.call(first, second)
            best_first, best_second, best = first, second, value if fraction_compare(value, best).positive?
          end
        end
        paragraph << "best #{best_first.name} #{best_second.name} #{fraction_text(best)}"
      when 'NEAREST', 'WITHIN'
        source = by_name[args[0]]
        neighbors = molecules.reject { |molecule| molecule.equal?(source) }.map { |molecule| [molecule, similarity.call(source, molecule)] }
        neighbors.sort! do |first, second|
          comparison = fraction_compare(second[1], first[1])
          comparison.zero? ? first[0].order <=> second[0].order : comparison
        end
        result = kind == 'NEAREST' ? neighbors.first(query[:count]) : neighbors.select { |_, value| fraction_compare(value, query[:threshold]) >= 0 }
        heading = "#{kind} #{id} #{source.name} "
        heading += "threshold=#{fraction_text(query[:threshold])} " if kind == 'WITHIN'
        paragraph = [heading + "count=#{result.length}"]
        result.each_with_index { |(molecule, value), index| paragraph << "#{index + 1} #{molecule.name} #{fraction_text(value)} common=#{value[0]}" }
      when 'COMPARE'
        first, second = args.map { |name| by_name[name] }
        value = similarity.call(first, second)
        paragraph = ["COMPARE #{id} #{first.name} #{second.name} bits=#{first.bits.length},#{second.bits.length} common=#{value[0]} union=#{value[1]} tanimoto=#{fraction_text(value)} identical=#{first.canonical == second.canonical ? 'yes' : 'no'}"]
      when 'CLUSTER'
        threshold = query[:threshold]
        neighbors = molecules.map do |first|
          molecules.filter_map { |second| second.order if !first.equal?(second) && fraction_compare(similarity.call(first, second), threshold) >= 0 }
        end
        assigned, clusters = Set.new, []
        molecules.each_index.sort_by { |number| [-neighbors[number].length, number] }.each do |center|
          next if assigned.include?(center)
          members = [center] + neighbors[center].reject { |neighbor| assigned.include?(neighbor) }
          clusters << members
          assigned.merge(members)
        end
        paragraph = ["CLUSTER #{id} threshold=#{fraction_text(threshold)} clusters=#{clusters.length} singletons=#{clusters.count { |members| members.length == 1 }}"]
        clusters.reject { |members| members.length == 1 }.each_with_index do |members, index|
          selected = members.map { |number| molecules[number] }
          paragraph << "cluster #{index + 1} centroid=#{selected.first.name} size=#{selected.length} members=#{member_names(selected)}"
        end
      else
        next
      end
      paragraphs << paragraph
    end
    paragraphs
  end

  def self.paragraphs_text(paragraphs) = paragraphs.map { |paragraph| paragraph.join("\n") }.join("\n\n") + "\n"

  def self.main
    elements, causes = read_elements('input/elements.txt'), Hash.new(0)
    molecules, molecule_errors = read_molecules(elements, causes)
    prepare_molecules(molecules)
    by_name = molecules.to_h { |molecule| [molecule.name, molecule] }
    queries, query_errors = read_queries(elements, by_name, causes)
    cause_lines = ["CAUSES kinds=#{causes.length}"] + causes.sort_by { |reason, count| [-count, reason] }.map { |reason, count| "#{reason}=#{count}" }
    outputs = {'properties.csv' => properties_lines(molecules).join("\n") + "\n",
               'canonical.txt' => paragraphs_text(canonical_paragraphs(molecules)),
               'rings.txt' => paragraphs_text(ring_paragraphs(molecules)),
               'substructure.txt' => paragraphs_text(substructure_paragraphs(queries, molecules, by_name)),
               'similarity.txt' => paragraphs_text(similarity_paragraphs(queries, molecules, by_name)),
               'errors.txt' => paragraphs_text([molecule_errors, query_errors, cause_lines])}
    FileUtils.mkdir_p('output')
    outputs.each { |filename, content| File.write(File.join('output', filename), content, mode: 'wb') }
  end
end

Chemistry.main if $PROGRAM_NAME == __FILE__
