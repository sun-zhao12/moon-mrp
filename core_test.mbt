///|
fn q(units : Int) -> @moon-mrp.Qty {
  @moon-mrp.Qty::int(units)
}

///|
fn qm(milli : Int64) -> @moon-mrp.Qty {
  @moon-mrp.Qty::milli(milli)
}

///|
fn item(
  sku : String,
  stock? : @moon-mrp.Qty = @moon-mrp.Qty::zero(),
  safety? : @moon-mrp.Qty = @moon-mrp.Qty::zero(),
  lead? : Int = 0,
  yield_rate? : Int = 1000,
  lot? : @moon-mrp.LotRule = @moon-mrp.LotForLot,
  unit? : String = "",
) -> @moon-mrp.Item {
  {
    sku,
    unit,
    on_hand: stock,
    safety_stock: safety,
    lead_time: lead,
    yield_per_mille: yield_rate,
    lot,
  }
}

///|
fn movement(
  id : String,
  sku : String,
  t : Int,
  quantity : @moon-mrp.Qty,
) -> @moon-mrp.Movement {
  { id, item: sku, bucket: t, quantity, }
}

///|
fn request(
  items : Array[@moon-mrp.Item],
  demands? : Array[@moon-mrp.Movement] = [],
  receipts? : Array[@moon-mrp.Movement] = [],
  bom? : Array[@moon-mrp.Component] = [],
  horizon? : Int = 6,
  conversions? : Array[@moon-mrp.UnitConversion] = [],
  policy? : @moon-mrp.ReleasePolicy = @moon-mrp.Strict,
) -> @moon-mrp.Request {
  { horizon, items, bom, demands, receipts, conversions, policy, }
}

///|
fn row(p : @moon-mrp.Plan, sku : String) -> @moon-mrp.ItemPlan {
  p.items.filter(fn(ip) { ip.item == sku })[0]
}

///|
fn field(json : Json, key : String) -> Json {
  match json {
    Object(m) => m.get(key).unwrap()
    _ => abort("object expected")
  }
}

