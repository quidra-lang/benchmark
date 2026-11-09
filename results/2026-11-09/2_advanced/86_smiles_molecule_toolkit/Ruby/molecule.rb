require 'set'

module Chemistry
  Element = Struct.new(:symbol, :number, :weight, :valences)
  Atom = Struct.new(:element, :aromatic, :mass, :charge, :hydrogens, :bracket, :column)
  ORGANIC = %w[B C N O P S F Cl Br I].freeze
  AROMATIC = %w[B C N O P S].freeze
  BOND_TYPES = {'-' => 1, '/' => 1, '\\' => 1, '=' => 2, '#' => 3, ':' => 4}.freeze
  BASE_VALUES = [0, 1, 2, 3, 1].freeze

  class AnalysisError < StandardError
    attr_reader :reason, :column
    def initialize(reason, column)
      super(reason)
      @reason, @column = reason, column
    end
  end

  class Bond
    attr_accessor :ends, :symbol, :kind, :multiplicity, :ring
    def initialize(first, second, symbol)
      @ends, @symbol = [first, second].sort, symbol
      @kind, @multiplicity, @ring = nil, 0, false
    end
  end

  class Molecule
    attr_accessor :elements, :atoms, :neighbors, :bonds, :rings, :ring_atoms, :name,
                  :order, :properties, :canonical, :classes, :scaffold, :systems,
                  :aromatic_rings, :bits, :paths
    def initialize(elements)
      @elements, @atoms, @neighbors, @bonds = elements, [], [], {}
      @rings, @ring_atoms = [], Set.new
    end
    def add_atom(atom)
      @atoms << atom
      @neighbors << {}
      @atoms.length - 1
    end
    def add_bond(first, second, symbol)
      bond = Bond.new(first, second, symbol)
      @bonds[bond.ends] = bond
      @neighbors[first][second] = @neighbors[second][first] = bond
      bond
    end
    def ordered_bonds = @bonds.keys.sort.map { |key| @bonds[key] }
    def degree(number) = @neighbors[number].length
    def base_total(number) = @neighbors[number].values.sum { |bond| BASE_VALUES[bond.kind] }
    def bond_total(number) = @neighbors[number].values.sum(&:multiplicity)
  end

  def self.read_elements(path)
    elements = {}
    File.foreach(path, chomp: true) do |line|
      next if line.empty? || line.start_with?('#')
      symbol, number, weight, valences = line.split(' ')
      elements[symbol] = Element.new(symbol, number.to_i, weight.to_i, valences.split(',').map(&:to_i))
    end
    elements
  end

  def self.needs_pi(molecule, number, hydrogens = nil)
    atom = molecule.atoms[number]
    hydrogens = atom.hydrogens if hydrogens.nil?
    atom.aromatic && atom.element.valences.first + atom.charge >= molecule.base_total(number) + hydrogens + 1
  end

  def self.organic_hydrogens(atom, total)
    valence = atom.element.valences.find { |value| value >= total }
    valence && valence - total
  end
end
