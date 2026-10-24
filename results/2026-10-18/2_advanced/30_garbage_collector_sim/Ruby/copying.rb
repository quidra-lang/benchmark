module GCSim
  class Copying < HeapState
    def initialize(size)
      super
      @half = size / 2
      @base = @top = 0
    end

    def free_list
      limit = @base + @half
      @top < limit ? [[@top, limit - @top]] : []
    end

    def inactive_range
      first = @half - @base
      [first, first + @half]
    end

    def fits?(obj) = @top + obj.size <= @base + @half

    def place(obj)
      obj.address = @top
      @top += obj.size
      @objects << obj
    end

    def allocate(obj, roots, line)
      unless fits?(obj)
        collect(roots, line, obj.size)
        return false unless fits?(obj)
      end
      place(obj)
      true
    end

    def copy(obj, record, copied, queue)
      return unless obj && copied.add?(obj)

      obj.address = @top
      @top += obj.size
      obj.moves += 1
      record.live.add(obj)
      record.moved.add(obj)
      queue << obj
    end

    def collect(roots, line, request)
      record = new_record(line, request, 'copy')
      @base = @half - @base
      @top = @base
      copied = Set.new
      queue = []
      record.work += roots.length
      roots.each { |root| copy(root, record, copied, queue) }
      index = 0
      while index < queue.length
        obj = queue[index]
        index += 1
        record.work += obj.size + obj.fields.length
        obj.fields.each { |child| copy(child, record, copied, queue) }
      end
      @objects.each { |obj| record.freed.add(obj) unless copied.include?(obj) }
      @objects = queue
      finish_record(record)
    end
  end
end
