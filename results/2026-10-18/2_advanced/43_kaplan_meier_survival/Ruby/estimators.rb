require_relative "numerics"

module Estimators
  module_function

  def risk_sets(subjects)
    counts = Hash.new(0)
    events = Hash.new(0)
    subjects.each do |subject|
      counts[subject.time] += 1
      events[subject.time] += subject.event
    end
    risk = subjects.length
    counts.keys.sort.map do |time|
      row = [time, risk, events[time], counts[time] - events[time]]
      risk -= counts[time]
      row
    end
  end

  def kaplan_meier(subjects)
    times = risk_sets(subjects).select { |_, _, deaths, _| deaths.positive? }
    survival = 1.0
    greenwood = hazard = hazard_variance = 0.0
    times.each_with_index.map do |(time, risk, deaths, _), index|
      survival *= (risk - deaths).to_f / risk
      if risk == deaths
        greenwood = nil
      elsif !greenwood.nil?
        greenwood += deaths.to_f / (risk * (risk - deaths))
      end
      if survival.zero?
        error = lower = upper = nil
      else
        error = survival * Math.sqrt(greenwood)
        logarithm = Math.log(survival)
        omega = Numerics::Z95 * Math.sqrt(greenwood) / (-logarithm)
        lower = Math.exp(logarithm * Math.exp(omega))
        upper = Math.exp(logarithm * Math.exp(-omega))
      end
      hazard += deaths.to_f / risk
      hazard_variance += deaths.to_f / (risk * risk)
      next_time = times[index + 1]&.first
      censored = subjects.count do |subject|
        subject.event.zero? && subject.time >= time && (next_time.nil? || subject.time < next_time)
      end
      { time: time, risk: risk, events: deaths, censored: censored, survival: survival,
        se: error, lower: lower, upper: upper, hazard: hazard, hazard_se: Math.sqrt(hazard_variance) }
    end
  end

  def row_at(rows, time)
    rows.reverse_each.find { |row| row[:time] <= time } ||
      { survival: 1.0, se: 0.0, lower: nil, upper: nil, hazard: 0.0, hazard_se: 0.0 }
  end

  def life_table(subjects, width, count)
    survival = 1.0
    variance_sum = 0.0
    Array.new(count) do |interval|
      start = interval * width
      finish = (interval + 1) * width
      risk = subjects.count { |subject| subject.time >= start }
      deaths = subjects.count { |subject| subject.time >= start && subject.time < finish && subject.event == 1 }
      withdrawn = subjects.count { |subject| subject.time >= start && subject.time < finish && subject.event.zero? }
      f = 2 * risk - withdrawn
      survival *= (f - 2 * deaths).to_f / f
      variance_sum += (4 * deaths).to_f / (f * (f - 2 * deaths))
      { start: start, end: finish, risk: risk, events: deaths, withdrawn: withdrawn,
        exposed: f / 2.0, q: (2 * deaths).to_f / f, survival: survival,
        se: survival * Math.sqrt(variance_sum), hazard: (2000 * deaths).to_f / (width * (f - deaths)) }
    end
  end
end
