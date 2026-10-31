const identifiers = [
  "user_name", "maxRetryCount", "ShoppingCartItem", "background-color", "get_last_login_time",
  "isEmailAddressValid"
];
for (const identifier of identifiers) {
  const words = identifier.split(/[_-]|(?=[A-Z])/).filter(Boolean).map(word => word.toLowerCase());
  const capitals = words.map(word => word[0].toUpperCase() + word.slice(1));
  const snake = words.join("_"), camel = words[0] + capitals.slice(1).join("");
  const pascal = capitals.join(""), kebab = words.join("-");
  console.log(`${identifier}: snake=${snake}, camel=${camel}, pascal=${pascal}, kebab=${kebab}`);
}
