# frozen_string_literal: true

module Report
  def self.real(value)
    format('%.4f', value).sub(/\A-0\.0000\z/, '0.0000')
  end

  def self.key(value)
    real(value).delete('.').to_i
  end

  def self.amount(cents)
    absolute = cents.abs
    "#{cents.negative? ? '-' : ''}#{absolute / 100}.#{format('%02d', absolute % 100)}"
  end

  def self.write(name, lines)
    File.binwrite("output/#{name}", lines.empty? ? '' : lines.join("\n") + "\n")
  end
end
