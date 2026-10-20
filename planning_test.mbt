///|
fn item(
  sku : String,
  stock? : Int64 = 0L,
  safety? : Int64 = 0L,
  lead? : Int = 0,
  lot? : @moon-mrp.LotRule = LotForLot,
) -> @moon-mrp.Item {
  { sku, on_hand: stock, safety_stock: safety, lead_time: lead, lot, }
}

///|
fn movement(
  id : String,
  sku : String,
  t : Int,
  q : Int64,
) -> @moon-mrp.Movement {
  { id, item: sku, bucket: t, quantity: q, }
}

///|
fn request(
  items : Array[@moon-mrp.Item],
  demands? : Array[@moon-mrp.Movement] = [],
  receipts? : Array[@moon-mrp.Movement] = [],
  bom? : Array[@moon-mrp.Component] = [],
  horizon? : Int = 6,
) -> @moon-mrp.Request {
  { horizon, items, demands, receipts, bom, }
}

///|
fn row(p : @moon-mrp.Plan, sku : String) -> @moon-mrp.ItemPlan {
  p.items.filter(fn(p) { p.item == sku })[0]
}

///|
test "multilevel shared components are netted after every parent is exploded" {
  let r = request(
    [
      item("K", stock=1L, lead=1, lot=Multiple(5L)),
      item("A", stock=4L, lead=2, lot=Multiple(4L)),
      item("R", stock=5L, lead=1),
    ],
    demands=[movement("sale", "K", 5, 9L), movement("spare", "A", 4, 3L)],
    receipts=[movement("open", "A", 4, 5L)],
    bom=[
      { parent: "K", child: "A", units_per: 2L, },
      { parent: "A", child: "R", units_per: 3L, },
      { parent: "K", child: "R", units_per: 1L, },
    ],
  )
  let p = @moon-mrp.plan(r).unwrap()
  assert_eq(row(p, "K").buckets[5].planned_receipt, 10L)
  assert_eq(row(p, "A").buckets[4].gross, 23L)
  assert_eq(row(p, "A").buckets[4].net, 14L)
  assert_eq(row(p, "A").buckets[4].planned_receipt, 16L)
  assert_eq(row(p, "R").buckets[2].gross, 48L)
  assert_eq(row(p, "R").buckets[4].gross, 10L)
  assert_eq(row(p, "R").buckets[2].planned_receipt, 43L)
  assert_eq(row(p, "R").buckets[4].planned_receipt, 10L)
  assert_eq(p.orders.length(), 4)
  for ip in p.items {
    for b in ip.buckets {
      let mut pegged = 0L
      for peg in p.pegs {
        if peg.item == ip.item && peg.bucket == b.index {
          pegged += peg.quantity
        }
      }
      assert_eq(pegged, b.gross)
    }
  }
}

///|
test "finished stock and scheduled receipts prevent phantom child orders" {
  let p = @moon-mrp.plan(
    request(
      [item("P", stock=4L), item("C")],
      demands=[movement("d", "P", 2, 9L)],
      receipts=[movement("r", "P", 2, 5L)],
      bom=[{ parent: "P", child: "C", units_per: 100L, }],
    ),
  ).unwrap()
  assert_eq(p.orders, [])
  assert_eq(row(p, "C").buckets[2].gross, 0L)
}

///|
test "receipts are usable in their bucket and never borrowed from future" {
  let p = @moon-mrp.plan(
    request([item("A")], demands=[movement("d", "A", 1, 3L)], receipts=[
      movement("r", "A", 2, 5L),
    ]),
  ).unwrap()
  assert_eq(row(p, "A").buckets[1].planned_receipt, 3L)
  assert_eq(row(p, "A").buckets[2].projected, 5L)
}

///|
test "safety stock is an end-of-bucket floor, not repeated demand" {
  let p = @moon-mrp.plan(
    request([item("A", stock=1L, safety=3L)], demands=[
      movement("d", "A", 2, 1L),
    ]),
  ).unwrap()
  assert_eq(row(p, "A").buckets[0].planned_receipt, 2L)
  assert_eq(row(p, "A").buckets[1].planned_receipt, 0L)
  assert_eq(row(p, "A").buckets[2].planned_receipt, 1L)
  for b in row(p, "A").buckets {
    assert_eq(b.projected, 3L)
  }
}

