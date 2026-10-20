///|
test "lot-for-lot returns the net demand unchanged" {
  assert_eq(@moon-mrp.order_quantity(7L, LotForLot).unwrap(), 7L)
  assert_eq(@moon-mrp.order_quantity(0L, LotForLot).unwrap(), 0L)
  assert_eq(
    @moon-mrp.order_quantity(1000000000000L, LotForLot).unwrap(),
    1000000000000L,
  )
}

///|
test "multiple rounds up to the next multiple" {
  assert_eq(@moon-mrp.order_quantity(7L, Multiple(5L)).unwrap(), 10L)
  assert_eq(@moon-mrp.order_quantity(10L, Multiple(5L)).unwrap(), 10L)
  assert_eq(
    @moon-mrp.order_quantity(1L, Multiple(999999999L)).unwrap(),
    999999999L,
  )
}

///|
test "minimum-multiple satisfies both the minimum and the multiple" {
  assert_eq(
    @moon-mrp.order_quantity(1L, MinimumMultiple(23L, 4L)).unwrap(),
    24L,
  )
  assert_eq(
    @moon-mrp.order_quantity(24L, MinimumMultiple(23L, 4L)).unwrap(),
    24L,
  )
  assert_eq(
    @moon-mrp.order_quantity(25L, MinimumMultiple(23L, 4L)).unwrap(),
    28L,
  )
  assert_eq(@moon-mrp.order_quantity(0L, MinimumMultiple(23L, 4L)).unwrap(), 0L)
}

///|
test "invalid lot policies are rejected before any rounding" {
  let bad_policies : Array[@moon-mrp.LotRule] = [
    Multiple(0L),
    Multiple(-1L),
    Multiple(1000000001L),
    MinimumMultiple(0L, 4L),
    MinimumMultiple(4L, 0L),
    MinimumMultiple(4L, 1000000001L),
  ]
  for bad in bad_policies {
    assert_eq(
      @moon-mrp.order_quantity(5L, bad).unwrap_err(),
      @moon-mrp.InvalidItem("lot or net quantity"),
    )
  }
}

///|
test "negative and oversized net demands are rejected" {
  assert_eq(
    @moon-mrp.order_quantity(-1L, LotForLot).unwrap_err(),
    @moon-mrp.InvalidItem("lot or net quantity"),
  )
  assert_eq(
    @moon-mrp.order_quantity(1000000000001L, LotForLot).unwrap_err(),
    @moon-mrp.InvalidItem("lot or net quantity"),
  )
}

///|
test "rounding past the quantity limit is reported as a limit error" {
  assert_eq(
    @moon-mrp.order_quantity(999999999999L, Multiple(999999999L)).unwrap_err(),
    @moon-mrp.QuantityLimit("lot rounding"),
  )
  assert_eq(
    @moon-mrp.order_quantity(999999999999L, LotForLot).unwrap(),
    999999999999L,
  )
}
