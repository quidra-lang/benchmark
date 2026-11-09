
LAST_DAY = 36_524

class CommandError < StandardError; end

def parse_money(text)
  whole, fraction = text.split('.').map(&:to_i)
  whole * 100 + fraction
end

def money(value)
  magnitude = value.abs
  format('%s%d.%02d', value.negative? ? '-' : '', magnitude / 100, magnitude % 100)
end

def trunc(numerator, denominator)
  numerator.negative? ? -(numerator.abs / denominator) : numerator / denominator
end

def leap?(year)
  (year % 4).zero? && (!(year % 100).zero? || (year % 400).zero?)
end

def year_length(year) = leap?(year) ? 366 : 365

def month_length(year, month)
  return 29 if month == 2 && leap?(year)

  [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
end

def day_number(year, month, day)
  number = day - 1
  (2000...year).each { |y| number += year_length(y) }
  (1...month).each { |m| number += month_length(year, m) }
  number
end

def calendar(number)
  year = 2000
  month = 1
  while number >= year_length(year)
    number -= year_length(year)
    year += 1
  end
  while number >= month_length(year, month)
    number -= month_length(year, month)
    month += 1
  end
  [year, month, number + 1]
end

def date_text(number) = format('%04d-%02d-%02d', *calendar(number))

def parse_date(text)
  year, month, day = text.split('-').map(&:to_i)
  unless (2000..2099).cover?(year) && (1..12).cover?(month) && day >= 1 && day <= month_length(year, month)
    raise CommandError, "invalid date #{text}"
  end
  day_number(year, month, day)
end

def date_range(first, last)
  start_day = parse_date(first)
  end_day = parse_date(last)
  raise CommandError, "invalid range #{first} #{last}" if start_day > end_day

  start_day..end_day
end

def months_after(number, offset)
  year, month, day = calendar(number)
  total = month - 1 + offset
  year += total / 12
  month = total % 12 + 1
  day_number(year, month, [day, month_length(year, month)].min)
end

class Account
  attr_reader :code, :type, :name
  attr_accessor :active

  def initialize(code, type, name)
    @code, @type, @name = code, type, name
    @active = true
  end

  def type_class = type == 'CONTRA_ASSET' ? 'ASSET' : type
  def sign = %w[ASSET EXPENSE].include?(type) ? 1 : -1
  def temporary? = %w[REVENUE EXPENSE].include?(type)
end

Totals = Data.define(:debit, :credit) do
  def difference = debit - credit
  def +(other) = Totals.new(debit + other.debit, credit + other.credit)
  def add(is_debit, amount)
    is_debit ? Totals.new(debit + amount, credit) : Totals.new(debit, credit + amount)
  end
end

ZERO_TOTALS = Totals.new(0, 0)

Line = Data.define(:debit, :account, :amount, :partner) do
  def difference = debit ? amount : -amount
  def side = debit ? 'DR' : 'CR'
end

class Lines
  attr_reader :items, :amount, :accounts

  def initialize(items)
    @items = items.freeze
    @accounts = Hash.new(ZERO_TOTALS)
    @amount = 0
    items.each do |line|
      @accounts[line.account] = @accounts[line.account].add(line.debit, line.amount)
      @amount += line.amount if line.debit
    end
    @accounts.freeze
    freeze
  end
end

DraftLine = Data.define(:debit, :code, :amount, :partner)
Draft = Struct.new(:kind, :key, :date, :memo, :lines) do
  def totals = lines.reduce(ZERO_TOTALS) { |sum, line| sum.add(line.debit, line.amount) }
end

class Entry
  attr_reader :id, :day, :category, :memo, :lines, :sequence
  attr_accessor :reverses, :reversed_by

  def initialize(id, day, category, memo, lines, sequence)
    @id, @day, @category, @memo, @lines, @sequence = id, day, category, memo, lines, sequence
    @reverses = @reversed_by = nil
  end
end

class Template
  attr_reader :memo, :lines
  attr_accessor :uses

  def initialize(memo, lines)
    @memo, @lines, @uses = memo, lines, 0
  end
end

CloseRecord = Data.define(:day, :entry)
OpenItem = Struct.new(:entry, :original, :remaining)

class Settlement
  attr_reader :items
  attr_accessor :unapplied

  def initialize
    @items = []
    @unapplied = 0
  end
end

class Book
  def initialize(output = $stdout)
    @accounts = {}
    @entries = []
    @entry_ids = {}
    @templates = {}
    @closes = []
    @draft = nil
    @close_count = @depreciation_count = @interest_count = @writeoff_count = 0
    @output = output
  end

  def emit(text) = @output.puts(text)

  def account(code)
    @accounts.fetch(code) { raise CommandError, "unknown account #{code}" }
  end

  def require_type(code, type)
    found = account(code)
    raise CommandError, "wrong type #{code} #{type}" unless found.type == type

    found
  end

  def active(*selected)
    selected.each { |found| raise CommandError, "inactive account #{found.code}" unless found.active }
  end

  def active_lines(lines)
    lines.items.each { |line| active(line.account) }
  end

  def check_open(day)
    raise CommandError, "period closed #{date_text(day)}" if !@closes.empty? && day <= @closes.last.day
  end

  def closed_text = @closes.empty? ? 'none' : date_text(@closes.last.day)
  def ordered_accounts = @accounts.keys.sort.map { |code| @accounts[code] }
  def ordered_entries = @entries.sort_by { |entry| [entry.day, entry.sequence] }

  def parent(code)
    (code.length - 1).downto(1) { |length| return code[0, length] if @accounts.key?(code[0, length]) }
    'none'
  end

  def top(code)
    (1...code.length).each { |length| return code[0, length] if @accounts.key?(code[0, length]) }
    code
  end

  def totals(first, last, operating: false)
    result = Hash.new(ZERO_TOTALS)
    @entries.each do |entry|
      next unless (first..last).cover?(entry.day)
      next if operating && %i[closing reopen].include?(entry.category)

      entry.lines.accounts.each { |found, amount| result[found] = result[found] + amount }
    end
    result
  end

  def account_totals(found, first, last)
    result = ZERO_TOTALS
    @entries.each { |entry| result += entry.lines.accounts[found] if (first..last).cover?(entry.day) }
    result
  end

  def balance(found, day) = found.sign * account_totals(found, 0, day).difference

  def daily_sum(found, first, last)
    changes = Array.new(last - first + 1, 0)
    running = 0
    @entries.each do |entry|
      next if entry.day > last

      value = found.sign * entry.lines.accounts[found].difference
      if entry.day < first
        running += value
      else
        changes[entry.day - first] += value
      end
    end
    sum = 0
    changes.each { |change| running += change; sum += running }
    sum
  end

  def post(id, day, category, memo, lines)
    entry = Entry.new(id, day, category, memo, lines, @entries.length + 1)
    @entries << entry
    @entry_ids[id] = entry
    entry
  end

  def reverse(original, day, category, memo)
    lines = Lines.new(original.lines.items.map { |line| Line.new(!line.debit, line.account, line.amount, line.partner) })
    entry = post("#{original.id}-R", day, category, memo, lines)
    original.reversed_by = entry
    entry.reverses = original
    entry
  end

  def settlements(found, day)
    result = {}
    ordered_entries.each do |entry|
      next if entry.day > day

      entry.lines.items.each do |line|
        next unless line.account.equal?(found) && !line.partner.nil?

        settled = result[line.partner] ||= Settlement.new
        value = found.sign * line.difference
        if value.positive?
          applied = [value, settled.unapplied].min
          settled.unapplied -= applied
          settled.items << OpenItem.new(entry, value, value - applied) if value > applied
        else
          payment = -value
          while payment.positive? && !settled.items.empty?
            item = settled.items.first
            applied = [payment, item.remaining].min
            payment -= applied
            item.remaining -= applied
            settled.items.shift if item.remaining.zero?
          end
          settled.unapplied += payment
        end
      end
    end
    result
  end

  def post_draft
    raise CommandError, 'no open entry' unless @draft

    block = @draft
    @draft = nil
    day = 0
    if block.kind == :journal
      raise CommandError, "duplicate entry #{block.key}" if @entry_ids.key?(block.key)

      day = parse_date(block.date)
      check_open(day)
    elsif @templates.key?(block.key)
      raise CommandError, "duplicate template #{block.key}"
    end
    raise CommandError, "too few lines #{block.key}" if block.lines.length < 2

    items = block.lines.map do |line|
      found = account(line.code)
      active(found) if block.kind == :journal
      raise CommandError, "zero amount #{line.code}" if line.amount.zero?

      Line.new(line.debit, found, line.amount, line.partner)
    end
    amount = block.totals
    unless amount.debit == amount.credit
      raise CommandError, "unbalanced #{block.key} debit #{money(amount.debit)} credit #{money(amount.credit)}"
    end
    lines = Lines.new(items)
    if block.kind == :journal
      post(block.key, day, :journal, block.memo, lines)
      emit("POST #{block.key} #{date_text(day)} lines #{items.length} amount #{money(lines.amount)}")
    else
      @templates[block.key] = Template.new(block.memo, lines)
      emit("TEMPLATE #{block.key} lines #{items.length} amount #{money(lines.amount)}")
    end
  end

  def section(heading, types, sign, amounts, earnings: nil)
    groups = Hash.new { |hash, key| hash[key] = [] }
    total = earnings || 0
    ordered_accounts.each do |found|
      next unless types.include?(found.type)

      value = sign * amounts[found].difference
      groups[top(found.code)] << [found, value]
      total += value
    end
    emit("  #{heading} #{money(total)}")
    groups.keys.sort.each do |root|
      group = groups[root]
      next unless group.any? { |_, amount| !amount.zero? }

      emit("    #{root} #{@accounts[root].name} #{money(group.sum { |_, amount| amount })}")
      group.each { |found, amount| emit("      #{found.code} #{found.name} #{money(amount)}") unless amount.zero? }
    end
    emit("    current earnings #{money(earnings)}") unless earnings.nil?
    total
  end

  def aging_row(partner, values)
    balance = values[0, 4].sum - values[4]
    emit("  #{partner} 0-30 #{money(values[0])} 31-60 #{money(values[1])} 61-90 #{money(values[2])} " \
         "91+ #{money(values[3])} unapplied #{money(values[4])} balance #{money(balance)}")
  end

  def execute(words)
    case words[0]
    when 'ACCOUNT'
      code, type, name = words[1, 3]
      raise CommandError, "duplicate account #{code}" if @accounts.key?(code)

      type_class = type == 'CONTRA_ASSET' ? 'ASSET' : type
      ordered_accounts.each do |other|
        if (code.start_with?(other.code) || other.code.start_with?(code)) && type_class != other.type_class
          raise CommandError, "class mismatch #{code} #{other.code}"
        end
      end
      @accounts[code] = Account.new(code, type, name)
      emit("ACCOUNT #{code} #{type} #{name} parent #{parent(code)}")
    when 'DEACTIVATE'
      found = account(words[1])
      raise CommandError, "already inactive #{found.code}" unless found.active

      value = balance(found, LAST_DAY)
      raise CommandError, "nonzero balance #{found.code} #{money(value)}" unless value.zero?

      found.active = false
      emit("DEACTIVATE #{found.code} #{found.name}")
    when 'JOURNAL', 'TEMPLATE'
      emit("DISCARD #{@draft.key} lines #{@draft.lines.length}") if @draft
      journal = words[0] == 'JOURNAL'
      @draft = Draft.new(journal ? :journal : :template, words[1], journal ? words[2] : nil, words[journal ? 3 : 2], [])
    when 'DR', 'CR'
      raise CommandError, 'no open entry' unless @draft

      @draft.lines << DraftLine.new(words[0] == 'DR', words[1], parse_money(words[2]), words[3])
    when 'POST'
      post_draft
    when 'DRAFT'
      raise CommandError, 'no open entry' unless @draft

      amount = @draft.totals
      emit("DRAFT #{@draft.kind} #{@draft.key} lines #{@draft.lines.length} debit #{money(amount.debit)} " \
           "credit #{money(amount.credit)} difference #{money(amount.difference)}")
    when 'REVERSE'
      original = @entry_ids.fetch(words[1]) { raise CommandError, "unknown entry #{words[1]}" }
      raise CommandError, "cannot reverse #{original.id}" if %i[reversal closing reopen].include?(original.category)
      raise CommandError, "already reversed #{original.id}" if original.reversed_by

      day = parse_date(words[2])
      raise CommandError, "reverse before entry #{original.id} #{date_text(original.day)}" if day < original.day

      check_open(day)
      active_lines(original.lines)
      entry = reverse(original, day, :reversal, original.memo)
      emit("REVERSE #{original.id} entry #{entry.id} #{date_text(day)} amount #{money(entry.lines.amount)}")
    when 'RECUR'
      model = @templates.fetch(words[1]) { raise CommandError, "unknown template #{words[1]}" }
      day = parse_date(words[2])
      count = words[3].to_i
      raise CommandError, 'invalid count' if count.zero?

      check_open(day)
      active_lines(model.lines)
      emit("RECUR #{words[1]} count #{count}")
      count.times do |offset|
        model.uses += 1
        entry = post("#{words[1]}-#{model.uses}", months_after(day, offset), :recurring, model.memo, model.lines)
        emit("  POST #{entry.id} #{date_text(entry.day)} lines #{entry.lines.items.length} amount #{money(entry.lines.amount)}")
      end
    when 'DEPRECIATE'
      day = parse_date(words[1])
      check_open(day)
      asset = require_type(words[2], 'ASSET')
      contra = require_type(words[3], 'CONTRA_ASSET')
      expense = require_type(words[4], 'EXPENSE')
      active(contra, expense)
      cost = balance(asset, day)
      accumulated = balance(contra, day)
      amount = cost.positive? ? [cost / words[5].to_i, cost - accumulated].min : 0
      raise CommandError, "nothing to depreciate #{asset.code}" unless amount.positive?

      lines = Lines.new([Line.new(true, expense, amount, nil), Line.new(false, contra, amount, nil)])
      @depreciation_count += 1
      entry = post("DEP-#{@depreciation_count}", day, :depreciation, 'depreciation', lines)
      emit("DEPRECIATE #{asset.code} entry #{entry.id} #{date_text(day)} amount #{money(amount)} " \
           "accumulated #{money(accumulated + amount)} book #{money(cost - accumulated - amount)}")
    when 'INTEREST'
      found = account(words[1])
      raise CommandError, "not interest bearing #{found.code}" unless %w[ASSET LIABILITY].include?(found.type)

      offset = require_type(words[2], found.type == 'ASSET' ? 'REVENUE' : 'EXPENSE')
      range = date_range(words[3], words[4])
      check_open(range.end)
      active(found, offset)
      sum = daily_sum(found, range.begin, range.end)
      amount = trunc(sum * words[5].to_i, 3_650_000)
      raise CommandError, "no interest #{found.code}" unless amount.positive?

      debit, credit = found.type == 'ASSET' ? [found, offset] : [offset, found]
      lines = Lines.new([Line.new(true, debit, amount, nil), Line.new(false, credit, amount, nil)])
      @interest_count += 1
      entry = post("INT-#{@interest_count}", range.end, :interest, 'interest', lines)
      days = range.end - range.begin + 1
      emit("INTEREST #{found.code} entry #{entry.id} #{date_text(range.end)} days #{days} average #{money(trunc(sum, days))} amount #{money(amount)}")
    when 'WRITEOFF'
      day = parse_date(words[1])
      check_open(day)
      found = require_type(words[2], 'ASSET')
      expense = require_type(words[3], 'EXPENSE')
      active(found, expense)
      age = words[4].to_i
      settled = settlements(found, day)
      targets = {}
      settled.keys.sort.each do |partner|
        amount = settled[partner].items.sum { |item| day - item.entry.day > age ? item.remaining : 0 }
        targets[partner] = amount if amount.positive?
      end
      total = targets.values.sum
      raise CommandError, "nothing to write off #{found.code}" if total.zero?

      items = [Line.new(true, expense, total, nil)]
      targets.each { |partner, amount| items << Line.new(false, found, amount, partner) }
      @writeoff_count += 1
      entry = post("WO-#{@writeoff_count}", day, :writeoff, 'writeoff', Lines.new(items))
      emit("WRITEOFF #{found.code} entry #{entry.id} #{date_text(day)} partners #{targets.length} amount #{money(total)}")
      targets.each { |partner, amount| emit("  #{partner} #{money(amount)}") }
    when 'CLOSE'
      day = parse_date(words[1])
      check_open(day)
      equity = require_type(words[2], 'EQUITY')
      active(equity)
      amounts = totals(0, day)
      targets = ordered_accounts.select { |found| found.temporary? && !amounts[found].difference.zero? }
      targets.each { |found| active(found) }
      income = 0
      items = targets.map do |found|
        value = amounts[found].difference
        income -= value
        Line.new(value.negative?, found, value.abs, nil)
      end
      items << Line.new(income.negative?, equity, income.abs, nil) unless income.zero?
      @close_count += 1
      entry = items.empty? ? nil : post("CLOSE-#{@close_count}", day, :closing, 'closing', Lines.new(items))
      @closes << CloseRecord.new(day, entry)
      if entry
        emit("CLOSE #{date_text(day)} entry #{entry.id} lines #{items.length} net income #{money(income)}")
      else
        emit("CLOSE #{date_text(day)} no entry")
      end
    when 'REOPEN'
      raise CommandError, 'nothing to reopen' if @closes.empty?

      record = @closes.last
      detail = 'no entry'
      if record.entry
        active_lines(record.entry.lines)
        detail = "entry #{reverse(record.entry, record.day, :reopen, 'reopen').id}"
      end
      @closes.pop
      emit("REOPEN #{date_text(record.day)} #{detail} closed #{closed_text}")
    when 'LEDGER'
      found = account(words[1])
      range = date_range(words[2], words[3])
      running = balance(found, range.begin - 1)
      amounts = ZERO_TOTALS
      emit("LEDGER #{found.code} #{found.name} #{words[2]} #{words[3]}")
      emit("  opening #{money(running)}")
      ordered_entries.each do |entry|
        next unless range.cover?(entry.day)

        entry.lines.items.each do |line|
          next unless line.account.equal?(found)

          amounts = amounts.add(line.debit, line.amount)
          running += found.sign * line.difference
          emit("  #{date_text(entry.day)} #{entry.id} #{line.side} #{money(line.amount)} balance #{money(running)} #{entry.memo}")
        end
      end
      days = range.end - range.begin + 1
      emit("  ending #{money(running)} debits #{money(amounts.debit)} credits #{money(amounts.credit)} days #{days} " \
           "average #{money(trunc(daily_sum(found, range.begin, range.end), days))}")
    when 'ACTIVITY'
      found = account(words[1])
      year = words[2].to_i
      amounts = ZERO_TOTALS
      emit("ACTIVITY #{found.code} #{found.name} #{year}")
      (1..12).each do |month|
        first = day_number(year, month, 1)
        last = day_number(year, month, month_length(year, month))
        current = account_totals(found, first, last)
        amounts += current
        emit("  #{format('%04d-%02d', year, month)} debit #{money(current.debit)} credit #{money(current.credit)} balance #{money(balance(found, last))}")
      end
      emit("  total debit #{money(amounts.debit)} credit #{money(amounts.credit)}")
    when 'TRIAL'
      day = parse_date(words[1])
      amounts = totals(0, day)
      debit = credit = 0
      emit("TRIAL #{words[1]}")
      ordered_accounts.each do |found|
        value = amounts[found].difference
        next if value.zero?

        if value.positive? then debit += value else credit -= value end
        emit("  #{found.code} #{found.name} #{value.positive? ? 'debit' : 'credit'} #{money(value.abs)}")
      end
      emit("  total debit #{money(debit)} credit #{money(credit)}")
    when 'INCOME'
      range = date_range(words[1], words[2])
      amounts = totals(range.begin, range.end, operating: true)
      emit("INCOME #{words[1]} #{words[2]}")
      revenue = section('REVENUE', ['REVENUE'], -1, amounts)
      expense = section('EXPENSE', ['EXPENSE'], 1, amounts)
      emit("  NET INCOME #{money(revenue - expense)}")
    when 'BALANCE'
      day = parse_date(words[1])
      amounts = totals(0, day)
      earnings = -ordered_accounts.sum { |found| found.temporary? ? amounts[found].difference : 0 }
      emit("BALANCE #{words[1]}")
      assets = section('ASSETS', %w[ASSET CONTRA_ASSET], 1, amounts)
      liabilities = section('LIABILITIES', ['LIABILITY'], -1, amounts)
      equity = section('EQUITY', ['EQUITY'], -1, amounts, earnings: earnings)
      emit(assets == liabilities + equity ? '  check ok' : "  check mismatch #{money(assets - liabilities - equity)}")
    when 'ROLLUP'
      day = parse_date(words[2])
      targets = ordered_accounts.select { |found| found.code.start_with?(words[1]) }
      emit("ROLLUP #{words[1]} #{words[2]}")
      if targets.empty?
        emit('  (none)')
        return
      end
      amounts = totals(0, day)
      postings = ZERO_TOTALS
      targets.each do |found|
        depth = targets.count { |other| !other.equal?(found) && found.code.start_with?(other.code) }
        subtotal = targets.sum { |other| other.code.start_with?(found.code) ? amounts[other].difference : 0 }
        own = amounts[found]
        emit("#{' ' * (2 * (1 + depth))}#{found.code} #{found.name} own #{money(found.sign * own.difference)} total #{money(found.sign * subtotal)}")
        postings += own
      end
      emit("  postings debit #{money(postings.debit)} credit #{money(postings.credit)}")
    when 'AGING', 'ITEMS'
      found = account(words[1])
      aging = words[0] == 'AGING'
      day = parse_date(words[aging ? 2 : 3])
      settled = settlements(found, day)
      if aging
        emit("AGING #{found.code} #{found.name} #{words[2]}")
        columns = Array.new(5, 0)
        settled.keys.sort.each do |partner|
          group = settled[partner]
          next if group.items.empty? && group.unapplied.zero?

          values = [0, 0, 0, 0, group.unapplied]
          group.items.each do |item|
            age = day - item.entry.day
            bucket = if age <= 30 then 0 elsif age <= 60 then 1 elsif age <= 90 then 2 else 3 end
            values[bucket] += item.remaining
          end
          aging_row(partner, values)
          5.times { |i| columns[i] += values[i] }
        end
        aging_row('total', columns)
      else
        group = settled[words[2]] || Settlement.new
        emit("ITEMS #{found.code} #{found.name} #{words[2]} #{words[3]}")
        remaining = 0
        group.items.each do |item|
          emit("  #{date_text(item.entry.day)} #{item.entry.id} amount #{money(item.original)} open #{money(item.remaining)} age #{day - item.entry.day}")
          remaining += item.remaining
        end
        emit("  unapplied #{money(group.unapplied)} balance #{money(remaining - group.unapplied)}")
      end
    when 'ENTRY'
      entry = @entry_ids.fetch(words[1]) { raise CommandError, "unknown entry #{words[1]}" }
      emit("ENTRY #{entry.id} #{date_text(entry.day)} #{entry.category} #{entry.memo}")
      entry.lines.items.each do |line|
        partner = line.partner.nil? ? '' : " #{line.partner}"
        emit("  #{line.side} #{line.account.code} #{line.account.name} #{money(line.amount)}#{partner}")
      end
      emit("  total #{money(entry.lines.amount)}")
      emit("  reverses #{entry.reverses.id}") if entry.reverses
      emit("  reversed by #{entry.reversed_by.id}") if entry.reversed_by
    when 'DAYBOOK'
      range = date_range(words[1], words[2])
      total = count = 0
      emit("DAYBOOK #{words[1]} #{words[2]}")
      ordered_entries.each do |entry|
        next unless range.cover?(entry.day)

        total += entry.lines.amount
        count += 1
        emit("  #{date_text(entry.day)} #{entry.id} #{entry.category} #{money(entry.lines.amount)} #{entry.memo}")
      end
      emit("  total entries #{count} amount #{money(total)}")
    when 'ACCOUNTS'
      amounts = totals(0, LAST_DAY)
      emit('ACCOUNTS')
      ordered_accounts.each do |found|
        emit("  #{found.code} #{found.type} #{found.name} parent #{parent(found.code)} " \
             "balance #{money(found.sign * amounts[found].difference)} #{found.active ? 'active' : 'inactive'}")
      end
      emit('  (none)') if @accounts.empty?
    when 'TEMPLATES'
      emit('TEMPLATES')
      @templates.keys.sort.each do |name|
        model = @templates[name]
        emit("  #{name} #{model.memo} lines #{model.lines.items.length} amount #{money(model.lines.amount)} used #{model.uses}")
      end
      emit('  (none)') if @templates.empty?
    when 'STATUS'
      inactive = @accounts.values.count { |found| !found.active }
      emit("STATUS accounts #{@accounts.length} inactive #{inactive} entries #{@entries.length} templates #{@templates.length} " \
           "closed #{closed_text} open #{@draft ? @draft.key : 'none'}")
    end
  end
end

book = Book.new
$stdin.gets.to_i.times do
  begin
    book.execute($stdin.gets.split)
  rescue CommandError => error
    book.emit("ERROR #{error.message}")
  end
end
