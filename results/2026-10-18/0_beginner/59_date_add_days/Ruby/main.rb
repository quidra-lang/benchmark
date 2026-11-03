def format_date(year, month, day)
  format('%04d-%02d-%02d', year, month, day)
end

cases = [[1999, 12, 25, 10], [2000, 2, 27, 3], [2021, 2, 20, 14], [2023, 11, 15, 120], [2026, 10, 17, 1500]]
cases.each do |year, month, day, added|
  original = format_date(year, month, day)
  added.times do
    leap = (year % 400).zero? || ((year % 4).zero? && !(year % 100).zero?)
    lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    day += 1
    if day > lengths[month - 1]
      day = 1
      month += 1
      if month > 12
        month = 1
        year += 1
      end
    end
  end
  puts "#{original} + #{added} days = #{format_date(year, month, day)}"
end
