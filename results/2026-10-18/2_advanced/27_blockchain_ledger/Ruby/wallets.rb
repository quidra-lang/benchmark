require_relative 'hashing'

module Ledger
  Wallet = Struct.new(:name, :secret, :address)

  class Wallets
    attr_reader :all

    def initialize(path)
      @all = File.readlines(path, chomp: true).map do |line|
        name, secret = line.split
        Wallet.new(name, secret, Hashing.digest("addr:#{secret}")[0, 16])
      end
      @by_name = @all.to_h { |wallet| [wallet.name, wallet] }
      @by_address = @all.to_h { |wallet| [wallet.address, wallet] }
    end

    def [](name)
      @by_name.fetch(name)
    end

    def owner(address)
      @by_address[address]
    end

    def self.signature(secret, index, body)
      Hashing.digest("#{secret}:#{index}:#{body}")[0, 16]
    end
  end
end