///|
test "multilevel shared components are netted after every parent is exploded" {
  let r = request(
    [
      item("K", stock=q(1), lead=1, lot=@moon-mrp.Multiple(q(5))),
      item("A", stock=q(4), lead=2, lot=@moon-mrp.Multiple(q(4))),
      item("R", stock=q(5), lead=1),
    ],
    demands=[movement("sale", "K", 5, q(9)), movement("spare", "A", 4, q(3))],
    receipts=[movement("open", "A", 4, q(5))],
    bom=[
      {
        parent: "K",
        child: "A",
        units_per: q(2),
        usage_unit: "",
        scrap_per_mille: 0,
      },
      {
        parent: "A",
        child: "R",
        units_per: q(3),
        usage_unit: "",
        scrap_per_mille: 0,
      },
      {
        parent: "K",
        child: "R",
        units_per: q(1),
        usage_unit: "",
        scrap_per_mille: 0,
      },
    ],
  )
  let p = @moon-mrp.plan(r).unwrap()
  assert_eq(row(p, "K").buckets[5].planned_receipt, q(10))
  assert_eq(row(p, "A").buckets[4].gross, q(23))
  assert_eq(row(p, "A").buckets[4].net, q(14))
  assert_eq(row(p, "A").buckets[4].planned_receipt, q(16))
  assert_eq(row(p, "R").buckets[2].gross, q(48))
  assert_eq(row(p, "R").buckets[4].gross, q(10))
  assert_eq(row(p, "R").buckets[2].planned_receipt, q(43))
  assert_eq(row(p, "R").buckets[4].planned_receipt, q(10))
  assert_eq(p.orders.length(), 4)
  for ip in p.items {
    for b in ip.buckets {
      let mut pegged = @moon-mrp.Qty::zero()
      for peg in p.pegs {
        if peg.item == ip.item && peg.bucket == b.index {
          pegged = pegged.add(peg.quantity)
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
      [item("P", stock=q(4)), item("C")],
      demands=[movement("d", "P", 2, q(9))],
      receipts=[movement("r", "P", 2, q(5))],
      bom=[
        {
          parent: "P",
          child: "C",
          units_per: q(100),
          usage_unit: "",
          scrap_per_mille: 0,
        },
      ],
    ),
  ).unwrap()
  assert_eq(p.orders, [])
  assert_eq(row(p, "C").buckets[2].gross, @moon-mrp.Qty::zero())
}

///|
test "receipts are usable in their bucket and never borrowed from future" {
  let p = @moon-mrp.plan(
    request([item("A")], demands=[movement("d", "A", 1, q(3))], receipts=[
      movement("r", "A", 2, q(5)),
    ]),
  ).unwrap()
  assert_eq(row(p, "A").buckets[1].planned_receipt, q(3))
  assert_eq(row(p, "A").buckets[2].projected, q(5))
}

///|
test "safety stock is an end-of-bucket floor, not repeated demand" {
  let p = @moon-mrp.plan(
    request([item("A", stock=q(1), safety=q(3))], demands=[
      movement("d", "A", 2, q(1)),
    ]),
  ).unwrap()
  assert_eq(row(p, "A").buckets[0].planned_receipt, q(2))
  assert_eq(row(p, "A").buckets[1].planned_receipt, @moon-mrp.Qty::zero())
  assert_eq(row(p, "A").buckets[2].planned_receipt, q(1))
  for b in row(p, "A").buckets {
    assert_eq(b.projected, q(3))
  }
}

///|
test "minimum and multiple policies have independently enumerated minima" {
  for n in 0..<=80 {
    for m in 1..<=13 {
      for minimum in [0, 1, 7, 23] {
        let rule : @moon-mrp.LotRule = if minimum == 0 {
          @moon-mrp.Multiple(q(m))
        } else {
          @moon-mrp.MinimumMultiple(q(minimum), q(m))
        }
        let mut oracle = 0
        if n > 0 {
          while oracle < n || oracle < minimum {
            oracle += m
          }
        }
        assert_eq(@moon-mrp.order_quantity(q(n), rule).unwrap(), q(oracle))
      }
    }
  }
}

///|
test "inventory conservation and minimal lot size over 256 independent calendars" {
  for calendar in 0..<256 {
    let demands : Array[@moon-mrp.Movement] = []
    for t in 0..<4 {
      let amount = (calendar >> (t * 2)) & 3
      if amount > 0 {
        demands.push(movement(t.to_string(), "A", t, q(amount)))
      }
    }
    let p = @moon-mrp.plan(
      request(
        [item("A", stock=q(2), safety=q(1), lot=@moon-mrp.Multiple(q(3)))],
        demands~,
        horizon=4,
      ),
    ).unwrap()
    let mut inventory = 2000L
    for b in row(p, "A").buckets {
      let mut oracle_order = 0L
      while inventory + oracle_order - b.gross.milli < 1000L {
        oracle_order += 3000L
      }
      inventory = inventory + oracle_order - b.gross.milli
      assert_eq(b.planned_receipt.milli, oracle_order)
      assert_eq(b.projected.milli, inventory)
    }
  }
}

///|
test "order releases are shifted and feed component gross at release time" {
  let p = @moon-mrp.plan(
    request(
      [item("P", lead=2), item("C", lead=1)],
      demands=[movement("d", "P", 5, q(4))],
      bom=[
        {
          parent: "P",
          child: "C",
          units_per: q(2),
          usage_unit: "",
          scrap_per_mille: 0,
        },
      ],
    ),
  ).unwrap()
  assert_eq(row(p, "P").buckets[3].planned_release, q(4))
  assert_eq(row(p, "C").buckets[3].gross, q(8))
  assert_eq(row(p, "C").buckets[2].planned_release, q(8))
}

///|
test "early releases reject the plan under the strict policy" {
  assert_eq(
    @moon-mrp.plan(
      request([item("A", lead=2)], demands=[movement("d", "A", 1, q(1))]),
    ).unwrap_err(),
    @moon-mrp.BeforeHorizon("A", 1, -1),
  )
  assert_eq(
    @moon-mrp.plan(
      request(
        [item("P", lead=2), item("C", lead=2)],
        demands=[movement("d", "P", 3, q(1))],
        bom=[
          {
            parent: "P",
            child: "C",
            units_per: q(1),
            usage_unit: "",
            scrap_per_mille: 0,
          },
        ],
      ),
    ).unwrap_err(),
    @moon-mrp.BeforeHorizon("C", 1, -1),
  )
}

///|
test "full graph validation catches unused cycles and blocked descendants" {
  let r = request([item("A"), item("B"), item("C")], bom=[
    {
      parent: "A",
      child: "B",
      units_per: q(1),
      usage_unit: "",
      scrap_per_mille: 0,
    },
    {
      parent: "B",
      child: "A",
      units_per: q(1),
      usage_unit: "",
      scrap_per_mille: 0,
    },
    {
      parent: "B",
      child: "C",
      units_per: q(1),
      usage_unit: "",
      scrap_per_mille: 0,
    },
  ])
  assert_eq(@moon-mrp.plan(r).unwrap_err(), @moon-mrp.Cycle(["A", "B", "C"]))
}

///|
test "input permutation gives identical plans and preserves caller arrays" {
  let a = item("A")
  let z = item("Z")
  let d1 = movement("d1", "Z", 3, q(2))
  let d2 = movement("d2", "A", 3, q(1))
  let first = request([z, a], demands=[d2, d1], bom=[
    {
      parent: "Z",
      child: "A",
      units_per: q(2),
      usage_unit: "",
      scrap_per_mille: 0,
    },
  ])
  let second = request([a, z], demands=[d1, d2], bom=[
    {
      parent: "Z",
      child: "A",
      units_per: q(2),
      usage_unit: "",
      scrap_per_mille: 0,
    },
  ])
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
    @moon-mrp.plan(request([item("A", stock=qm(-1L))])).unwrap_err(),
    @moon-mrp.InvalidItem("A"),
  )
  assert_eq(
    @moon-mrp.plan(
      request([item("A", lot=@moon-mrp.Multiple(@moon-mrp.Qty::zero()))]),
    ).unwrap_err(),
    @moon-mrp.InvalidItem("A"),
  )
  assert_eq(
    @moon-mrp.plan(request([item("A", yield_rate=0)])).unwrap_err(),
    @moon-mrp.InvalidItem("A"),
  )
  assert_eq(
    @moon-mrp.plan(request([item("A", yield_rate=1001)])).unwrap_err(),
    @moon-mrp.InvalidItem("A"),
  )
}

///|
test "BOM references duplicate edges and self loops fail" {
  let edge : @moon-mrp.Component = {
    parent: "A",
    child: "B",
    units_per: q(2),
    usage_unit: "",
    scrap_per_mille: 0,
  }
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
      request([item("A")], bom=[
        {
          parent: "A",
          child: "A",
          units_per: q(1),
          usage_unit: "",
          scrap_per_mille: 0,
        },
      ]),
    ).unwrap_err(),
    @moon-mrp.InvalidComponent("A", "A"),
  )
  assert_eq(
    @moon-mrp.plan(
      request([item("A"), item("B")], bom=[
        {
          parent: "A",
          child: "B",
          units_per: q(1),
          usage_unit: "",
          scrap_per_mille: 1001,
        },
      ]),
    ).unwrap_err(),
    @moon-mrp.InvalidComponent("A", "B"),
  )
}

