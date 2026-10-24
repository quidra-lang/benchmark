module Picker
  module_function

  def detect(station, params)
    samples = station[:samples]
    mean = samples.sum.div(samples.length)
    detrended = samples.map { |s| s - mean }
    energy = detrended.map { |d| d * d }
    prefix = [0]
    energy.each { |e| prefix << prefix[-1] + e }
    sw, lw = params.values_at(:sta_window, :lta_window)
    pon, qon = params[:trigger_on]
    poff, qoff = params[:trigger_off]
    beginning = nil
    peak_ratio = nil
    triggers = 0
    short = 0
    picks = []
    finish = lambda do |ending|
      triggers += 1
      duration = ending - beginning
      if duration < params[:min_duration]
        short += 1
        next
      end
      k = beginning
      k -= 1 while k - 1 >= beginning - sw + 1 && energy[k - 1] >= params[:noise_level]
      last = [k + params[:amplitude_window], samples.length].min
      amplitude = (k...last).map { |j| detrended[j].abs }.max
      clipped = (k...last).any? { |j| samples[j].abs >= params[:clip_level] }
      sample_number = station[:start] + k
      picks << {station: station, sample: sample_number, time: sample_number / 100.0,
                duration: duration, ratio: peak_ratio, amplitude: amplitude, clipped: clipped,
                state: :unassociated, event: 0, residual: nil, assigned: false}
    end
    (sw + lw - 1...samples.length).each do |i|
      sta = prefix[i + 1] - prefix[i - sw + 1]
      lta = prefix[i - sw + 1] - prefix[i - sw - lw + 1]
      if beginning.nil?
        if sta * lw * qon >= pon * lta * sw
          beginning = i
          peak_ratio = (sta * lw).to_f / (lta * sw).to_f
        end
      elsif sta * lw * qoff < poff * lta * sw
        finish.call(i)
        beginning = nil
      else
        ratio = (sta * lw).to_f / (lta * sw).to_f
        peak_ratio = ratio if ratio > peak_ratio
      end
    end
    finish.call(samples.length) unless beginning.nil?
    absolute = detrended.map(&:abs).sort
    middle = absolute.length / 2
    noise = if absolute.length.odd?
              absolute[middle]
            else
              (absolute[middle - 1] + absolute[middle]) / 2.0
            end
    station.merge!(mean: mean, noise: noise, peak: absolute.last,
                   clipped_samples: samples.count { |s| s.abs >= params[:clip_level] },
                   triggers: triggers, short: short, picks: picks)
    picks
  end
end
