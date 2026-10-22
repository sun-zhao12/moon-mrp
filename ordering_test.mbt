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
      demands=[
        movement("p-order", "P", 1, q(1)),
        movement("c-order", "C", 1, q(1)),
      ],
      bom=[
        {
          parent: "P",
          child: "C",
          units_per: q(1),
          usage_unit: "",
          scrap_per_mille: 0,
        },
      ],
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
        movement("b2", "B", 2, q(1)),
        movement("a2", "A", 2, q(1)),
        movement("b0", "B", 0, q(1)),
        movement("a0", "A", 0, q(1)),
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
    [
      item("K", stock=q(1), lead=1, lot=@moon-mrp.Multiple(q(5))),
      item("R", stock=q(2)),
    ],
    demands=[movement("sale", "K", 3, q(7))],
    bom=[
      {
        parent: "K",
        child: "R",
        units_per: q(3),
        usage_unit: "",
        scrap_per_mille: 0,
      },
    ],
    horizon=5,
  )
  let first = @moon-mrp.plan(r).unwrap()
  let second = @moon-mrp.plan(r).unwrap()
  assert_eq(first, second)
  assert_eq(first.orders, second.orders)
  assert_eq(first.pegs, second.pegs)
}
