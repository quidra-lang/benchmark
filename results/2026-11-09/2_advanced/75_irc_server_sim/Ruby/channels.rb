require 'set'
require_relative 'masks'

class Member
  attr_reader :client
  attr_accessor :operator, :voice

  def initialize(client, operator)
    @client, @operator, @voice = client, operator, false
  end

  def status = @operator ? '@' : (@voice ? '+' : '')
  def display = status + @client.nickname
end

class Channel
  attr_reader :name, :created, :members, :bans, :flags
  attr_accessor :topic, :topic_setter, :topic_time, :key, :limit, :peak, :messages

  def initialize(name, time)
    @name, @created = name, time
    @members, @bans = [], []
    @topic = @key = ''
    @topic_setter = @topic_time = nil
    @flags = Set['n', 't']
    @limit = @peak = @messages = 0
  end

  def member(client)
    @members.find { |member| member.client.equal?(client) }
  end

  def add(client, operator = false)
    @members << Member.new(client, operator)
    client.channels << self
    @peak = [@peak, @members.length].max
  end

  def remove(client)
    @members.delete(member(client))
    client.channels.delete(self)
  end

  def name_list(viewer)
    inside = !member(viewer).nil?
    @members.select { |member| inside || !member.client.invisible }.map(&:display).join(' ')
  end

  def banned?(client)
    @bans.any? { |mask, _, _| Masks.matches?(mask, client.prefix) }
  end

  def can_speak?(client)
    membership = member(client)
    privileged = membership && (membership.operator || membership.voice)
    (membership || !@flags.include?('n')) && (!@flags.include?('m') || privileged) &&
      (privileged || !banned?(client))
  end

  def mode_display(include_key = true)
    mode = '+'
    'iklmnt'.each_char do |character|
      present = case character
                when 'k' then !@key.empty?
                when 'l' then @limit.positive?
                else @flags.include?(character)
                end
      mode += character if present
    end
    mode += ' ' + @key if include_key && !@key.empty?
    mode += " #{@limit}" if @limit.positive?
    mode
  end
end
