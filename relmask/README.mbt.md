# Library usage

The plan owns all schema details. Every input column needs an explicit rule.

```mbt check
///|
test {
  let source =
    #|{"tables":[{"name":"users","columns":[{"name":"id","type":"integer","rule":{"reindex":100}}],"primary":["id"]}]}
  let data =
    #|{"users":[{"id":7}]}
  let plan = @relmask.Plan::parse(source)
  let checked = plan.transform(data, "example-only-key-at-least-32-bytes")
  assert_eq(checked.to_json(), "{\"users\":[{\"id\":100}]}")
}
```
