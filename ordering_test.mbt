///|
test "identifiers are ordered by UTF-16 code unit, not by locale" {
  let p = @moon-mrp.plan(request([item("a"), item("Z"), item("A")], horizon=1)).unwrap()
  let skus = p.items.map(fn(ip) { ip.item })
  assert_eq(skus, ["A", "Z", "a"])
}

///|
test "pegs order by item, then bucket, then source kind" {
  let p = @moon-mrp.plan(
    request(
      [item("P"), item("C")],
      demands=[movement("p-order", "P", 1, 1L), movement("c-order", "C", 1, 1L)],
      bom=[{ parent: "P", child: "C", units_per: 1L, }],
      horizon=2,
    ),
  ).unwrap()
  let pegs = p.pegs
  assert_eq(pegs.length(), 3)
  assert_eq(pegs[0].item, "C")
  assert_eq(pegs[0].source, @moon-mrp.Demand("c-order"))
  assert_eq(pegs[1].item, "C")
  assert_eq(pegs[1].source, @moon-mrp.ParentOrder("P", 1))
  assert_eq(pegs[2].item, "P")
  assert_eq(pegs[2].source, @moon-mrp.Demand("p-order"))
}

///|
test "orders are ordered by item and then by receipt bucket" {
  let p = @moon-mrp.plan(
    request(
      [item("B"), item("A")],
      demands=[
        movement("b2", "B", 2, 1L),
        movement("a2", "A", 2, 1L),
        movement("b0", "B", 0, 1L),
        movement("a0", "A", 0, 1L),
      ],
      horizon=3,
    ),
  ).unwrap()
  let labels = p.orders.map(fn(o) {
    o.item + "#" + o.receipt_bucket.to_string()
  })
  assert_eq(labels, ["A#0", "A#2", "B#0", "B#2"])
}

///|
test "repeated planning of the same request is deterministic" {
  let r = request(
    [item("K", stock=1L, lead=1, lot=Multiple(5L)), item("R", stock=2L)],
    demands=[movement("sale", "K", 3, 7L)],
    bom=[{ parent: "K", child: "R", units_per: 3L, }],
    horizon=5,
  )
  let first = @moon-mrp.plan(r).unwrap()
  let second = @moon-mrp.plan(r).unwrap()
  assert_eq(first, second)
  assert_eq(first.orders, second.orders)
  assert_eq(first.pegs, second.pegs)
}
