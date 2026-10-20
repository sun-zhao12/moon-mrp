///|
test "bucket and order objects expose every documented field" {
  let p = @moon-mrp.plan(
    request(
      [item("A", stock=5L, lead=1, lot=Multiple(2L))],
      demands=[movement("d", "A", 2, 9L)],
      receipts=[movement("r", "A", 1, 1L)],
      horizon=3,
    ),
  ).unwrap()
  let json = p.to_json()
  assert_eq(field(json, "schema"), Json("moon-mrp.plan.v1"))
  assert_eq(field(json, "horizon"), Json(3))
  let items = match field(json, "items") {
    Array(a) => a
    _ => abort("array expected")
  }
  assert_eq(items.length(), 1)
  assert_eq(field(items[0], "item"), Json("A"))
  let buckets = match field(items[0], "buckets") {
    Array(a) => a
    _ => abort("array expected")
  }
  assert_eq(buckets.length(), 3)
  let second = buckets[1]
  assert_eq(field(second, "index"), Json(1))
  assert_eq(field(second, "gross"), Json("0"))
  assert_eq(field(second, "scheduled"), Json("1"))
  assert_eq(field(second, "net"), Json("0"))
  assert_eq(field(second, "planned_receipt"), Json("0"))
  assert_eq(field(second, "planned_release"), Json("4"))
  assert_eq(field(second, "projected"), Json("6"))
  let last = buckets[2]
  assert_eq(field(last, "gross"), Json("9"))
  assert_eq(field(last, "net"), Json("3"))
  assert_eq(field(last, "planned_receipt"), Json("4"))
  assert_eq(field(last, "projected"), Json("1"))
  let orders = match field(json, "orders") {
    Array(a) => a
    _ => abort("array expected")
  }
  assert_eq(orders.length(), 1)
  assert_eq(field(orders[0], "item"), Json("A"))
  assert_eq(field(orders[0], "receipt_bucket"), Json(2))
  assert_eq(field(orders[0], "release_bucket"), Json(1))
  assert_eq(field(orders[0], "quantity"), Json("4"))
}

///|
test "peg sources separate independent demand from parent orders" {
  let p = @moon-mrp.plan(
    request(
      [item("P"), item("C")],
      demands=[movement("d", "P", 1, 3L)],
      bom=[{ parent: "P", child: "C", units_per: 2L, }],
      horizon=2,
    ),
  ).unwrap()
  let pegs = match field(p.to_json(), "pegs") {
    Array(a) => a
    _ => abort("array expected")
  }
  assert_eq(pegs.length(), 2)
  let parent_source = field(pegs[0], "source")
  assert_eq(field(parent_source, "kind"), Json("parent_order"))
  assert_eq(field(parent_source, "parent"), Json("P"))
  assert_eq(field(parent_source, "receipt_bucket"), Json(1))
  assert_eq(field(pegs[0], "quantity"), Json("6"))
  let demand_source = field(pegs[1], "source")
  assert_eq(field(demand_source, "kind"), Json("demand"))
  assert_eq(field(demand_source, "id"), Json("d"))
  assert_eq(field(pegs[1], "quantity"), Json("3"))
}

///|
test "an empty demand set still exports schema and empty arrays" {
  let p = @moon-mrp.plan(request([item("A")], horizon=2)).unwrap()
  let json = p.to_json()
  assert_eq(field(json, "schema"), Json("moon-mrp.plan.v1"))
  match field(json, "orders") {
    Array(a) => assert_eq(a.length(), 0)
    _ => abort("array expected")
  }
  match field(json, "pegs") {
    Array(a) => assert_eq(a.length(), 0)
    _ => abort("array expected")
  }
  let items = match field(json, "items") {
    Array(a) => a
    _ => abort("array expected")
  }
  let buckets = match field(items[0], "buckets") {
    Array(a) => a
    _ => abort("array expected")
  }
  assert_eq(buckets.length(), 2)
  assert_eq(field(buckets[0], "projected"), Json("0"))
}
