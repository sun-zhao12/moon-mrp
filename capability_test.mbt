///|
test "days-of-demand safety stock follows the horizon average" {
  let p = @moon-mrp.plan(
    request(
      [item("A", safety=@moon-mrp.SafetyStock::DaysOfDemand(2))],
      demands=[
        movement("d0", "A", 0, q(10)),
        movement("d1", "A", 1, q(10)),
        movement("d2", "A", 2, q(10)),
        movement("d3", "A", 3, q(10)),
      ],
      horizon=4,
    ),
  ).unwrap()
  assert_eq(row(p, "A").buckets[0].planned_receipt, q(30))
  assert_eq(row(p, "A").buckets[1].planned_receipt, q(10))
  assert_eq(row(p, "A").buckets[2].planned_receipt, q(10))
  assert_eq(row(p, "A").buckets[3].planned_receipt, q(10))
  for bucket in row(p, "A").buckets {
    assert_eq(bucket.projected, q(20))
  }
}

///|
test "percent-of-demand safety stock is a fraction of the bucket gross" {
  let p = @moon-mrp.plan(
    request(
      [item("A", safety=@moon-mrp.SafetyStock::PercentOfDemand(50))],
      demands=[movement("d", "A", 1, q(10))],
      horizon=2,
    ),
  ).unwrap()
  assert_eq(row(p, "A").buckets[1].net, q(15))
  assert_eq(row(p, "A").buckets[1].planned_receipt, q(15))
}

///|
test "reorder point orders its quantity when the balance dips" {
  let p = @moon-mrp.plan(
    request(
      [item("A", stock=q(10), lot=@moon-mrp.ReorderPoint(q(5), q(20)))],
      demands=[movement("d", "A", 1, q(8))],
      horizon=2,
    ),
  ).unwrap()
  assert_eq(row(p, "A").buckets[1].net, @moon-mrp.Qty::zero())
  assert_eq(row(p, "A").buckets[1].planned_receipt, q(20))
  assert_eq(row(p, "A").buckets[1].projected, q(22))
}

///|
test "reorder point keeps the net requirement when it is larger" {
  let p = @moon-mrp.plan(
    request(
      [item("A", lot=@moon-mrp.ReorderPoint(q(5), q(20)))],
      demands=[movement("d", "A", 0, q(25))],
      horizon=1,
    ),
  ).unwrap()
  assert_eq(row(p, "A").buckets[0].planned_receipt, q(25))
  assert_eq(
    @moon-mrp.order_quantity(q(7), @moon-mrp.ReorderPoint(q(5), q(20))).unwrap(),
    q(20),
  )
}

///|
test "phantom items pass demand straight to their components" {
  let p = @moon-mrp.plan(
    request(
      [item("P", phantom=true), item("C")],
      demands=[movement("d", "P", 1, q(10))],
      bom=[
        {
          parent: "P",
          child: "C",
          units_per: q(2),
          usage_unit: "",
          scrap_per_mille: 0,
        },
      ],
      horizon=3,
    ),
  ).unwrap()
  assert_eq(p.orders.length(), 1)
  assert_eq(p.orders[0].item, "C")
  assert_eq(p.orders[0].quantity, q(20))
  assert_eq(row(p, "P").buckets[1].gross, q(10))
  assert_eq(row(p, "P").buckets[1].planned_receipt, @moon-mrp.Qty::zero())
  assert_eq(row(p, "C").buckets[1].gross, q(20))
}

///|
test "phantom items reject stock and receipts" {
  assert_eq(
    @moon-mrp.plan(request([item("P", stock=q(1), phantom=true)], horizon=1)).unwrap_err(),
    @moon-mrp.InvalidItem("P"),
  )
  assert_eq(
    @moon-mrp.plan(
      request(
        [item("P", phantom=true), item("C")],
        receipts=[movement("r", "P", 0, q(1))],
        bom=[
          {
            parent: "P",
            child: "C",
            units_per: q(1),
            usage_unit: "",
            scrap_per_mille: 0,
          },
        ],
        horizon=1,
      ),
    ).unwrap_err(),
    @moon-mrp.InvalidItem("P"),
  )
}

///|
test "excess inventory becomes a stock exception" {
  let p = @moon-mrp.plan(
    request([item("A", stock=q(100), max=q(50))], horizon=2),
  ).unwrap()
  assert_eq(p.exceptions.length(), 2)
  assert_eq(p.exceptions[0].item, "A")
  assert_eq(p.exceptions[0].bucket, 0)
  assert_eq(p.exceptions[0].projected, q(100))
  assert_eq(p.exceptions[0].maximum, q(50))
}
