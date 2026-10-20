module Coloring
  class Attempt
    def initialize(courses, fixed, graph, candidate_slots, limit)
      @courses = courses
      @assignment = fixed.dup
      @graph = graph
      @candidate_slots = candidate_slots
      @limit = limit
      @backtracks = 0
      @dead_end = nil
      @aborted = false
      @order = []
    end

    def run
      success = search
      { success: success, assignment: @assignment, order: @order,
        backtracks: @backtracks, dead_end: @dead_end }
    end

    private

    def saturation(id)
      @graph.neighbours[id].keys.filter_map { |other| @assignment[other] }.uniq.length
    end

    def search
      remaining = @courses.reject { |id| @assignment.key?(id) }
      return true if remaining.empty?

      course = remaining.min_by { |id| [-saturation(id), -@graph.degree(id), id] }
      selected_saturation = saturation(course)
      @candidate_slots.call(course, @assignment).each do |slot|
        @assignment[course] = slot
        if search
          @order.unshift({ course: course, slot: slot, saturation: selected_saturation })
          return true
        end
        @assignment.delete(course)
        return false if @aborted
      end
      @backtracks += 1
      @dead_end = course
      @aborted = @backtracks > @limit
      false
    end
  end

  def self.greedy(order, graph)
    colours = {}
    order.each do |id|
      used = graph.neighbours[id].keys.filter_map { |other| colours[other] }
      colour = 1
      colour += 1 while used.include?(colour)
      colours[id] = colour
    end
    colours.values.max || 0
  end
end
