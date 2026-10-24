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
  let bundle = checked.bundle_json()
  let received = plan.verify_bundle(bundle)
  assert_eq(received.to_json(), checked.to_json())
  assert_eq(received.report_json(), checked.report_json())
  let selected = plan.subset(data, "{\"users\":[{\"id\":7}]}")
  assert_eq(selected, data)
  let csv_tables = plan.export_csv(received.to_json())
  assert_eq(plan.import_csv(csv_tables), received.to_json())
  let batch = plan.transform_with_state(
    data, "example-only-key-at-least-32-bytes",
  )
  let replay = plan.transform_with_state(
    data,
    "example-only-key-at-least-32-bytes",
    previous=batch.state_json(),
  )
  assert_eq(replay.dataset().to_json(), batch.dataset().to_json())
  assert_true(
    plan
    .compare_datasets(batch.dataset().to_json(), replay.dataset().to_json())
    .is_empty(),
  )
}
```
