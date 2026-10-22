///|
test "fractional usage is kept in thousandths" {
  let p = @moon-mrp.plan(
    request(
      [item("P"), item("C")],
      demands=[movement("d", "P", 0, q(4))],
      bom=[
        {
          parent: "P",
          child: "C",
          units_per: qm(250L),
          usage_unit: "",
          scrap_per_mille: 0,
        },
      ],
      horizon=1,
    ),
  ).unwrap()
  assert_eq(row(p, "C").buckets[0].gross, q(1))
  assert_eq(row(p, "C").buckets[0].gross.to_string(), "1")
}

///|
test "scrap pads every component disposition and rounds up" {
  let p = @moon-mrp.plan(
    request(
      [item("P"), item("C")],
      demands=[movement("d", "P", 0, q(10))],
      bom=[
        {
          parent: "P",
          child: "C",
          units_per: q(2),
          usage_unit: "",
          scrap_per_mille: 100,
        },
      ],
      horizon=1,
    ),
  ).unwrap()
  assert_eq(row(p, "C").buckets[0].gross, q(22))
}

///|
test "yield inflates the order and only the usable part reaches stock" {
  let p = @moon-mrp.plan(
    request(
      [item("A", yield_rate=900)],
      demands=[movement("d", "A", 1, q(10))],
      horizon=2,
    ),
  ).unwrap()
  let bucket = row(p, "A").buckets[1]
  assert_eq(bucket.net, q(10))
  assert_eq(bucket.planned_receipt, qm(11112L))
  assert_eq(bucket.received, q(10))
  assert_eq(bucket.projected, @moon-mrp.Qty::zero())
}

///|
test "unit conversion turns grams into kilograms" {
  let p = @moon-mrp.plan(
    request(
      [item("P"), item("C", unit="KG")],
      demands=[movement("d", "P", 0, q(4))],
      bom=[
        {
          parent: "P",
          child: "C",
          units_per: q(500),
          usage_unit: "G",
          scrap_per_mille: 0,
        },
      ],
      conversions=[{ from: "G", to: "KG", factor: qm(1L), }],
      horizon=1,
    ),
  ).unwrap()
  assert_eq(row(p, "C").buckets[0].gross, q(2))
}

///|
test "a missing unit conversion is an error, not a silent guess" {
  let r = request(
    [item("P"), item("C", unit="KG")],
    demands=[movement("d", "P", 0, q(4))],
    bom=[
      {
        parent: "P",
        child: "C",
        units_per: q(500),
        usage_unit: "G",
        scrap_per_mille: 0,
      },
    ],
    horizon=1,
  )
  assert_eq(
    @moon-mrp.plan(r).unwrap_err(),
    @moon-mrp.InvalidConversion("G", "KG"),
  )
}

///|
test "period order covers several buckets with a single order" {
  let p = @moon-mrp.plan(
    request(
      [item("A", lot=@moon-mrp.PeriodOrder(3))],
      demands=[movement("d1", "A", 1, q(10)), movement("d2", "A", 2, q(5))],
      horizon=4,
    ),
  ).unwrap()
  assert_eq(row(p, "A").buckets[1].planned_receipt, q(15))
  assert_eq(row(p, "A").buckets[2].planned_receipt, @moon-mrp.Qty::zero())
  assert_eq(row(p, "A").buckets[1].projected, q(5))
  assert_eq(row(p, "A").buckets[2].projected, @moon-mrp.Qty::zero())
}

///|
test "min-max replenishes up to the maximum" {
  let p = @moon-mrp.plan(
    request(
      [item("A", stock=q(10), lot=@moon-mrp.MinMax(q(5), q(20)))],
      demands=[movement("d", "A", 1, q(8))],
      horizon=2,
    ),
  ).unwrap()
  assert_eq(row(p, "A").buckets[1].planned_receipt, q(18))
  assert_eq(row(p, "A").buckets[1].projected, q(20))
}

///|
test "late releases are clamped and reported under the allow-late policy" {
  let p = @moon-mrp.plan(
    request(
      [item("A", lead=2)],
      demands=[movement("d", "A", 1, q(5))],
      policy=@moon-mrp.AllowLate,
    ),
  ).unwrap()
  assert_eq(p.orders.length(), 1)
  assert_eq(p.orders[0].release_bucket, 0)
  assert_eq(p.orders[0].receipt_bucket, 1)
  assert_true(p.orders[0].late)
  assert_eq(row(p, "A").buckets[0].planned_release, q(5))
  assert_eq(p.incidents.length(), 1)
  assert_eq(p.incidents[0], {
    item: "A",
    receipt_bucket: 1,
    required_release: -1,
    actual_release: 0,
  })
}

