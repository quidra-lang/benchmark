message = 'Zoe, meet Max by the Old Bridge at six!'
encrypted = message.tr('A-Za-z', 'D-ZA-Cd-za-c')
puts encrypted
puts encrypted.tr('D-ZA-Cd-za-c', 'A-Za-z')
