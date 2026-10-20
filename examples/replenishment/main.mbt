///|
/// A single-store replenishment run: safety stock, an open purchase order and a
/// minimum-multiple policy. The same numbers are checked against a hand-written
/// inventory simulation so the example doubles as an end-to-end assertion.
fn main raise {
  let horizon = 6
  let request : @mrp.Request = {
    horizon,
    items: [
      {
        sku: "LABEL",
        on_hand: 3L,
        safety_stock: 2L,
        lead_time: 1,
        lot: @mrp.MinimumMultiple(10L, 4L),
      },
    ],
    bom: [],
    demands: [
      { id: "store-a", item: "LABEL", bucket: 2, quantity: 9L, },
      { id: "store-b", item: "LABEL", bucket: 3, quantity: 3L, },
    ],
    receipts: [{ id: "open-po", item: "LABEL", bucket: 1, quantity: 2L, }],
  }
  let plan = request |> @mrp.plan |> Result::unwrap
  println(
    "1 store replenishment (minimum 10, multiple 4, safety stock 2, lead time 1)",
  )
  println("  bucket gross scheduled net receipt release projected")
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
      bucket.planned_release.to_string() +
      " " +
      bucket.projected.to_string(),
    )
    inventory = inventory +
      bucket.scheduled +
      bucket.planned_receipt -
      bucket.gross
    assert_eq(inventory, bucket.projected)
  }
  assert_eq(plan.orders.length(), 1)
  let order = plan.orders[0]
  assert_eq(order.receipt_bucket, 2)
  assert_eq(order.release_bucket, 1)
  assert_eq(order.quantity, 12L)
  println(
    "  order: LABEL quantity=" +
    order.quantity.to_string() +
    " receipt=" +
    order.receipt_bucket.to_string() +
    " release=" +
    order.release_bucket.to_string(),
  )

  println("2 policy applied without a plan")
  for net in [0L, 1L, 11L, 12L] {
    let rounded = @mrp.order_quantity(net, @mrp.MinimumMultiple(10L, 4L)).unwrap()
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
  assert_true(json.contains("\"schema\":\"moon-mrp.plan.v1\""))
  println("  ok")
}
