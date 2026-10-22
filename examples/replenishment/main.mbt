///|
/// A single-store replenishment run: safety stock, an open purchase order and a
/// minimum-multiple policy. The bucket table is checked against an independent
/// inventory recurrence so the example doubles as an end-to-end assertion.
fn q(units : Int) -> @mrp.Qty {
  @mrp.Qty::int(units)
}

///|
fn main raise {
  let horizon = 6
  let request : @mrp.Request = {
    horizon,
    items: [
      {
        sku: "LABEL",
        unit: "EA",
        on_hand: q(3),
        safety_stock: q(2),
        lead_time: 1,
        yield_per_mille: 1000,
        lot: @mrp.MinimumMultiple(q(10), q(4)),
      },
    ],
    bom: [],
    demands: [
      { id: "store-a", item: "LABEL", bucket: 2, quantity: q(9), },
      { id: "store-b", item: "LABEL", bucket: 3, quantity: q(3), },
    ],
    receipts: [{ id: "open-po", item: "LABEL", bucket: 1, quantity: q(2), }],
    conversions: [],
    policy: @mrp.Strict,
  }
  let plan = request |> @mrp.plan |> Result::unwrap
  println(
    "1 store replenishment (minimum 10, multiple 4, safety stock 2, lead time 1)",
  )
  println("  bucket gross scheduled net receipt received release projected")
  let mut inventory = request.items[0].on_hand
  for bucket in plan.items[0].buckets {
    println(
      "  " +
      bucket.index.to_string() +
      " " +
      bucket.gross.to_string() +
      " " +
      bucket.scheduled.to_string() +
      " " +
      bucket.net.to_string() +
      " " +
      bucket.planned_receipt.to_string() +
      " " +
      bucket.received.to_string() +
      " " +
      bucket.planned_release.to_string() +
      " " +
      bucket.projected.to_string(),
    )
    inventory = inventory
      .add(bucket.scheduled)
      .add(bucket.received)
      .sub(bucket.gross)
    assert_eq(inventory, bucket.projected)
  }
  assert_eq(plan.orders.length(), 1)
  let order = plan.orders[0]
  assert_eq(order.receipt_bucket, 2)
  assert_eq(order.release_bucket, 1)
  assert_eq(order.quantity, q(12))
  println(
    "  order: LABEL quantity=" +
    order.quantity.to_string() +
    " receipt=" +
    order.receipt_bucket.to_string() +
    " release=" +
    order.release_bucket.to_string(),
  )

  println("2 policy applied without a plan")
  for net in [0, 1, 11, 12] {
    let rounded = @mrp.order_quantity(q(net), @mrp.MinimumMultiple(q(10), q(4))).unwrap()
    println(
      "  order_quantity(" +
      net.to_string() +
      ", MinimumMultiple(10,4)) = " +
      rounded.to_string(),
    )
  }

  println(
    "3 conservation held for every bucket and the JSON stays string-typed",
  )
  let json = plan.to_json().stringify()
  assert_true(json.contains("\"quantity\":\"12\""))
  assert_true(json.contains("\"schema\":\"moon-mrp.plan.v2\""))
  println("  ok")
}
