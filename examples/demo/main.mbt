///|
fn q(units : Int) -> @mrp.Qty {
  @mrp.Qty::int(units)
}

///|
fn qm(milli : Int64) -> @mrp.Qty {
  @mrp.Qty::milli(milli)
}

///|
fn item(
  sku : String,
  stock? : @mrp.Qty = @mrp.Qty::zero(),
  safety? : @mrp.Qty = @mrp.Qty::zero(),
  lead? : Int = 0,
  yield_rate? : Int = 1000,
  lot? : @mrp.LotRule = @mrp.LotForLot,
  unit? : String = "",
) -> @mrp.Item {
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
fn demand(
  id : String,
  item : String,
  bucket : Int,
  quantity : @mrp.Qty,
) -> @mrp.Movement {
  { id, item, bucket, quantity, }
}

///|
fn show(label : String, p : @mrp.Plan) -> Unit {
  println(label)
  for o in p.orders {
    println(
      "  " +
      o.item +
      ": quantity=" +
      o.quantity.to_string() +
      "; release=" +
      o.release_bucket.to_string() +
      "; receipt=" +
      o.receipt_bucket.to_string() +
      (if o.late { "; late" } else { "" }),
    )
  }
}

///|
fn main {
  let assembly : @mrp.Request = {
    horizon: 6,
    items: [
      item("KIT", stock=q(1), lead=1, lot=@mrp.Multiple(q(5))),
      item("MODULE", stock=q(4), lead=2, lot=@mrp.Multiple(q(4))),
      item("RAW", stock=q(5), lead=1),
    ],
    bom: [
      {
        parent: "KIT",
        child: "MODULE",
        units_per: q(2),
        usage_unit: "",
        scrap_per_mille: 0,
      },
      {
        parent: "MODULE",
        child: "RAW",
        units_per: q(3),
        usage_unit: "",
        scrap_per_mille: 0,
      },
      {
        parent: "KIT",
        child: "RAW",
        units_per: q(1),
        usage_unit: "",
        scrap_per_mille: 0,
      },
    ],
    demands: [
      demand("sales", "KIT", 5, q(9)),
      demand("spares", "MODULE", 4, q(3)),
    ],
    receipts: [demand("open-po", "MODULE", 4, q(5))],
    conversions: [],
    policy: @mrp.Strict,
  }
  let plan = @mrp.plan(assembly).unwrap()
  show("1 assembly and shared raw material", plan)

  let retail : @mrp.Request = {
    horizon: 4,
    items: [
      item(
        "LABEL",
        stock=q(3),
        safety=q(2),
        lot=@mrp.MinimumMultiple(q(10), q(4)),
      ),
    ],
    bom: [],
    demands: [
      demand("day1", "LABEL", 1, q(9)),
      demand("day2", "LABEL", 2, q(3)),
    ],
    receipts: [demand("incoming", "LABEL", 1, q(2))],
    conversions: [],
    policy: @mrp.Strict,
  }
  show(
    "2 replenishment with minimum order and safety stock",
    @mrp.plan(retail).unwrap(),
  )

  let repair : @mrp.Request = {
    horizon: 4,
    items: [item("PART", stock=q(2), lead=1)],
    bom: [],
    demands: [demand("repair", "PART", 3, q(8))],
    receipts: [],
    conversions: [],
    policy: @mrp.Strict,
  }
  show("3 before supplier confirmation", @mrp.plan(repair).unwrap())
  show(
    "3 after supplier confirmation",
    @mrp.plan({ ..repair, receipts: [demand("confirmed", "PART", 2, q(3))], }).unwrap(),
  )

  let coating : @mrp.Request = {
    horizon: 3,
    items: [item("PANEL", yield_rate=950), item("PAINT", unit="KG")],
    bom: [
      {
        parent: "PANEL",
        child: "PAINT",
        units_per: q(2500),
        usage_unit: "G",
        scrap_per_mille: 200,
      },
    ],
    demands: [demand("frame", "PANEL", 1, q(8))],
    receipts: [],
    conversions: [{ from: "G", to: "KG", factor: qm(1L), }],
    policy: @mrp.Strict,
  }
  let coated = @mrp.plan(coating).unwrap()
  show("4 yield, scrap, fractional usage and unit conversion", coated)
  println(
    "  PAINT gross=" + coated.items[0].buckets[1].gross.to_string() + " KG",
  )

  let urgent : @mrp.Request = {
    horizon: 4,
    items: [item("PART", stock=q(2), lead=2)],
    bom: [],
    demands: [demand("urgent", "PART", 1, q(5))],
    receipts: [],
    conversions: [],
    policy: @mrp.Strict,
  }
  println(
    "5 early release rejected under strict policy=" +
    (if @mrp.plan(urgent) is Err(_) { "true" } else { "false" }),
  )
  let relaxed = { ..urgent, policy: @mrp.AllowLate, }
  let late_plan = @mrp.plan(relaxed).unwrap()
  show("5 accepted under allow-late policy", late_plan)
  for incident in late_plan.incidents {
    println(
      "  incident: " +
      incident.item +
      " receipt=" +
      incident.receipt_bucket.to_string() +
      " required_release=" +
      incident.required_release.to_string() +
      " actual_release=" +
      incident.actual_release.to_string(),
    )
  }

  let cycle = {
    ..repair,
    items: [item("A"), item("B")],
    demands: [],
    bom: [
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
    ],
  }
  println(
    "cycle rejected=" +
    (if @mrp.plan(cycle) is Err(_) { "true" } else { "false" }),
  )
  println("assembly JSON")
  println(plan.to_json().stringify())
}