///|
test "the strict policy still rejects the same release" {
  assert_eq(
    @moon-mrp.plan(
      request([item("A", lead=2)], demands=[movement("d", "A", 1, q(5))]),
    ).unwrap_err(),
    @moon-mrp.BeforeHorizon("A", 1, -1),
  )
}

///|
test "conservation holds with yield, scrap and unit conversion" {
  let p = @moon-mrp.plan(
    request(
      [item("P", yield_rate=950), item("C", unit="KG")],
      demands=[movement("d", "P", 1, q(8))],
      bom=[
        {
          parent: "P",
          child: "C",
          units_per: qm(2500L),
          usage_unit: "",
          scrap_per_mille: 200,
        },
      ],
      horizon=4,
    ),
  ).unwrap()
  assert_eq(row(p, "P").buckets[1].planned_receipt, qm(8422L))
  assert_eq(row(p, "P").buckets[1].received, q(8))
  assert_eq(row(p, "C").buckets[1].gross, qm(25268L))
  for ip in p.items {
    let mut balance = @moon-mrp.Qty::zero()
    for bucket in ip.buckets {
      balance = balance
        .add(bucket.scheduled)
        .add(bucket.received)
        .sub(bucket.gross)
      assert_eq(balance, bucket.projected)
    }
  }
}

///|
test "pegs always sum to the bucket gross requirement" {
  let p = @moon-mrp.plan(
    request(
      [item("P"), item("C")],
      demands=[movement("d", "P", 1, q(7))],
      bom=[
        {
          parent: "P",
          child: "C",
          units_per: q(3),
          usage_unit: "",
          scrap_per_mille: 500,
        },
      ],
      horizon=3,
    ),
  ).unwrap()
  for ip in p.items {
    for bucket in ip.buckets {
      let mut sum = @moon-mrp.Qty::zero()
      for peg in p.pegs {
        if peg.item == ip.item && peg.bucket == bucket.index {
          sum = sum.add(peg.quantity)
        }
      }
      assert_eq(sum, bucket.gross)
    }
  }
}

///|
test "single-level planning matches an independent simulation" {
  for demand in [0, 1, 3, 7, 12, 30] {
    for stock in [0, 2, 5] {
      for safety in [0, 1, 4] {
        for yield_rate in [1000, 900, 700] {
          for multiple in [1, 5] {
            let demands : Array[@moon-mrp.Movement] = []
            if demand > 0 {
              demands.push(movement("d", "A", 2, q(demand)))
            }
            let p = @moon-mrp.plan(
              request(
                [
                  item(
                    "A",
                    stock=q(stock),
                    safety=q(safety),
                    yield_rate~,
                    lot=@moon-mrp.Multiple(q(multiple)),
                  ),
                ],
                demands~,
                horizon=3,
              ),
            ).unwrap()
            let mut inventory = stock.to_int64() * 1000L
            for bucket in row(p, "A").buckets {
              let available = inventory
              let needed = bucket.gross.milli + safety.to_int64() * 1000L
              let net = if needed > available { needed - available } else { 0L }
              let mut start = if net > 0L {
                (net * 1000L + yield_rate.to_int64() - 1L) /
                yield_rate.to_int64()
              } else {
                0L
              }
              if start > 0L {
                let batch = multiple.to_int64() * 1000L
                start = (start + batch - 1L) / batch * batch
              }
              let received = start * yield_rate.to_int64() / 1000L
              inventory = available + received - bucket.gross.milli
              assert_eq(bucket.net.milli, net)
              assert_eq(bucket.planned_receipt.milli, start)
              assert_eq(bucket.received.milli, received)
              assert_eq(bucket.projected.milli, inventory)
            }
          }
        }
      }
    }
  }
}

///|
test "quantities print as plain decimals" {
  assert_eq(q(2).to_string(), "2")
  assert_eq(qm(250L).to_string(), "0.25")
  assert_eq(qm(1500L).to_string(), "1.5")
  assert_eq(qm(1005L).to_string(), "1.005")
  assert_eq(qm(-250L).to_string(), "-0.25")
  assert_eq(qm(0L).to_string(), "0")
}
