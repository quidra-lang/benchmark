require_relative 'hashing'
require_relative 'wallets'

module Ledger
  Coin = Struct.new(:address, :amount, :height, :coinbase) do
    def mature?(height, maturity)
      !coinbase || self.height.zero? || height >= self.height + maturity
    end
  end

  class Transaction
    attr_reader :text, :txid, :size, :body, :inputs, :outputs, :signatures, :coinbase_height

    def initialize(text)
      @text = text
      @txid = Hashing.digest(text)
      @size = text.bytesize
      parts = text.split(';')
      @outputs = parts[1].delete_prefix('out=').split(',').map do |output|
        address, amount = output.split(':')
        [address, amount.to_i]
      end
      if text.start_with?('cb=')
        @coinbase_height = parts[0].delete_prefix('cb=').to_i
        @inputs = []
        @signatures = []
        @body = nil
      else
        @coinbase_height = nil
        @inputs = parts[0].delete_prefix('in=').split(',').map do |input|
          txid, index = input.split(':')
          [txid, index.to_i]
        end
        @signatures = parts[2].delete_prefix('sig=').split(',')
        @body = text.split(';sig=', 2).first
      end
    end

    def coinbase?
      !@coinbase_height.nil?
    end

    def self.create(inputs, outputs, secret)
      body = "in=#{inputs.map { |reference| reference.join(':') }.join(',')};out=#{outputs.map { |output| output.join(':') }.join(',')}"
      signatures = inputs.each_index.map { |index| Wallets.signature(secret, index, body) }
      new("#{body};sig=#{signatures.join(',')}")
    end

    def self.coinbase(height, outputs)
      new("cb=#{height};out=#{outputs.map { |output| output.join(':') }.join(',')}")
    end

    def bad_outputs?(wallets)
      @outputs.any? { |address, amount| wallets.owner(address).nil? || amount.zero? }
    end

    def output_amount
      @outputs.sum { |_, amount| amount }
    end

    def check(utxo, spent, height, wallets, maturity)
      return ['bad-output'] if bad_outputs?(wallets)

      seen = {}
      input_amount = 0
      @inputs.each_with_index do |reference, index|
        return ['double-spend'] if spent[reference] || seen[reference]

        seen[reference] = true
        coin = utxo[reference]
        return ['missing-input'] unless coin
        return ['immature'] unless coin.mature?(height, maturity)

        secret = wallets.owner(coin.address).secret
        return ['bad-sig'] unless @signatures[index] == Wallets.signature(secret, index, @body)

        input_amount += coin.amount
      end
      output_amount = self.output_amount
      return ['overspend'] if input_amount < output_amount

      [nil, input_amount - output_amount]
    end

    def apply(utxo, height)
      @inputs.each { |reference| utxo.delete(reference) }
      @outputs.each_with_index do |(address, amount), index|
        utxo[[@txid, index]] = Coin.new(address, amount, height, coinbase?)
      end
      utxo
    end
  end
end
