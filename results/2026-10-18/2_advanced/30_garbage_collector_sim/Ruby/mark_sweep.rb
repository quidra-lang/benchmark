module GCSim
  module Marking
    extend self

    def push(record, stack, obj)
      obj.marked = true
      stack << obj
      record.stack = [record.stack, stack.length].max
    end

    def mark(record, roots, objects)
      objects.each { |obj| obj.marked = false }
      record.work += roots.length
      stack = []
      roots.each do |root|
        next if root.nil? || root.marked

        push(record, stack, root)
        until stack.empty?
          obj = stack.pop
          record.live.add(obj)
          record.work += 1 + obj.fields.length
          obj.fields.each { |child| push(record, stack, child) if child && !child.marked }
        end
      end
    end

    def sweep(record, objects)
      record.work += objects.length
      objects.select do |obj|
        record.freed.add(obj) unless obj.marked
        obj.marked
      end
    end
  end

  class MarkSweep < HeapState
    def allocate(obj, roots, line)
      address = first_fit(free_list, obj.size)
      if address.nil?
        collect(roots, line, obj.size)
        address = first_fit(free_list, obj.size)
        return false if address.nil?
      end
      obj.address = address
      @objects << obj
      true
    end

    def collect(roots, line, request)
      record = new_record(line, request, 'sweep')
      Marking.mark(record, roots, @objects)
      @objects = Marking.sweep(record, @objects)
      finish_record(record)
    end
  end

  class MarkCompact < HeapState
    def initialize(size)
      super
      @top = 0
    end

    def free_list = @top < @size ? [[@top, @size - @top]] : []

    def allocate(obj, roots, line)
      if @top + obj.size > @size
        collect(roots, line, obj.size)
        return false if @top + obj.size > @size
      end
      obj.address = @top
      @top += obj.size
      @objects << obj
      true
    end

    def collect(roots, line, request)
      record = new_record(line, request, 'compact')
      Marking.mark(record, roots, @objects)
      record.work += @objects.length + roots.length
      destination = 0
      @objects = by_address(@objects).select do |obj|
        if obj.marked
          record.work += obj.fields.length
          if obj.address != destination
            record.moved.add(obj)
            record.work += obj.size
            obj.address = destination
            obj.moves += 1
          end
          destination += obj.size
          true
        else
          record.freed.add(obj)
          false
        end
      end
      @top = destination
      finish_record(record)
    end
  end
end