///|
test "movement validation is global and includes duplicates" {
  let d = movement("d", "A", 1, q(2))
  assert_eq(
    @moon-mrp.plan(request([item("A")], demands=[d, d])).unwrap_err(),
    @moon-mrp.DuplicateMovement("d"),
  )
  assert_eq(
    @moon-mrp.plan(request([item("A")], receipts=[movement("r", "A", 6, q(1))])).unwrap_err(),
    @moon-mrp.InvalidMovement("r"),
  )
  assert_eq(
    @moon-mrp.plan(request([item("A")], demands=[movement("d", "B", 1, q(1))])).unwrap_err(),
    @moon-mrp.UnknownItem("B"),
  )
  assert_eq(
    @moon-mrp.plan(
      request([item("A")], demands=[
        movement("d", "A", 1, @moon-mrp.Qty::zero()),
      ]),
    ).unwrap_err(),
    @moon-mrp.InvalidMovement("d"),
  )
}

///|
test "quantity overflow is detected before BOM multiplication" {
  let r = request(
    [item("A"), item("B")],
    demands=[movement("d", "A", 1, qm(1000000000000000L))],
    bom=[
      {
        parent: "A",
        child: "B",
        units_per: qm(1000000000000000L),
        usage_unit: "",
        scrap_per_mille: 0,
      },
    ],
  )
  assert_eq(@moon-mrp.plan(r).unwrap_err(), @moon-mrp.QuantityLimit("B"))
  assert_true(
    @moon-mrp.order_quantity(
      qm(1000000000000000L),
      @moon-mrp.Multiple(qm(999999999000L)),
    )
    is Err(_),
  )
}

///|
test "quantity addition caps and exact upper bound are enforced" {
  let p = @moon-mrp.plan(
    request([item("A")], demands=[movement("a", "A", 1, qm(1000000000000000L))]),
  ).unwrap()
  assert_eq(row(p, "A").buckets[1].planned_receipt, qm(1000000000000000L))
  assert_eq(
    @moon-mrp.plan(
      request([item("A")], demands=[
        movement("a", "A", 1, qm(1000000000000000L)),
        movement("b", "A", 1, qm(1L)),
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
    @moon-mrp.plan(request([item("A")], horizon=1025)).unwrap_err(),
    @moon-mrp.InvalidHorizon,
  )
}

///|
test "JSON export preserves decimals and escapes identifiers" {
  let p = @moon-mrp.plan(
    request([item("A\"\\\n")], demands=[
      movement("d", "A\"\\\n", 1, qm(1000000000000000L)),
    ]),
  ).unwrap()
  let json = p.to_json()
  assert_true(json.stringify().contains("1000000000000"))
  assert_eq(field(json, "schema"), Json("moon-mrp.plan.v2"))
  let orders = match field(json, "orders") {
    Array(a) => a
    _ => abort("array expected")
  }
  assert_eq(field(orders[0], "quantity"), Json("1000000000000"))
  assert_eq(field(orders[0], "item"), Json("A\"\\\n"))
}
