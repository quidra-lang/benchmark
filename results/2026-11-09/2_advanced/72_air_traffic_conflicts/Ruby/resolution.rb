require_relative 'flight_plans'

module Resolution
  module_function

  def manoeuvres(max_delay)
    [['level_up', 10], ['level_down', -10], ['speed_down', nil]] +
      (60..max_delay).step(60).map { |delay| ["delay_#{delay}", delay] }
  end

  def propose(plan, name, amount, types, params)
    changed = FlightPlans.clone_plan(plan)
    case name
    when 'level_up', 'level_down'
      changed[:offset] += amount
      return if FlightPlans.levels(changed).any? { |level| level < params[:level_min] || level > params[:level_max] }
    when 'speed_down'
      changed[:speed] = changed[:speed] * 9 / 10
      return if changed[:speed] < types[changed[:type]][:minimum]
    else
      changed[:delay] += amount
    end
    changed
  end

  def priority(first, second)
    [first, second].sort_by { |plan| [plan[:departure] + plan[:delay], plan[:callsign]] }.reverse.map { |plan| plan[:callsign] }
  end
end
