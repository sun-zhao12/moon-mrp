///|
test "lot-for-lot returns the net demand unchanged" {
  assert_eq(@moon-mrp.order_quantity(q(7), @moon-mrp.LotForLot).unwrap(), q(7))
  assert_eq(
    @moon-mrp.order_quantity(@moon-mrp.Qty::zero(), @moon-mrp.LotForLot).unwrap(),
    @moon-mrp.Qty::zero(),
  )
  assert_eq(
    @moon-mrp.order_quantity(qm(1000000000000000L), @moon-mrp.LotForLot).unwrap(),
    qm(1000000000000000L),
  )
}

///|
test "fixed quantity and multiple round up to whole batches" {
  assert_eq(
    @moon-mrp.order_quantity(q(7), @moon-mrp.FixedQuantity(q(5))).unwrap(),
    q(10),
  )
  assert_eq(
    @moon-mrp.order_quantity(q(10), @moon-mrp.FixedQuantity(q(5))).unwrap(),
    q(10),
  )
  assert_eq(
    @moon-mrp.order_quantity(q(7), @moon-mrp.Multiple(q(5))).unwrap(),
    q(10),
  )
}

///|
test "minimum-multiple satisfies both the minimum and the multiple" {
  assert_eq(
    @moon-mrp.order_quantity(q(1), @moon-mrp.MinimumMultiple(q(23), q(4))).unwrap(),
    q(24),
  )
  assert_eq(
    @moon-mrp.order_quantity(q(24), @moon-mrp.MinimumMultiple(q(23), q(4))).unwrap(),
    q(24),
  )
  assert_eq(
    @moon-mrp.order_quantity(q(25), @moon-mrp.MinimumMultiple(q(23), q(4))).unwrap(),
    q(28),
  )
  assert_eq(
    @moon-mrp.order_quantity(
      @moon-mrp.Qty::zero(),
      @moon-mrp.MinimumMultiple(q(23), q(4)),
    ).unwrap(),
    @moon-mrp.Qty::zero(),
  )
}

///|
test "period order and min-max need a calendar and degrade predictably" {
  assert_eq(
    @moon-mrp.order_quantity(q(7), @moon-mrp.PeriodOrder(3)).unwrap(),
    q(7),
  )
  assert_eq(
    @moon-mrp.order_quantity(q(7), @moon-mrp.MinMax(q(5), q(20))).unwrap(),
    q(20),
  )
  assert_eq(
    @moon-mrp.order_quantity(q(25), @moon-mrp.MinMax(q(5), q(20))).unwrap(),
    q(25),
  )
}

///|
test "invalid lot policies are rejected before any rounding" {
  let bad_policies : Array[@moon-mrp.LotRule] = [
    @moon-mrp.FixedQuantity(@moon-mrp.Qty::zero()),
    @moon-mrp.Multiple(@moon-mrp.Qty::zero()),
    @moon-mrp.Multiple(qm(-1000L)),
    @moon-mrp.MinimumMultiple(@moon-mrp.Qty::zero(), q(4)),
    @moon-mrp.MinimumMultiple(q(4), @moon-mrp.Qty::zero()),
    @moon-mrp.PeriodOrder(0),
    @moon-mrp.PeriodOrder(1025),
    @moon-mrp.MinMax(q(21), q(20)),
  ]
  for bad in bad_policies {
    assert_eq(
      @moon-mrp.order_quantity(q(5), bad).unwrap_err(),
      @moon-mrp.InvalidItem("lot or net quantity"),
    )
  }
}

///|
test "negative and oversized net demands are rejected" {
  assert_eq(
    @moon-mrp.order_quantity(qm(-1L), @moon-mrp.LotForLot).unwrap_err(),
    @moon-mrp.InvalidItem("lot or net quantity"),
  )
  assert_eq(
    @moon-mrp.order_quantity(qm(1000000000000001L), @moon-mrp.LotForLot).unwrap_err(),
    @moon-mrp.InvalidItem("lot or net quantity"),
  )
}

///|
test "rounding past the quantity limit is reported as a limit error" {
  assert_eq(
    @moon-mrp.order_quantity(
      qm(999999999999999L),
      @moon-mrp.Multiple(qm(400000000000000L)),
    ).unwrap_err(),
    @moon-mrp.QuantityLimit("lot rounding"),
  )
  assert_eq(
    @moon-mrp.order_quantity(qm(999999999999L), @moon-mrp.LotForLot).unwrap(),
    qm(999999999999L),
  )
}
