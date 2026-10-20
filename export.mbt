///|
/// Exact quantities are strings, including values small enough for JS numbers.
pub fn Plan::to_json(self : Plan) -> Json {
  Json({
    "schema": Json("moon-mrp.plan.v1"),
    "horizon": Json(self.horizon),
    "items": Json(
      self.items.map(fn(p) {
        Json({
          "item": Json(p.item),
          "buckets": Json(
            p.buckets.map(fn(b) {
              Json({
                "index": Json(b.index),
                "gross": Json(b.gross.to_string()),
                "scheduled": Json(b.scheduled.to_string()),
                "net": Json(b.net.to_string()),
                "planned_receipt": Json(b.planned_receipt.to_string()),
                "planned_release": Json(b.planned_release.to_string()),
                "projected": Json(b.projected.to_string()),
              })
            }),
          ),
        })
      }),
    ),
    "orders": Json(
      self.orders.map(fn(o) {
        Json({
          "item": Json(o.item),
          "receipt_bucket": Json(o.receipt_bucket),
          "release_bucket": Json(o.release_bucket),
          "quantity": Json(o.quantity.to_string()),
        })
      }),
    ),
    "pegs": Json(
      self.pegs.map(fn(p) {
        let source = match p.source {
          Demand(id) => Json({ "kind": Json("demand"), "id": Json(id) })
          ParentOrder(parent, receipt) =>
            Json({
              "kind": Json("parent_order"),
              "parent": Json(parent),
              "receipt_bucket": Json(receipt),
            })
        }
        Json({
          "item": Json(p.item),
          "bucket": Json(p.bucket),
          "quantity": Json(p.quantity.to_string()),
          "source": source,
        })
      }),
    ),
  })
}
