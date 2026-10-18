require "set"

class Invalid < StandardError
end

class Library
  RULES = {
    "STUDENT" => { limit: 3, period: 14, fine: 25, cap: 1000, reservations: 2, fee: 50 },
    "STAFF" => { limit: 10, period: 28, fine: 10, cap: 2000, reservations: 5, fee: 100 }
  }.freeze

  def initialize
    @day = 1
    @closed = Set.new
    @titles = {}
    @members = {}
    @counts = { borrowed: 0, returned: 0, renewed: 0, lost: 0, FINE: 0, FEE: 0, PRICE: 0, paid: 0, waived: 0 }
  end

  def fail_with(reason)
    raise Invalid, reason
  end

  def amount(text)
    whole, fraction = text.split(".")
    whole.to_i * 100 + fraction.to_i
  end

  def money(value)
    format("%d.%02d", value.div(100), value % 100)
  end

  def isbn(text)
    raw = text.delete("-")
    if raw.match?(/\A[0-9]{9}[0-9X]\z/)
      sum = raw.chars.each_with_index.sum { |c, i| (10 - i) * (c == "X" ? 10 : c.to_i) }
      fail_with("invalid isbn") unless (sum % 11).zero?
      prefix = "978" + raw[0, 9]
      checksum = prefix.chars.each_with_index.sum { |c, i| c.to_i * (i.even? ? 1 : 3) }
      return prefix + ((10 - checksum % 10) % 10).to_s
    end
    if raw.match?(/\A(?:978|979)[0-9]{10}\z/)
      sum = raw.chars.each_with_index.sum { |c, i| c.to_i * (i.even? ? 1 : 3) }
      return raw if (sum % 10).zero?
    end
    fail_with("invalid isbn")
  end

  def member(id)
    @members[id] || fail_with("unknown member")
  end

  def title(token)
    @titles[isbn(token)] || fail_with("unknown book")
  end

  def common(id, token)
    person = member(id)
    [person, title(token)]
  end

  def all_copies
    @titles.values.flat_map { |book| book[:copies] }
  end

  def holdings(book)
    book[:copies].count { |copy| %w[AVAILABLE LOANED HOLD].include?(copy[:state]) }
  end

  def balance(person)
    person[:items].sum { |item| item[:unpaid] }
  end

  def reservations(person)
    person[:holds].length + @titles.values.count { |book| book[:queue].include?(person[:id]) }
  end

  def open_day(day)
    day += 1 while @closed.include?(day)
    day
  end

  def late(copy)
    days = [0, @day - copy[:due]].max
    rule = RULES[@members[copy[:member]][:type]]
    [days, [days * rule[:fine], rule[:cap]].min]
  end

  def charge(person, kind, book, value)
    return if value.zero?
    person[:items] << {
      no: person[:items].length + 1, day: @day, kind: kind, isbn: book[:isbn], amount: value, unpaid: value
    }
    @counts[kind.to_sym] += value
  end

  def release(book, copy)
    if book[:queue].empty?
      copy[:state] = "AVAILABLE"
      copy[:member] = nil
      return []
    end
    id = book[:queue].shift
    copy[:state] = "HOLD"
    copy[:member] = id
    copy[:expiry] = open_day(@day + 3)
    @members[id][:holds][book[:isbn]] = copy
    ["HOLD #{book[:isbn]} copy #{copy[:no]} #{id} until #{copy[:expiry]}"]
  end

  def end_loan(book, copy, result)
    person = @members[copy[:member]]
    days, fine = late(copy)
    person[:loans].delete(book[:isbn])
    charge(person, "FINE", book, fine)
    person[:history] << "#{result} #{book[:isbn]} copy #{copy[:no]} from #{copy[:loan_day]} to #{@day} late #{days} fine #{money(fine)}"
    [days, fine]
  end

  def loss(book, copy, heading)
    person = @members[copy[:member]]
    days, fine = end_loan(book, copy, "LOST")
    person[:history][-1] += " price #{money(book[:price])}"
    charge(person, "PRICE", book, book[:price])
    copy[:state] = "LOST"
    copy[:member] = nil
    @counts[:lost] += 1
    output = ["#{heading} #{person[:id]} #{book[:isbn]} copy #{copy[:no]} late #{days} fine #{money(fine)} " +
              "price #{money(book[:price])} balance #{money(balance(person))}"]
    if holdings(book).zero? && !book[:queue].empty?
      output.concat(book[:queue].map { |id| "DROPPED #{book[:isbn]} #{id}" })
      book[:queue] = []
    end
    output
  end

  def renewal_reason(book, copy)
    return "loan overdue" if copy[:due] < @day
    return "renewal limit" if copy[:renewals] == 2
    book[:queue].empty? ? nil : "title reserved"
  end

  def renew(person, book, copy)
    copy[:due] = open_day(@day + RULES[person[:type]][:period])
    copy[:renewals] += 1
    @counts[:renewed] += 1
    "RENEW #{person[:id]} #{book[:isbn]} copy #{copy[:no]} due #{copy[:due]} renewals #{copy[:renewals]}"
  end

  def advance(day)
    fail_with("invalid day") if day <= @day
    output = ["DAY #{day}"]
    while @day < day
      @day += 1
      losses = all_copies.select { |copy| copy[:state] == "LOANED" && copy[:due] + 365 <= @day }
                         .sort_by { |copy| [copy[:member], copy[:isbn]] }
      losses.each { |copy| output.concat(loss(@titles[copy[:isbn]], copy, "AUTOLOST")) }
      expired = all_copies.select { |copy| copy[:state] == "HOLD" && copy[:expiry] < @day }
                          .sort_by { |copy| [copy[:isbn], copy[:no]] }
      expired.each do |copy|
        book = @titles[copy[:isbn]]
        person = @members[copy[:member]]
        fee = RULES[person[:type]][:fee]
        charge(person, "FEE", book, fee)
        person[:holds].delete(copy[:isbn])
        output << "EXPIRED #{copy[:isbn]} copy #{copy[:no]} #{person[:id]} fee #{money(fee)}"
        output.concat(release(book, copy))
      end
    end
    output
  end

  def command(line)
    name, *args = line.split(" ")
    return advance(args[0].to_i) if name == "DAY"
    if name == "CLOSED"
      day = args[0].to_i
      fail_with("invalid day") if day <= @day
      fail_with("already closed") if @closed.include?(day)
      @closed << day
      output = ["CLOSED #{day}"]
      all_copies.sort_by { |copy| [copy[:isbn], copy[:no]] }.each do |copy|
        if copy[:state] == "LOANED" && copy[:due] == day
          copy[:due] = open_day(day)
          output << "MOVED #{copy[:isbn]} copy #{copy[:no]} #{copy[:member]} due #{copy[:due]}"
        elsif copy[:state] == "HOLD" && copy[:expiry] == day
          copy[:expiry] = open_day(day)
          output << "MOVED #{copy[:isbn]} copy #{copy[:no]} #{copy[:member]} until #{copy[:expiry]}"
        end
      end
      return output
    end
    if name == "ADDBOOK"
      id = isbn(args[0])
      book_name = args.drop(3).join(" ")
      book = @titles[id]
      fail_with("title mismatch") if book && book[:name] != book_name
      unless book
        book = { isbn: id, name: book_name, price: amount(args[2]), copies: [], queue: [], borrowed: 0 }
        @titles[id] = book
      end
      book[:price] = amount(args[2])
      added = Array.new(args[1].to_i) do
        copy = {
          isbn: id, no: book[:copies].length + 1, state: "AVAILABLE",
          member: nil, loan_day: 0, due: 0, renewals: 0, expiry: 0
        }
        book[:copies] << copy
        copy
      end
      output = ["ADDBOOK #{id} added #{added.length} total #{holdings(book)}"]
      added.each { |copy| output.concat(release(book, copy)) }
      return output
    end
    if name == "ADDMEMBER"
      fail_with("duplicate member") if @members.key?(args[0])
      fail_with("unknown type") unless RULES.key?(args[1])
      @members[args[0]] = {
        id: args[0], type: args[1], name: args.drop(2).join(" "),
        loans: {}, holds: {}, items: [], history: []
      }
      return ["ADDMEMBER #{args[0]} #{args[1]} loans #{RULES[args[1]][:limit]} days #{RULES[args[1]][:period]}"]
    end
    if name == "WITHDRAW"
      book = title(args[0])
      number = args[1].to_i
      fail_with("unknown copy") unless number.between?(1, book[:copies].length)
      copy = book[:copies][number - 1]
      fail_with("copy not available") unless copy[:state] == "AVAILABLE"
      copy[:state] = "WITHDRAWN"
      return ["WITHDRAW #{book[:isbn]} copy #{copy[:no]} total #{holdings(book)}"]
    end
    return circulate(name, args) if %w[BORROW RETURN RENEW RESERVE CANCEL LOST].include?(name)
    if name == "RENEWALL"
      person = member(args[0])
      fail_with("no loans") if person[:loans].empty?
      fail_with("member blocked") if balance(person) > 500
      output = []
      renewed = 0
      skipped = 0
      person[:loans].values.sort_by { |copy| copy[:isbn] }.each do |copy|
        book = @titles[copy[:isbn]]
        reason = renewal_reason(book, copy)
        if reason
          output << "SKIP #{copy[:isbn]} #{reason}"
          skipped += 1
        else
          output << renew(person, book, copy)
          renewed += 1
        end
      end
      output << "RENEWALL #{person[:id]} renewed #{renewed} skipped #{skipped}"
      return output
    end
    return charges(name, args) if %w[PAYFINE WAIVE FINES].include?(name)
    inspect_library(name, args)
  end

  def circulate(name, args)
    person, book = common(args[0], args[1])
    loan = person[:loans][book[:isbn]]
    hold = person[:holds][book[:isbn]]
    rule = RULES[person[:type]]
    if name == "BORROW"
      fail_with("library closed") if @closed.include?(@day)
      fail_with("already borrowed") if loan
      fail_with("member blocked") if balance(person) > 500
      fail_with("overdue loans") if person[:loans].values.any? { |copy| copy[:due] < @day }
      fail_with("loan limit") if person[:loans].length >= rule[:limit]
      copy = hold || book[:copies].find { |item| item[:state] == "AVAILABLE" }
      unless copy
        fail_with(book[:copies].any? { |item| item[:state] == "HOLD" } ? "all copies on hold" : "no copy available")
      end
      person[:holds].delete(book[:isbn])
      copy.merge!(state: "LOANED", member: person[:id], loan_day: @day,
                  due: open_day(@day + rule[:period]), renewals: 0)
      person[:loans][book[:isbn]] = copy
      book[:borrowed] += 1
      @counts[:borrowed] += 1
      return ["BORROW #{person[:id]} #{book[:isbn]} copy #{copy[:no]} due #{copy[:due]}"]
    end
    if %w[RETURN LOST RENEW].include?(name)
      fail_with("not borrowed") unless loan
      return loss(book, loan, "LOST") if name == "LOST"
      if name == "RETURN"
        days, fine = end_loan(book, loan, "RETURNED")
        @counts[:returned] += 1
        output = ["RETURN #{person[:id]} #{book[:isbn]} copy #{loan[:no]} late #{days} fine #{money(fine)} balance #{money(balance(person))}"]
        return output + release(book, loan)
      end
      fail_with("member blocked") if balance(person) > 500
      reason = renewal_reason(book, loan)
      fail_with(reason) if reason
      return [renew(person, book, loan)]
    end
    queued = book[:queue].include?(person[:id])
    if name == "CANCEL"
      fail_with("not reserved") unless queued || hold
      if queued
        book[:queue].delete(person[:id])
        return ["CANCEL #{person[:id]} #{book[:isbn]} queue"]
      end
      person[:holds].delete(book[:isbn])
      return ["CANCEL #{person[:id]} #{book[:isbn]} hold copy #{hold[:no]}"] + release(book, hold)
    end
    fail_with("already borrowed") if loan
    fail_with("already reserved") if queued || hold
    fail_with("member blocked") if balance(person) > 500
    fail_with("reservation limit") if reservations(person) >= rule[:reservations]
    fail_with("no copies") if holdings(book).zero?
    fail_with("copy available") if book[:copies].any? { |copy| copy[:state] == "AVAILABLE" }
    book[:queue] << person[:id]
    days = book[:copies].select { |copy| copy[:state] == "LOANED" }.map { |copy| copy[:due] }.sort
    position = book[:queue].length
    ["RESERVE #{person[:id]} #{book[:isbn]} position #{position} estimate #{days[position - 1] || 'none'}"]
  end

  def charges(name, args)
    person = member(args[0])
    if name == "PAYFINE"
      fail_with("no fines") if balance(person).zero?
      remaining = amount(args[1])
      items = []
      person[:items].each do |item|
        applied = [remaining, item[:unpaid]].min
        if applied.positive?
          item[:unpaid] -= applied
          remaining -= applied
          items << "ITEM #{item[:no]} #{item[:kind]} paid #{money(applied)} remaining #{money(item[:unpaid])}"
        end
        break if remaining.zero?
      end
      paid = amount(args[1]) - remaining
      @counts[:paid] += paid
      return ["PAYFINE #{person[:id]} paid #{money(paid)} change #{money(remaining)} balance #{money(balance(person))}", *items]
    end
    if name == "WAIVE"
      no = args[1].to_i
      fail_with("unknown item") unless no.between?(1, person[:items].length)
      item = person[:items][no - 1]
      fail_with("item settled") if item[:unpaid].zero?
      value = item[:unpaid]
      item[:unpaid] = 0
      @counts[:waived] += value
      return ["WAIVE #{person[:id]} item #{no} #{item[:kind]} amount #{money(value)} balance #{money(balance(person))}"]
    end
    items = person[:items].select { |item| item[:unpaid].positive? }
    output = ["FINES #{person[:id]} items #{items.length} balance #{money(balance(person))}"]
    lines = items.map do |item|
      "#{item[:no]} day #{item[:day]} #{item[:kind]} #{item[:isbn]} amount #{money(item[:amount])} remaining #{money(item[:unpaid])}"
    end
    output + lines
  end

  def inspect_library(name, args)
    if name == "SEARCH"
      keyword = args.join(" ").downcase
      titles = @titles.values.select { |book| book[:name].downcase.include?(keyword) }
                      .sort_by { |book| [book[:name].downcase, book[:isbn]] }
      lines = titles.map do |book|
        available = book[:copies].count { |copy| copy[:state] == "AVAILABLE" }
        "#{book[:isbn]} #{available}/#{holdings(book)} #{book[:name]}"
      end
      return ["SEARCH #{titles.length}"] + lines
    end
    if name == "OVERDUE"
      copies = all_copies.select { |copy| copy[:state] == "LOANED" && copy[:due] < @day }
                         .sort_by { |copy| [copy[:due], copy[:member], copy[:isbn]] }
      lines = copies.map do |copy|
        days, fine = late(copy)
        "#{copy[:member]} #{copy[:isbn]} copy #{copy[:no]} due #{copy[:due]} late #{days} fine #{money(fine)}"
      end
      return ["OVERDUE #{copies.length}"] + lines
    end
    if name == "NOTICES"
      output = []
      @members.keys.sort.each do |id|
        person = @members[id]
        loans = person[:loans].values.sort_by { |copy| [copy[:due], copy[:isbn]] }
        loans.select { |copy| copy[:due] < @day }.each do |copy|
          output << "OVERDUE #{id} #{copy[:isbn]} due #{copy[:due]}"
        end
        loans.select { |copy| copy[:due].between?(@day, @day + 2) }.each do |copy|
          output << "DUESOON #{id} #{copy[:isbn]} due #{copy[:due]}"
        end
        person[:holds].values.sort_by { |copy| [copy[:expiry], copy[:isbn]] }.each do |copy|
          output << "PICKUP #{id} #{copy[:isbn]} until #{copy[:expiry]}"
        end
      end
      return ["NOTICES #{output.length}", *output]
    end
    if name == "HISTORY"
      person = member(args[0])
      return ["HISTORY #{person[:id]} #{person[:history].length}", *person[:history]]
    end
    if name == "MEMBER" || name == "MEMBERS"
      members = name == "MEMBER" ? [member(args[0])] : @members.values.sort_by { |person| person[:id] }
      output = name == "MEMBERS" ? ["MEMBERS #{members.length}"] : []
      members.each do |person|
        value = balance(person)
        state = value > 500 ? "BLOCKED" : "OK"
        if name == "MEMBERS"
          output << "#{person[:id]} #{person[:type]} loans #{person[:loans].length} reservations #{reservations(person)} balance #{money(value)} #{state}"
          next
        end
        rule = RULES[person[:type]]
        output << "MEMBER #{person[:id]} #{person[:type]} #{person[:name]}"
        output << "STATUS loans #{person[:loans].length}/#{rule[:limit]} reservations #{reservations(person)}/#{rule[:reservations]} balance #{money(value)} #{state}"
        person[:loans].values.sort_by { |copy| [copy[:due], copy[:isbn]] }.each do |copy|
          days, fine = late(copy)
          suffix = days.positive? ? " late #{days} fine #{money(fine)}" : ""
          output << "LOAN #{copy[:isbn]} copy #{copy[:no]} due #{copy[:due]} renewals #{copy[:renewals]}" + suffix
        end
        person[:holds].values.sort_by { |copy| [copy[:expiry], copy[:isbn]] }.each do |copy|
          output << "HOLD #{copy[:isbn]} copy #{copy[:no]} until #{copy[:expiry]}"
        end
        @titles.values.sort_by { |book| book[:isbn] }.each do |book|
          index = book[:queue].index(person[:id])
          output << "QUEUE #{book[:isbn]} position #{index + 1}" if index
        end
      end
      return output
    end
    if name == "BOOK"
      book = title(args[0])
      output = ["BOOK #{book[:isbn]} #{book[:name]}", "PRICE #{money(book[:price])} copies #{holdings(book)} borrowed #{book[:borrowed]}"]
      book[:copies].each do |copy|
        line = "COPY #{copy[:no]} #{copy[:state]}"
        line += " #{copy[:member]} due #{copy[:due]}" if copy[:state] == "LOANED"
        line += " #{copy[:member]} until #{copy[:expiry]}" if copy[:state] == "HOLD"
        output << line
      end
      output << "QUEUE #{book[:queue].length}" + (book[:queue].empty? ? "" : " " + book[:queue].join(" "))
      return output
    end
    if name == "INVENTORY"
      states = Hash.new(0)
      all_copies.each { |copy| states[copy[:state]] += 1 }
      total = states["AVAILABLE"] + states["LOANED"] + states["HOLD"]
      output = ["INVENTORY titles #{@titles.length} copies #{total} available #{states['AVAILABLE']} " +
                "loaned #{states['LOANED']} hold #{states['HOLD']} lost #{states['LOST']} withdrawn #{states['WITHDRAWN']}"]
      @titles.values.sort_by { |book| book[:isbn] }.each do |book|
        counts = book[:copies].map { |copy| copy[:state] }.tally
        output << "#{book[:isbn]} copies #{holdings(book)} available #{counts.fetch('AVAILABLE', 0)} " +
                  "loaned #{counts.fetch('LOANED', 0)} hold #{counts.fetch('HOLD', 0)} queue #{book[:queue].length}"
      end
      return output
    end
    c = @counts
    outstanding = @members.values.sum { |person| balance(person) }
    active = all_copies.count { |copy| copy[:state] == "LOANED" }
    output = [
      "STATS day #{@day} titles #{@titles.length} members #{@members.length} closed #{@closed.length}",
      "LOANS borrowed #{c[:borrowed]} returned #{c[:returned]} renewed #{c[:renewed]} lost #{c[:lost]} active #{active}",
      "MONEY fines #{money(c[:FINE])} fees #{money(c[:FEE])} charges #{money(c[:PRICE])} " +
        "paid #{money(c[:paid])} waived #{money(c[:waived])} outstanding #{money(outstanding)}"
    ]
    top = @titles.values.select { |book| book[:borrowed].positive? }.sort_by { |book| [-book[:borrowed], book[:isbn]] }.take(3)
    top.each_with_index { |book, i| output << "TOP #{i + 1} #{book[:isbn]} #{book[:borrowed]} #{book[:name]}" }
    output
  end
end

lines = STDIN.read.split("\n")
library = Library.new
output = []
lines[0].to_i.times do |i|
  begin
    output.concat(library.command(lines[i + 1]))
  rescue Invalid => error
    output << "ERROR " + error.message
  end
end
STDOUT.write(output.join("\n") + "\n")
