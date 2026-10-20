///|
fn item(
  sku : String,
  stock? : Int64 = 0L,
  safety? : Int64 = 0L,
  lead? : Int = 0,
  lot? : @mrp.LotRule = LotForLot,
) -> @mrp.Item {
  { sku, on_hand: stock, safety_stock: safety, lead_time: lead, lot, }
}

///|
fn demand(
  id : String,
  item : String,
  bucket : Int,
  quantity : Int64,
) -> @mrp.Movement {
  { id, item, bucket, quantity, }
}

///|
fn show(label : String, p : @mrp.Plan) -> Unit {
  println(label)
  for o in p.orders {
    println(
      "  \{o.item}: quantity=\{o.quantity}; release=\{o.release_bucket}; receipt=\{o.receipt_bucket}",
    )
  }
}

///|
fn main {
  let assembly : @mrp.Request = {
    horizon: 6,
    items: [
      item("KIT", stock=1L, lead=1, lot=Multiple(5L)),
      item("MODULE", stock=4L, lead=2, lot=Multiple(4L)),
      item("RAW", stock=5L, lead=1),
    ],
    bom: [
      { parent: "KIT", child: "MODULE", units_per: 2L, },
      { parent: "MODULE", child: "RAW", units_per: 3L, },
      { parent: "KIT", child: "RAW", units_per: 1L, },
    ],
    demands: [demand("sales", "KIT", 5, 9L), demand("spares", "MODULE", 4, 3L)],
    receipts: [demand("open-po", "MODULE", 4, 5L)],
  }
  let plan = @mrp.plan(assembly).unwrap()
  show("1 assembly and shared raw material", plan)
  let retail : @mrp.Request = {
    horizon: 4,
    items: [item("LABEL", stock=3L, safety=2L, lot=MinimumMultiple(10L, 4L))],
    bom: [],
    demands: [demand("day1", "LABEL", 1, 9L), demand("day2", "LABEL", 2, 3L)],
    receipts: [demand("incoming", "LABEL", 1, 2L)],
  }
  show(
    "2 replenishment with minimum order and safety stock",
    @mrp.plan(retail).unwrap(),
  )
  let repair : @mrp.Request = {
    horizon: 4,
    items: [item("PART", stock=2L, lead=1)],
    bom: [],
    demands: [demand("repair", "PART", 3, 8L)],
    receipts: [],
  }
  show("3 before supplier confirmation", @mrp.plan(repair).unwrap())
  show(
    "3 after supplier confirmation",
    @mrp.plan({ ..repair, receipts: [demand("confirmed", "PART", 2, 3L)], }).unwrap(),
  )
  let invalid = { ..repair, demands: [demand("urgent", "PART", 0, 3L)], }
  println("early release rejected=\{@mrp.plan(invalid) is Err(_)}")
  let cycle = {
    ..repair,
    items: [item("A"), item("B")],
    demands: [],
    bom: [
      { parent: "A", child: "B", units_per: 1L, },
      { parent: "B", child: "A", units_per: 1L, },
    ],
  }
  println("cycle rejected=\{@mrp.plan(cycle) is Err(_)}")
  println("assembly JSON")
  println(plan.to_json().stringify())
}
