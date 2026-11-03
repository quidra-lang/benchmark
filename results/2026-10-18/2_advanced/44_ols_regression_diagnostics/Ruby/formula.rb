module Formula
  class Factor
    attr_reader :name, :column, :categorical

    def initialize(name)
      @name = name
      @categorical = name.start_with?('C(')
      @power = 1
      if @categorical
        @column = name[2...-1]
      elsif name.start_with?('I(')
        @column, power = name[2...-1].split('^')
        @power = power.to_i
      else
        @column = name
      end
    end

    def components(levels)
      return [[self, @name, nil]] unless @categorical

      levels[@column].drop(1).map { |level| [self, @name + level, level] }
    end

    def value(row, level)
      value = row[@column]
      return value == level ? 1.0 : 0.0 if @categorical
      return value * value if @power == 2
      return value * value * value if @power == 3

      value
    end
  end

  class Term
    attr_reader :factors, :name, :factor_names

    def initialize(factors)
      @factors = factors
      @name = factors.map(&:name).join(':')
      @factor_names = factors.map(&:name).sort
    end

    def contained_in?(other)
      @factor_names.length < other.factor_names.length &&
        (@factor_names - other.factor_names).empty?
    end
  end

  class Model
    attr_reader :original, :weight, :response, :terms, :factor_columns,
                :categorical_columns, :variables

    def initialize(line)
      @original, separator, weight = line.partition(' weights=')
      @weight = separator.empty? ? nil : weight
      @response, expressions = @original.split(' ~ ')
      @terms = []
      seen = {}
      expressions.split(' + ').each do |expression|
        if expression.include?('*')
          factors = expression.split('*').map { |name| Factor.new(name) }
          expanded = (1..factors.length).flat_map { |size| factors.combination(size).to_a }
        else
          expanded = [expression.split(':').map { |name| Factor.new(name) }]
        end
        expanded.each do |factors|
          term = Term.new(factors)
          next if seen[term.factor_names]

          seen[term.factor_names] = true
          @terms << term
        end
      end
      factors = @terms.flat_map(&:factors)
      @factor_columns = factors.map(&:column).uniq
      @categorical_columns = factors.select(&:categorical).map(&:column).uniq
      @variables = (@factor_columns + [@response, @weight].compact).uniq
    end

    def format(term_indices)
      names = term_indices.sort.map { |index| @terms[index].name }
      @response + ' ~ ' + (names.empty? ? '1' : names.join(' + '))
    end

    def removable(term_indices)
      term_indices.sort.select do |index|
        term_indices.none? { |other| @terms[index].contained_in?(@terms[other]) }
      end
    end

    def candidates(term_indices)
      @terms.each_index.select do |index|
        !term_indices.include?(index) && @terms.each_index.all? { |other|
          !@terms[other].contained_in?(@terms[index]) || term_indices.include?(other)
        }
      end
    end

    def hierarchical?(term_indices)
      term_indices.all? do |index|
        @terms.each_index.all? do |other|
          !@terms[other].contained_in?(@terms[index]) || term_indices.include?(other)
        end
      end
    end
  end

  class DesignColumn
    attr_reader :term_index, :name

    def initialize(term_index, components)
      @term_index = term_index
      @components = components
      @name = components.empty? ? '(Intercept)' : components.map { |part| part[1] }.join(':')
    end

    def value(row)
      return 1.0 if @components.empty?

      factor, _, level = @components[0]
      value = factor.value(row, level)
      @components.drop(1).each do |part|
        value *= part[0].value(row, part[2])
      end
      value
    end
  end

  class Design
    attr_reader :model, :row_numbers, :rows, :levels, :columns, :matrix, :response, :weights

    def initialize(model, data)
      @model = model
      @row_numbers = []
      @rows = []
      data.rows.each_with_index do |row, i|
        next unless model.variables.all? { |column| !row[column].nil? }

        @row_numbers << i + 1
        @rows << row
      end
      @levels = model.categorical_columns.to_h do |column|
        [column, @rows.map { |row| row[column] }.uniq.sort]
      end
      @columns = [DesignColumn.new(nil, [])]
      model.terms.each_with_index do |term, index|
        # Extend tuples from the outside so the first factor changes fastest.
        tuples = [[]]
        term.factors.each do |factor|
          tuples = factor.components(@levels).flat_map do |component|
            tuples.map { |tuple| tuple + [component] }
          end
        end
        tuples.each { |tuple| @columns << DesignColumn.new(index, tuple) }
      end
      @matrix = @rows.map { |row| values(row) }
      @response = @rows.map { |row| row[model.response] }
      @weights = @rows.map { |row| model.weight ? row[model.weight] : 1.0 }
    end

    def values(row)
      @columns.map { |column| column.value(row) }
    end

    def subset_matrix(term_indices)
      indices = @columns.each_index.select do |j|
        @columns[j].term_index.nil? || term_indices.include?(@columns[j].term_index)
      end
      @matrix.map { |row| indices.map { |j| row[j] } }
    end

    def predictable?(row)
      @model.factor_columns.all? do |column|
        value = row[column]
        !value.nil? && (!@levels.key?(column) || @levels[column].include?(value))
      end
    end
  end
end
