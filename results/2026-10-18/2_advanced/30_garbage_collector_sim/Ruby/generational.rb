module GCSim
  class Generational < Copying
    attr_reader :remembered, :barriers, :remembers

    MARKING_KINDS = %w[major full].freeze
    TENURING_KINDS = %w[tenure full].freeze
    COLLECTION_STEPS = [%w[major minor], %w[full tenure]].freeze

    def initialize(size, young, age)
      super(size)
      @young = young
      @half = young / 2
      @promotion_age = age
      @remembered = Set.new
      @barriers = @remembers = 0
      @target = 0
    end

    def young?(obj) = obj.address < @young
    def old_blocks = free_blocks(@objects, @young, @size)
    def free_list = super() + old_blocks

    def write_barrier(target, value)
      return if young?(target)

      @barriers += 1
      @remembers += 1 if value && young?(value) && @remembered.add?(target)
    end

    def allocate(obj, roots, line)
      if fits?(obj)
        place(obj)
        return true
      end
      COLLECTION_STEPS.each do |marking_kind, copying_kind|
        kind = largest_free(old_blocks) < @top - @base ? marking_kind : copying_kind
        return false unless collect(kind, roots, line, obj.size)

        if fits?(obj)
          place(obj)
          return true
        end
      end
      false
    end

    def sweep_old(record)
      @objects = @objects.select do |obj|
        next true if young?(obj)

        record.work += 1
        unless obj.marked
          record.freed.add(obj)
          @remembered.delete(obj)
        end
        obj.marked
      end
    end

    def evacuate(obj, record, pending, queue)
      return true unless obj && pending.delete?(obj)

      obj.age += 1
      obj.moves += 1
      if TENURING_KINDS.include?(record.kind) || obj.age >= @promotion_age
        address = first_fit(old_blocks, obj.size)
        return false if address.nil?

        obj.address = address
        record.promoted.add(obj)
      else
        obj.address = @target
        @target += obj.size
      end
      record.moved.add(obj)
      record.live.add(obj) unless MARKING_KINDS.include?(record.kind)
      queue << obj
      true
    end

    def evacuate_fields(obj, record, pending, queue)
      obj.fields.all? { |child| evacuate(child, record, pending, queue) }
    end

    def collect(kind, roots, line, request)
      record = new_record(line, request, kind)
      if MARKING_KINDS.include?(kind)
        Marking.mark(record, roots, @objects)
        sweep_old(record)
      end
      pending = @objects.select { |obj| young?(obj) }.to_set
      destination = @half - @base
      @target = destination
      queue = []
      record.work += roots.length
      roots.each { |root| return false unless evacuate(root, record, pending, queue) }
      by_address(@remembered).each do |obj|
        record.work += 1 + obj.fields.length
        return false unless evacuate_fields(obj, record, pending, queue)
      end
      index = 0
      while index < queue.length
        obj = queue[index]
        index += 1
        record.work += obj.size + obj.fields.length
        return false unless evacuate_fields(obj, record, pending, queue)
      end
      @objects = @objects.reject do |obj|
        dead = pending.include?(obj)
        record.freed.add(obj) if dead
        dead
      end
      @base = destination
      @top = @target
      @remembered = @objects.select do |obj|
        !young?(obj) && obj.fields.any? { |child| child && young?(child) }
      end.to_set
      finish_record(record)
      true
    end
  end
end
