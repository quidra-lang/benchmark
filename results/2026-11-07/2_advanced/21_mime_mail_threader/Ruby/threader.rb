# frozen_string_literal: true

module Threader
  class Container
    attr_accessor :id, :message, :parent, :children, :subject, :key

    def initialize(id = '')
      @id = id
      @message = nil
      @parent = nil
      @children = []
      @subject = nil
      @key = nil
    end
  end

  def self.ancestor?(candidate, node)
    while node
      return true if candidate.equal?(node)

      node = node.parent
    end
    false
  end

  def self.attach(child, parent)
    child.parent = parent
    parent.children << child
  end

  def self.prune(roots)
    replacements = {}
    stack = roots.reverse.map { |node| [node, true, false] }
    until stack.empty?
      node, root, visited = stack.pop
      unless visited
        stack << [node, root, true]
        node.children.reverse_each { |child| stack << [child, false, false] }
        next
      end
      children = []
      node.children.each { |child| children.concat(replacements.delete(child)) }
      node.children = children
      children.each { |child| child.parent = node }
      if node.message || (root && children.length >= 2)
        replacements[node] = [node]
      else
        children.each { |child| child.parent = node.parent }
        replacements[node] = children
        node.children = []
      end
    end
    roots.flat_map { |root| replacements.fetch(root) }
  end

  def self.sort(roots)
    nodes = []
    stack = roots.dup
    until stack.empty?
      node = stack.pop
      nodes << node
      node.children.each { |child| stack << child }
    end
    nodes.reverse_each do |node|
      node.children.sort_by!(&:key)
      node.key = node.message ? node.message[:key] : node.children.first.key
    end
    roots.sort_by!(&:key)
  end

  def self.subject(node)
    return node.subject unless node.subject.nil?

    node.message ? node.message[:base_subject] : node.children.first.message[:base_subject]
  end

  def self.merge_subjects(roots)
    groups = {}
    roots.each do |root|
      text = subject(root)
      next if text.empty?

      (groups[text] ||= []) << root
    end
    groups.each do |text, group|
      next if group.length < 2

      target = group.find { |root| root.message.nil? }
      unless target
        originals = group.select { |root| !root.message[:reply] }
        target = originals.first if originals.length == 1
      end
      unless target
        target = Container.new
        target.subject = text
        roots << target
      end
      group.each do |root|
        next if root.equal?(target)

        roots.delete(root)
        if root.message
          attach(root, target)
        else
          root.children.each { |child| attach(child, target) }
          root.children = []
        end
      end
    end
  end

  def self.build(messages)
    containers = []
    id_table = {}
    lookup = lambda do |id|
      unless id_table.key?(id)
        container = Container.new(id)
        id_table[id] = container
        containers << container
      end
      id_table.fetch(id)
    end
    messages.each do |message|
      if message[:id].empty?
        current = Container.new
        containers << current
      else
        current = lookup.call(message[:id])
      end
      current.message = message
      references = message[:refs].map { |id| lookup.call(id) }
      references.each_cons(2) do |first, second|
        attach(second, first) if second.parent.nil? && !ancestor?(second, first)
      end
      if current.parent
        current.parent.children.delete(current)
        current.parent = nil
      end
      attach(current, references.last) if !references.empty? && !ancestor?(current, references.last)
    end
    roots = prune(containers.select { |node| node.parent.nil? })
    sort(roots)
    merge_subjects(roots)
    sort(roots)
    roots
  end
end
