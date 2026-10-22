///|
test "horizon bounds are inclusive at 1024" {
  let items = [item("A")]
  assert_eq(@moon-mrp.plan(request(items, horizon=1)).unwrap().horizon, 1)
  assert_eq(@moon-mrp.plan(request(items, horizon=1024)).unwrap().horizon, 1024)
  assert_eq(
    @moon-mrp.plan(request(items, horizon=1025)).unwrap_err(),
    @moon-mrp.InvalidHorizon,
  )
}

///|
test "item count accepts 4096 and rejects 4097" {
  let items : Array[@moon-mrp.Item] = []
  for i in 0..<4096 {
    items.push(item("S" + i.to_string()))
  }
  assert_eq(
    @moon-mrp.plan(request(items, horizon=1)).unwrap().items.length(),
    4096,
  )
  let more = items.copy()
  more.push(item("S4096"))
  assert_eq(
    @moon-mrp.plan(request(more, horizon=1)).unwrap_err(),
    @moon-mrp.SizeLimit,
  )
}

///|
test "movement count accepts 100000 and rejects 100001" {
  let many : Array[@moon-mrp.Movement] = []
  for i in 0..<100000 {
    many.push(movement("d" + i.to_string(), "A", 0, q(1)))
  }
  assert_eq(
    @moon-mrp.plan(
      request([item("A", stock=q(100000))], demands=many, horizon=1),
    ).unwrap().items.length(),
    1,
  )
  let too_many = many.copy()
  too_many.push(movement("extra", "A", 0, q(1)))
  assert_eq(
    @moon-mrp.plan(
      request([item("A", stock=q(100000))], demands=too_many, horizon=1),
    ).unwrap_err(),
    @moon-mrp.SizeLimit,
  )
}

///|
test "bom edge count rejects 100001 rows before duplicate detection" {
  let edges : Array[@moon-mrp.Component] = []
  for _ in 0..<100001 {
    edges.push({
      parent: "A",
      child: "B",
      units_per: q(1),
      usage_unit: "",
      scrap_per_mille: 0,
    })
  }
  assert_eq(
    @moon-mrp.plan(request([item("A"), item("B")], bom=edges, horizon=1)).unwrap_err(),
    @moon-mrp.SizeLimit,
  )
}