///|
test "minimum and multiple policies have independently enumerated minima" {
  for n in 0..<=80 {
    for m in 1..<=13 {
      for minimum in [0, 1, 7, 23] {
        let rule : @moon-mrp.LotRule = if minimum == 0 {
          Multiple(m.to_int64())
        } else {
          MinimumMultiple(minimum.to_int64(), m.to_int64())
        }
        let mut oracle = 0L
        if n > 0 {
          while oracle < n.to_int64() || oracle < minimum.to_int64() {
            oracle += m.to_int64()
          }
        }
        assert_eq(@moon-mrp.order_quantity(n.to_int64(), rule).unwrap(), oracle)
      }
    }
  }
}

///|
test "inventory conservation and minimal lot size over 256 independent calendars" {
  for calendar in 0..<256 {
    let ds : Array[@moon-mrp.Movement] = []
    for t in 0..<4 {
      let q = (calendar >> (t * 2)) & 3
      if q > 0 {
        ds.push(movement(t.to_string(), "A", t, q.to_int64()))
      }
    }
    let p = @moon-mrp.plan(
      request(
        [item("A", stock=2L, safety=1L, lot=Multiple(3L))],
        demands=ds,
        horizon=4,
      ),
    ).unwrap()
    let mut inventory = 2L
    for b in row(p, "A").buckets {
      let mut oracle_order = 0L
      while inventory + oracle_order - b.gross < 1L {
        oracle_order += 3L
      }
      inventory = inventory + oracle_order - b.gross
      assert_eq(b.planned_receipt, oracle_order)
      assert_eq(b.projected, inventory)
    }
  }
}

///|
test "order releases are shifted and feed component gross at release time" {
  let p = @moon-mrp.plan(
    request(
      [item("P", lead=2), item("C", lead=1)],
      demands=[movement("d", "P", 5, 4L)],
      bom=[{ parent: "P", child: "C", units_per: 2L, }],
    ),
  ).unwrap()
  assert_eq(row(p, "P").buckets[3].planned_release, 4L)
  assert_eq(row(p, "C").buckets[3].gross, 8L)
  assert_eq(row(p, "C").buckets[2].planned_release, 8L)
}

///|
test "early parent and early component releases reject entire plan" {
  assert_eq(
    @moon-mrp.plan(
      request([item("A", lead=2)], demands=[movement("d", "A", 1, 1L)]),
    ).unwrap_err(),
    @moon-mrp.BeforeHorizon("A", 1, -1),
  )
  assert_eq(
    @moon-mrp.plan(
      request(
        [item("P", lead=2), item("C", lead=2)],
        demands=[movement("d", "P", 3, 1L)],
        bom=[{ parent: "P", child: "C", units_per: 1L, }],
      ),
    ).unwrap_err(),
    @moon-mrp.BeforeHorizon("C", 1, -1),
  )
}

///|
test "full graph validation catches unused cycles and blocked descendants" {
  let r = request([item("A"), item("B"), item("C")], bom=[
    { parent: "A", child: "B", units_per: 1L, },
    { parent: "B", child: "A", units_per: 1L, },
    { parent: "B", child: "C", units_per: 1L, },
  ])
  assert_eq(@moon-mrp.plan(r).unwrap_err(), @moon-mrp.Cycle(["A", "B", "C"]))
}

///|
test "input permutation gives identical plans and preserves caller arrays" {
  let a = item("A")
  let z = item("Z")
  let d1 = movement("d1", "Z", 3, 2L)
  let d2 = movement("d2", "A", 3, 1L)
  let first = request([z, a], demands=[d2, d1], bom=[
    { parent: "Z", child: "A", units_per: 2L, },
  ])
  let second = request([a, z], demands=[d1, d2], bom=first.bom)
  assert_eq(@moon-mrp.plan(first).unwrap(), @moon-mrp.plan(second).unwrap())
  assert_eq(first.items[0].sku, "Z")
  assert_eq(first.demands[0].id, "d2")
}

///|
test "invalid and duplicate item identities are rejected" {
  assert_eq(
    @moon-mrp.plan(request([item("")])).unwrap_err(),
    @moon-mrp.InvalidItem(""),
  )
  assert_eq(
    @moon-mrp.plan(request([item("A"), item("A")])).unwrap_err(),
    @moon-mrp.DuplicateItem("A"),
  )
  assert_eq(
    @moon-mrp.plan(request([item("A", stock=-1L)])).unwrap_err(),
    @moon-mrp.InvalidItem("A"),
  )
  assert_eq(
    @moon-mrp.plan(request([item("A", lot=Multiple(0L))])).unwrap_err(),
    @moon-mrp.InvalidItem("A"),
  )
}

