identifiers = %w[user_name maxRetryCount ShoppingCartItem background-color get_last_login_time isEmailAddressValid]
identifiers.each do |identifier|
  words = identifier.split(/[_-]|(?=[A-Z])/).reject(&:empty?).map(&:downcase)
  snake = words.join('_')
  camel = words.first + words.drop(1).map(&:capitalize).join
  pascal = words.map(&:capitalize).join
  kebab = words.join('-')
  puts "#{identifier}: snake=#{snake}, camel=#{camel}, pascal=#{pascal}, kebab=#{kebab}"
end
