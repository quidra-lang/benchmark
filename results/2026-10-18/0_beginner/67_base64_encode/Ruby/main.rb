alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
['Man', 'Hello, World!', '', '<b>bold</b>', 'a+b=c?'].each do |text|
  encoded = ''
  text.bytes.each_slice(3) do |chunk|
    size = chunk.length
    chunk += [0] * (3 - size)
    value = (chunk[0] << 16) | (chunk[1] << 8) | chunk[2]
    symbols = [18, 12, 6, 0].map { |shift| alphabet[(value >> shift) & 63] }.join
    encoded += symbols[0, size + 1] + '=' * (3 - size)
  end
  puts %("#{text}" -> "#{encoded}")
end