///|
test "BOM references duplicate edges and self loops fail" {
  let edge : @moon-mrp.Component = { parent: "A", child: "B", units_per: 2L, }
  assert_eq(
    @moon-mrp.plan(request([item("A")], bom=[edge])).unwrap_err(),
    @moon-mrp.UnknownItem("B"),
  )
  assert_eq(
    @moon-mrp.plan(request([item("A"), item("B")], bom=[edge, edge])).unwrap_err(),
    @moon-mrp.DuplicateComponent("A", "B"),
  )
  assert_eq(
    @moon-mrp.plan(
      request([item("A")], bom=[{ parent: "A", child: "A", units_per: 1L, }]),
    ).unwrap_err(),
    @moon-mrp.InvalidComponent("A", "A"),
  )
}

///|
test "movement validation is global and includes duplicates" {
  let d = movement("d", "A", 1, 2L)
  assert_eq(
    @moon-mrp.plan(request([item("A")], demands=[d, d])).unwrap_err(),
    @moon-mrp.DuplicateMovement("d"),
  )
  assert_eq(
    @moon-mrp.plan(request([item("A")], receipts=[movement("r", "A", 6, 1L)])).unwrap_err(),
    @moon-mrp.InvalidMovement("r"),
  )
  assert_eq(
    @moon-mrp.plan(request([item("A")], demands=[movement("d", "B", 1, 1L)])).unwrap_err(),
    @moon-mrp.UnknownItem("B"),
  )
  assert_eq(
    @moon-mrp.plan(request([item("A")], demands=[movement("d", "A", 1, 0L)])).unwrap_err(),
    @moon-mrp.InvalidMovement("d"),
  )
}

///|
test "quantity overflow is detected before BOM multiplication" {
  let r = request(
    [item("A"), item("B")],
    demands=[movement("d", "A", 1, 1000000000000L)],
    bom=[{ parent: "A", child: "B", units_per: 1000000000L, }],
  )
  assert_eq(@moon-mrp.plan(r).unwrap_err(), @moon-mrp.QuantityLimit("B"))
  assert_true(
    @moon-mrp.order_quantity(1000000000000L, Multiple(999999999L)) is Err(_),
  )
}

///|
test "quantity addition caps and exact upper bound are enforced" {
  let p = @moon-mrp.plan(
    request([item("A")], demands=[movement("a", "A", 1, 1000000000000L)]),
  ).unwrap()
  assert_eq(row(p, "A").buckets[1].planned_receipt, 1000000000000L)
  assert_eq(
    @moon-mrp.plan(
      request([item("A")], demands=[
        movement("a", "A", 1, 1000000000000L),
        movement("b", "A", 1, 1L),
      ]),
    ).unwrap_err(),
    @moon-mrp.QuantityLimit("A"),
  )
}

///|
test "empty demand is supported but empty models and bad horizons are not" {
  assert_eq(@moon-mrp.plan(request([item("A")])).unwrap().orders, [])
  assert_eq(@moon-mrp.plan(request([])).unwrap_err(), @moon-mrp.SizeLimit)
  assert_eq(
    @moon-mrp.plan(request([item("A")], horizon=0)).unwrap_err(),
    @moon-mrp.InvalidHorizon,
  )
  assert_eq(
    @moon-mrp.plan(request([item("A")], horizon=129)).unwrap_err(),
    @moon-mrp.InvalidHorizon,
  )
}

///|
test "JSON export preserves integer quantities and escapes identifiers" {
  let p = @moon-mrp.plan(
    request([item("A\"\\\n")], demands=[
      movement("d", "A\"\\\n", 1, 1000000000000L),
    ]),
  ).unwrap()
  let json = p.to_json()
  assert_true(json.stringify().contains("1000000000000"))
  assert_eq(field(json, "schema"), Json("moon-mrp.plan.v1"))
  let orders = match field(json, "orders") {
    Array(a) => a
    _ => abort("array expected")
  }
  assert_eq(field(orders[0], "quantity"), Json("1000000000000"))
  assert_eq(field(orders[0], "item"), Json("A\"\\\n"))
}

///|
fn field(json : Json, key : String) -> Json {
  match json {
    Object(m) => m.get(key).unwrap()
    _ => abort("object expected")
  }
}
