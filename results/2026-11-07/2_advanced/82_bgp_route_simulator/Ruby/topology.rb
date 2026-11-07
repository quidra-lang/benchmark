module Topology
  def self.address(text)
    text.split('.').reduce(0) { |value, octet| (value << 8) + octet.to_i }
  end

  def self.address_text(value)
    [24, 16, 8, 0].map { |shift| (value >> shift) & 255 }.join('.')
  end

  def self.prefix(text)
    address, length = text.split('/')
    [self.address(address), length.to_i].freeze
  end

  def self.prefix_text(prefix)
    "#{address_text(prefix[0])}/#{prefix[1]}"
  end

  def self.contains?(prefix, address)
    address >> (32 - prefix[1]) == prefix[0] >> (32 - prefix[1])
  end

  class Link
    attr_reader :number, :name, :first, :second, :relationship, :delay, :mrai
    attr_accessor :up, :down_count

    def initialize(number, name, first, second, relationship, delay, mrai)
      @number, @name, @first, @second = number, name, first, second
      @relationship, @delay, @mrai = relationship, delay, mrai
      @up, @down_count = true, 0
    end

    def other(owner) = owner == first ? second : first
    def role(owner) = relationship == 'P2P' ? 'peer' : (owner == first ? 'customer' : 'provider')
    def direction(owner) = { 'customer' => 'D', 'peer' => 'P', 'provider' => 'U' }.fetch(role(owner))
  end

  class Network
    attr_reader :router_ids, :ases, :links, :by_name, :at_as, :initial

    def initialize(router_ids, links, initial)
      @router_ids, @links, @initial = router_ids, links, initial
      @ases = router_ids.keys.sort
      @by_name = links.to_h { |link| [link.name, link] }
      @at_as = ases.to_h { |owner| [owner, []] }
      @between = Hash.new { |hash, key| hash[key] = [] }
      links.each do |link|
        at_as[link.first] << link
        at_as[link.second] << link
        @between[[link.first, link.second].sort] << link
      end
    end

    def connecting(first, second) = @between.fetch([first, second].sort)
  end

  def self.read
    router_ids, links, initial = {}, [], []
    File.foreach('input/topology.txt', chomp: true) do |line|
      fields = line.split(' ')
      case fields[0]
      when 'AS'
        router_ids[fields[1].to_i] = address(fields[2])
      when 'LINK'
        links << Link.new(links.length, fields[1], fields[2].to_i, fields[3].to_i,
                          fields[4], fields[5].to_i, fields[6].to_i)
      when 'PREFIX'
        initial << [fields[1].to_i, prefix(fields[2]), fields[3], fields.drop(4)]
      end
    end
    Network.new(router_ids, links, initial)
  end
end
