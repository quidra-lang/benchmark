function decode(text) {
  let result = "";
  for (let i = 0; i < text.length; i++) {
    if (text[i] === "+") result += " ";
    else if (text[i] === "%") {
      result += String.fromCharCode(parseInt(text.slice(i + 1, i + 3), 16));
      i += 2;
    } else result += text[i];
  }
  return result;
}
const queries = [
  "name=Alice+Smith&age=30&city=New%20York",
  "q=c%2B%2B+tutorial&page=2&sort=desc&page=3",
  "msg=50%25+off%21&debug&lang=en&ref=&lang=ja",
  "redirect=https%3a%2f%2fexample.com%2Fhome&token=abc==&item10=pen&item2=fish%26chips"
];
queries.forEach((query, number) => {
  const values = new Map();
  for (const item of query.split("&")) {
    const equals = item.indexOf("=");
    const key = decode(equals < 0 ? item : item.slice(0, equals));
    const value = decode(equals < 0 ? "" : item.slice(equals + 1));
    if (!values.has(key)) values.set(key, []);
    values.get(key).push(value);
  }
  console.log(`query ${number + 1}:`);
  for (const key of [...values.keys()].sort()) {
    const quoted = values.get(key).map(value => `"${value}"`).join(", ");
    console.log(`  ${key}: ${quoted}`);
  }
});
