cap =: 3 : 0
  (toupper {.y),}.y
)
main =: 3 : 0
  identifiers =. 'user_name';'maxRetryCount';'ShoppingCartItem';'background-color';'get_last_login_time';'isEmailAddressValid'
  for_box. identifiers do.
    identifier =. >box
    words =. 0$<''
    current =. ''
    for_char. identifier do.
      if. char e.'_-' do.
        if. #current do. words =. words,<current end.
        current =. ''
      elseif. char e.'ABCDEFGHIJKLMNOPQRSTUVWXYZ' do.
        if. #current do. words =. words,<current end.
        current =. tolower char
      else. current =. current,char
      end.
    end.
    if. #current do. words =. words,<current end.
    snake =. }. ; (<'_') ,&.> words
    kebab =. }. ; (<'-') ,&.> words
    pascal =. ;cap&.>words
    camel =. (>0{words),;cap&.>}.words
    smoutput identifier,': snake=',snake,', camel=',camel,', pascal=',pascal,', kebab=',kebab
  end.
)
main ''
