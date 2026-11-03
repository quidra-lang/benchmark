const queries = [
  "name=Alice+Smith&age=30&city=New%20York",
  "q=c%2B%2B+tutorial&page=2&sort=desc&page=3",
  "msg=50%25+off%21&debug&lang=en&ref=&lang=ja",
  "redirect=https%3a%2f%2fexample.com%2Fhome&token=abc==&item10=pen&item2=fish%26chips"
];
queries.forEach((query, number) => {
  const values = Map.groupBy(new URLSearchParams(query), ([key]) => key);
  console.log(`query ${number + 1}:`);
  for (const key of [...values.keys()].sort()) {
    const quoted = values.get(key).map(([, value]) => `"${value}"`).join(", ");
    console.log(`  ${key}: ${quoted}`);
  }
});
