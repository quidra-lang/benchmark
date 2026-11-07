require 'set'

def can_complete?(node)
  pending = [[node, false]]
  until pending.empty?
    current, expanded = pending.pop
    next unless current.completes.nil?
    if expanded
      current.completes = if current.kind == 'block'
                            current.statements.all?(&:completes)
                          else
                            current.then_branch.completes || current.otherwise.completes
                          end
    elsif current.kind == 'block' || (current.kind == 'if' && current.otherwise)
      pending << [current, true]
      children = current.kind == 'block' ? current.statements : [current.then_branch, current.otherwise]
      children.reverse_each { |child| pending << [child, false] }
    else
      current.completes = !%w[return break continue].include?(current.kind)
    end
  end
  node.completes
end

class Analyzer
  attr_reader :globals, :functions, :variables
  def initialize(declarations, end_position)
    @declarations, @end_position = declarations, end_position
    @globals, @functions, @variables, @scopes = {}, [], [], []
  end
  def fail_at(position, message) = raise(CompileError.new('semantic', position, message))
  def prepare(node)
    node.references, node.read_accesses = [], 0
    if node.kind == 'function'
      node.calls = Set.new
      @functions << node
    else
      @variables << node
    end
  end
  def lookup(name, position, read: true)
    scope = @scopes.reverse.find { |table| table.key?(name) }
    referent = scope ? scope[name] : @globals[name]
    if referent
      referent.references << position
      referent.read_accesses += 1 if read
    end
    referent
  end
  def variable(name, position, indexed, read: true)
    referent = lookup(name, position, read: read)
    fail_at(position, "undeclared identifier '#{name}'") unless referent
    fail_at(position, "'#{name}' is a function, not a variable") if referent.kind == 'function'
    array = referent.kind == 'global' && !referent.size.nil?
    fail_at(position, "'#{name}' is not an array") if indexed && !array
    fail_at(position, "array '#{name}' used without index") if !indexed && array
    referent
  end
  def expression(node, call_statement: false)
    pending = [[:visit, node, call_statement]]
    until pending.empty?
      action, current, detail = pending.pop
      if action == :argument
        argument, parameter, number = detail
        if argument.type != parameter.type
          fail_at(current.position, "argument #{number} of '#{current.name}' must be #{parameter.type}")
        end
      elsif action == :finish
        finish_expression(current, detail)
      else
        case current.kind
        when 'integer', 'read' then current.type = 'int'
        when 'boolean' then current.type = 'bool'
        when 'variable', 'array'
          current.referent = variable(current.name, current.position, current.kind == 'array')
          if current.kind == 'array'
            pending << [:finish, current]
            pending << [:visit, current.index, false]
          else
            current.type = current.referent.type
          end
        when 'call'
          referent = lookup(current.name, current.position)
          fail_at(current.position, "undeclared function '#{current.name}'") unless referent
          fail_at(current.position, "'#{current.name}' is not a function") unless referent.kind == 'function'
          current.referent = referent
          @function.calls << referent
          expected, found = referent.parameters.length, current.arguments.length
          if expected != found
            fail_at(current.position, "wrong number of arguments to '#{current.name}' (expected #{expected}, found #{found})")
          end
          pending << [:finish, current, detail]
          (found - 1).downto(0) do |index|
            argument = current.arguments[index]
            pending << [:argument, current, [argument, referent.parameters[index], index + 1]]
            pending << [:visit, argument, false]
          end
        when 'unary', 'binary'
          pending << [:finish, current]
          Tree.expression_children(current).reverse_each { |child| pending << [:visit, child, false] }
        end
      end
    end
    node.type
  end
  def finish_expression(node, call_statement)
    node.type = case node.kind
                when 'array'
                  fail_at(node.position, "index of '#{node.name}' must be int") unless node.index.type == 'int'
                  node.referent.type
                when 'call'
                  if !call_statement && node.referent.type == 'void'
                    fail_at(node.position, "void function '#{node.name}' used as a value")
                  end
                  node.referent.type
                when 'unary'
                  required = node.operator == '-' ? 'int' : 'bool'
                  fail_at(node.position, "operator '#{node.operator}' requires #{required} operand") unless node.operand.type == required
                  node.operand.type
                when 'binary'
                  left, right, operator = node.left.type, node.right.type, node.operator
                  if %w[+ - * / % < <= > >=].include?(operator)
                    fail_at(node.position, "operator '#{operator}' requires int operands") unless left == 'int' && right == 'int'
                    %w[+ - * / %].include?(operator) ? 'int' : 'bool'
                  elsif %w[== !=].include?(operator)
                    fail_at(node.position, "operator '#{operator}' requires operands of the same type") unless left == right
                    'bool'
                  else
                    fail_at(node.position, "operator '#{operator}' requires bool operands") unless left == 'bool' && right == 'bool'
                    'bool'
                  end
                end
  end
  def constant_initializer(node)
    positions, pending = [], [node]
    until pending.empty?
      current = pending.pop
      positions << current.position if %w[variable array call read].include?(current.kind)
      pending.concat(Tree.expression_children(current))
    end
    fail_at(positions.min, 'global initializer must be constant') unless positions.empty?
    expression(node)
  end
  def statement(node, loop_depth = 0)
    pending = [[node, loop_depth]]
    until pending.empty?
      current, depth = pending.pop
      if current == :close_scope
        @scopes.pop
      elsif current == :for_condition
        if depth.condition && expression(depth.condition) != 'bool'
          fail_at(depth.position, "condition of 'for' must be bool")
        end
      else
        check_statement(current, depth, pending)
      end
    end
  end
  def check_statement(node, loop_depth, pending)
    case node.kind
    when 'declaration'
      fail_at(node.name_position, "variable '#{node.name}' cannot have type void") if node.type == 'void'
      fail_at(node.name_position, "redeclaration of '#{node.name}'") if @scopes.last.key?(node.name)
      if node.initializer && expression(node.initializer) != node.type
        fail_at(node.name_position, "type mismatch in initialization of '#{node.name}'")
      end
      prepare(node)
      @scopes.last[node.name] = node
    when 'assignment'
      node.referent = variable(node.name, node.position, !node.index.nil?, read: false)
      fail_at(node.position, "index of '#{node.name}' must be int") if node.index && expression(node.index) != 'int'
      if expression(node.value) != node.referent.type
        fail_at(node.position, "type mismatch in assignment to '#{node.name}'")
      end
    when 'call_statement' then expression(node.expression, call_statement: true)
    when 'if', 'while'
      fail_at(node.position, "condition of '#{node.kind}' must be bool") unless expression(node.condition) == 'bool'
      if node.kind == 'if'
        pending << [node.otherwise, loop_depth] if node.otherwise
        pending << [node.then_branch, loop_depth]
      else
        pending << [node.body, loop_depth + 1]
      end
    when 'for'
      @scopes << {}
      pending << [:close_scope]
      pending << [node.body, loop_depth + 1]
      pending << [node.update, loop_depth] if node.update
      pending << [:for_condition, node]
      pending << [node.initial, loop_depth] if node.initial
    when 'break', 'continue'
      fail_at(node.position, "'#{node.kind}' outside loop") if loop_depth.zero?
    when 'return'
      if @function.type == 'void'
        fail_at(node.position, "function '#{@function.name}' must not return a value") if node.value
      else
        fail_at(node.position, "function '#{@function.name}' must return a value") unless node.value
        if expression(node.value) != @function.type
          fail_at(node.position, "return value of '#{@function.name}' must be #{@function.type}")
        end
      end
    when 'print'
      node.arguments.each_with_index do |argument, index|
        fail_at(node.position, "argument #{index + 1} of 'print' must be int") unless expression(argument) == 'int'
      end
    when 'block'
      @scopes << {}
      pending << [:close_scope]
      node.statements.reverse_each { |child| pending << [child, loop_depth] }
    end
  end
  def analyze
    @declarations.each do |node|
      if node.kind == 'global'
        if node.size
          fail_at(node.name_position, "array '#{node.name}' must have element type int") unless node.type == 'int'
          fail_at(node.size_position, "array '#{node.name}' must have a positive size") if node.size.zero?
        elsif node.type == 'void'
          fail_at(node.name_position, "variable '#{node.name}' cannot have type void")
        end
      end
      fail_at(node.name_position, "redeclaration of '#{node.name}'") if @globals.key?(node.name)
      if node.kind == 'global'
        if node.initializer && constant_initializer(node.initializer) != node.type
          fail_at(node.name_position, "type mismatch in initialization of '#{node.name}'")
        end
      else
        names = Set.new
        node.parameters.each do |parameter|
          fail_at(parameter.name_position, "parameter '#{parameter.name}' cannot have type void") if parameter.type == 'void'
          fail_at(parameter.name_position, "redeclaration of '#{parameter.name}'") if names.include?(parameter.name)
          names << parameter.name
          prepare(parameter)
        end
      end
      prepare(node)
      @globals[node.name] = node
    end
    main = @globals['main']
    fail_at(@end_position, 'no main function') unless main && main.kind == 'function'
    unless main.type == 'void' && main.parameters.empty?
      fail_at(main.name_position, "main must be declared as 'void main()'")
    end
    @functions.each do |function|
      @function = function
      @scopes = [function.parameters.to_h { |parameter| [parameter.name, parameter] }]
      function.body.statements.each { |node| statement(node) }
      if function.type != 'void' && can_complete?(function.body)
        fail_at(function.name_position, "missing return in function '#{function.name}'")
      end
    end
    self
  end
end
