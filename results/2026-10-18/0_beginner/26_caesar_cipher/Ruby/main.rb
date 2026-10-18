def caesar(text, shift)
  text.gsub(/[A-Za-z]/) do |char|
    base = char <= 'Z' ? 'A'.ord : 'a'.ord
    (base + (char.ord - base + shift) % 26).chr
  end
end

message = 'Zoe, meet Max by the Old Bridge at six!'
encrypted = caesar(message, 3)
puts encrypted
puts caesar(encrypted, -3)
