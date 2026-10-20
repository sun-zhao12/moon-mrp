///|
test "horizon bounds are inclusive at 128" {
  let items = [item("A")]
  assert_eq(@moon-mrp.plan(request(items, horizon=1)).unwrap().horizon, 1)
  assert_eq(@moon-mrp.plan(request(items, horizon=128)).unwrap().horizon, 128)
  assert_eq(
    @moon-mrp.plan(request(items, horizon=129)).unwrap_err(),
    @moon-mrp.InvalidHorizon,
  )
}

///|
test "item count accepts 64 and rejects 65" {
  let sixty_four : Array[@moon-mrp.Item] = []
  for i in 0..<64 {
    sixty_four.push(item("S" + i.to_string()))
  }
  assert_eq(
    @moon-mrp.plan(request(sixty_four, horizon=1)).unwrap().items.length(),
    64,
  )
  let sixty_five = sixty_four.copy()
  sixty_five.push(item("S64"))
  assert_eq(
    @moon-mrp.plan(request(sixty_five, horizon=1)).unwrap_err(),
    @moon-mrp.SizeLimit,
  )
}

///|
test "movement count accepts 10000 and rejects 10001" {
  let many : Array[@moon-mrp.Movement] = []
  for i in 0..<10000 {
    many.push(movement("d" + i.to_string(), "A", 0, 1L))
  }
  assert_eq(
    @moon-mrp.plan(
      request([item("A", stock=1000000000000L)], demands=many, horizon=1),
    ).unwrap().items.length(),
    1,
  )
  let too_many = many.copy()
  too_many.push(movement("extra", "A", 0, 1L))
  assert_eq(
    @moon-mrp.plan(
      request([item("A", stock=1000000000000L)], demands=too_many, horizon=1),
    ).unwrap_err(),
    @moon-mrp.SizeLimit,
  )
}

///|
test "bom edge count rejects 4097 rows before duplicate detection" {
  let edges : Array[@moon-mrp.Component] = []
  for _ in 0..<4097 {
    edges.push({ parent: "A", child: "B", units_per: 1L, })
  }
  assert_eq(
    @moon-mrp.plan(request([item("A"), item("B")], bom=edges, horizon=1)).unwrap_err(),
    @moon-mrp.SizeLimit,
  )
}
