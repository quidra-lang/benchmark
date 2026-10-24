module LineBreaker
  module_function

  def line_class(slack, last)
    return 1 if last
    return 0 if slack <= 1
    return 1 if slack <= 3
    return 2 if slack <= 6

    3
  end

  def line_cost(metrics, start, finish, previous_class, params)
    slack = metrics.slack(start, finish)
    last = finish == metrics.end_index
    current_class = line_class(slack, last)
    cost = params[:line_penalty]
    cost += slack < 0 ? params[:overfull_penalty] : (last ? 0 : slack * slack)
    if metrics.breaks[finish].midword
      cost += params[:hyphen_penalty]
      cost += params[:double_hyphen_demerit] if metrics.breaks[start].midword
    end
    cost += params[:final_hyphen_demerit] if last && metrics.breaks[start].midword
    cost += params[:fitness_demerit] if (current_class - previous_class).abs >= 2
    cost
  end

  def breaking_cost(metrics, breaking, params)
    total, start, previous_class = 0, 0, 1
    breaking.each do |finish|
      total += line_cost(metrics, start, finish, previous_class, params)
      previous_class = line_class(metrics.slack(start, finish), finish == metrics.end_index)
      start = finish
    end
    total
  end

  def knuth_plass(metrics, params)
    states = Array.new(metrics.end_index + 1) { {} }
    states[0][1] = [0, nil, nil]
    1.upto(metrics.end_index) do |finish|
      (finish - 1).downto(0) do |start|
        slack = metrics.slack(start, finish)
        # Earlier starts only lengthen the span, and C1 never exceeds C2.
        break if slack < 0 && finish != start + 1

        current_class = line_class(slack, finish == metrics.end_index)
        states[start].each do |previous_class, previous|
          cost = previous[0] + line_cost(metrics, start, finish, previous_class, params)
          candidate = [cost, start, previous_class]
          best = states[finish][current_class]
          states[finish][current_class] = candidate if best.nil? || (candidate <=> best).negative?
        end
      end
    end
    breaking, position, current_class = [], metrics.end_index, 1
    cost = states[position][current_class][0]
    until position.zero?
      breaking << position
      _cost, position, current_class = states[position][current_class]
    end
    [breaking.reverse, cost]
  end

  def greedy(metrics, params)
    breaking, start = [], 0
    while start < metrics.end_index
      chosen = start + 1
      if metrics.slack(start, chosen) >= 0
        (chosen + 1).upto(metrics.end_index) do |finish|
          break if metrics.slack(start, finish) < 0

          chosen = finish
        end
      end
      breaking << chosen
      start = chosen
    end
    [breaking, breaking_cost(metrics, breaking, params)]
  end

  def break_text(metrics, method, params)
    method == 'kp' ? knuth_plass(metrics, params) : greedy(metrics, params)
  end
end
