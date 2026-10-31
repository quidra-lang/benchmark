require 'date'

module Records
  module_function

  def minute(text)
    DateTime.strptime(text, '%Y-%m-%d %H:%M', Date::GREGORIAN)
  end

  def datetime(epoch, minutes)
    (epoch + Rational(minutes, 1440)).strftime('%Y-%m-%d %H:%M')
  end

  def hour_datetime(epoch, hours)
    datetime(epoch, hours * 60)
  end

  def date(epoch, day)
    (epoch + day).strftime('%Y-%m-%d')
  end

  def read_all
    lines = File.readlines('input/params.txt', chomp: true)
    params = {epoch: minute(lines.shift.delete_prefix('epoch ')), stations: []}
    while lines.first.start_with?('station ')
      _, code, name = lines.shift.split(' ', 3)
      params[:stations] << {code: code, name: name}
    end
    params[:reference] = lines.shift.split[1]
    params[:flat_run] = lines.shift.split[1].to_i
    spike = lines.shift.split.drop(1)
    params[:spike] = {window: spike[0].to_i, count: spike[1].to_i, factor: spike[2].to_f, minimum: spike[3].to_f}
    params[:rayleigh] = lines.shift.split[1].to_f
    params[:snr_min] = lines.shift.split[1].to_f
    params[:top_residuals] = lines.shift.split[1].to_i
    surge = lines.shift.split
    params[:surge] = {threshold: surge[1].to_f, hours: surge[2].to_i}
    prediction = lines.shift.split
    params[:start] = ((minute(prediction[1] + ' ' + prediction[2]) - params[:epoch]) * 24).to_i
    params[:hours] = prediction[3].to_i
    params[:grid] = lines.shift.split[1].to_i
    params[:min_range] = lines.shift.split[1].to_f
    params[:correlation_lag] = lines.shift.split[1].to_i
    plot = lines.shift.split
    params[:plot] = {code: plot[1], hours: plot[2].to_i, top: plot[3].to_i, bottom: plot[4].to_i, step: plot[5].to_i}
    constituents = File.readlines('input/constituents.txt', chomp: true).drop(1).map do |line|
      name, speed = line.split
      {name: name, speed: speed.to_f}
    end
    observations = params[:stations].to_h { |station| [station[:code], []] }
    File.readlines('input/observations.csv', chomp: true).drop(1).each do |line|
      code, time, value = line.split(',')
      observations[code] << {time: ((minute(time) - params[:epoch]) * 24).to_i,
                            value: value == 'NA' ? nil : value.to_f,
                            milli: value == 'NA' ? nil : value.delete('.').to_i}
    end
    [params, constituents, observations]
  end
end
