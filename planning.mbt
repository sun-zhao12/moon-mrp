///|
let quantity_limit : Int64 = 1000000000000L

///|
fn valid_quantity(q : Int64) -> Bool {
  q >= 0L && q <= quantity_limit
}

///|
fn lot_valid(lot : LotRule) -> Bool {
  match lot {
    LotForLot => true
    Multiple(m) => m > 0L && m <= 1000000000L
    MinimumMultiple(minimum, m) =>
      minimum > 0L && minimum <= 1000000000L && m > 0L && m <= 1000000000L
  }
}

///|
/// Exact integer lot rounding; input and intermediate values are bounded.
pub fn order_quantity(
  net : Int64,
  lot : LotRule,
) -> Result[Int64, PlanningError] {
  if !valid_quantity(net) || !lot_valid(lot) {
    return Err(InvalidItem("lot or net quantity"))
  }
  if net == 0L {
    return Ok(0L)
  }
  let (minimum, multiple) = match lot {
    LotForLot => (0L, 1L)
    Multiple(m) => (0L, m)
    MinimumMultiple(n, m) => (n, m)
  }
  let target = if net > minimum { net } else { minimum }
  let count = target / multiple +
    (if target % multiple == 0L { 0L } else { 1L })
  let rounded = count * multiple
  if rounded > quantity_limit {
    Err(QuantityLimit("lot rounding"))
  } else {
    Ok(rounded)
  }
}

///|
fn validate_movements(
  movements : Array[Movement],
  index : Map[String, Int],
  horizon : Int,
) -> Result[Unit, PlanningError] {
  let ids : Map[String, Bool] = Map([])
  for m in movements {
    if m.id == "" ||
      m.bucket < 0 ||
      m.bucket >= horizon ||
      m.quantity <= 0L ||
      !valid_quantity(m.quantity) {
      return Err(InvalidMovement(m.id))
    }
    if !index.contains(m.item) {
      return Err(UnknownItem(m.item))
    }
    if ids.contains(m.id) {
      return Err(DuplicateMovement(m.id))
    }
    ids[m.id] = true
  }
  Ok(())
}

///| Validate the full graph, net parents before children, and peg each gross

///| requirement. A release before bucket zero rejects the entire calculation;

///|
/// no partial feasible plan is returned and no input is mutated.
pub fn plan(request : Request) -> Result[Plan, PlanningError] {
  let h = request.horizon
  if h < 1 || h > 128 {
    return Err(InvalidHorizon)
  }
  let n = request.items.length()
  if n == 0 ||
    n > 64 ||
    request.bom.length() > 4096 ||
    request.demands.length() > 10000 ||
    request.receipts.length() > 10000 {
    return Err(SizeLimit)
  }
  let items = request.items.copy()
  items.sort_by(fn(a, b) { a.sku.lexical_compare(b.sku) })
  let index : Map[String, Int] = Map([])
  for i, item in items {
    if item.sku == "" ||
      !valid_quantity(item.on_hand) ||
      !valid_quantity(item.safety_stock) ||
      item.lead_time < 0 ||
      item.lead_time > 127 ||
      !lot_valid(item.lot) {
      return Err(InvalidItem(item.sku))
    }
    if index.contains(item.sku) {
      return Err(DuplicateItem(item.sku))
    }
    index[item.sku] = i
  }
  match validate_movements(request.demands, index, h) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match validate_movements(request.receipts, index, h) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let bom = request.bom.copy()
  bom.sort_by(fn(a, b) {
    if a.parent == b.parent {
      a.child.lexical_compare(b.child)
    } else {
      a.parent.lexical_compare(b.parent)
    }
  })
  let indegree = Array::make(n, 0)
  let children : Array[Array[(Int, Int64)]] = Array::makei(n, fn(_) { [] })
  for i, edge in bom {
    if !index.contains(edge.parent) {
      return Err(UnknownItem(edge.parent))
    }
    if !index.contains(edge.child) {
      return Err(UnknownItem(edge.child))
    }
    if edge.parent == edge.child ||
      edge.units_per <= 0L ||
      edge.units_per > 1000000000L {
      return Err(InvalidComponent(edge.parent, edge.child))
    }
    if i > 0 &&
      bom[i - 1].parent == edge.parent &&
      bom[i - 1].child == edge.child {
      return Err(DuplicateComponent(edge.parent, edge.child))
    }
    let p = index[edge.parent]
    let c = index[edge.child]
    children[p].push((c, edge.units_per))
    indegree[c] += 1
  }
  let visited = Array::make(n, false)
  let order : Array[Int] = []
  for _ in 0..<n {
    let mut ready = -1
    for i in 0..<n {
      if !visited[i] && indegree[i] == 0 && ready == -1 {
        ready = i
      }
    }
    if ready == -1 {
      let blocked : Array[String] = []
      for i in 0..<n {
        if !visited[i] {
          blocked.push(items[i].sku)
        }
      }
      return Err(Cycle(blocked))
    }
    visited[ready] = true
    order.push(ready)
    for pair in children[ready] {
      indegree[pair.0] -= 1
    }
  }
  let gross : Array[Array[Int64]] = Array::makei(n, fn(_) { Array::make(h, 0L) })
  let scheduled : Array[Array[Int64]] = Array::makei(n, fn(_) {
    Array::make(h, 0L)
  })
  let pegs : Array[Peg] = []
  let demands = request.demands.copy()
  demands.sort_by(fn(a, b) { a.id.lexical_compare(b.id) })
  for d in demands {
    let i = index[d.item]
    let total = gross[i][d.bucket] + d.quantity
    if total > quantity_limit {
      return Err(QuantityLimit(d.item))
    }
    gross[i][d.bucket] = total
    pegs.push({
      item: d.item,
      bucket: d.bucket,
      quantity: d.quantity,
      source: Demand(d.id),
    })
  }
  for r in request.receipts {
    let i = index[r.item]
    let total = scheduled[i][r.bucket] + r.quantity
    if total > quantity_limit {
      return Err(QuantityLimit(r.item))
    }
    scheduled[i][r.bucket] = total
  }
  let plans : Array[ItemPlan] = []
  let orders : Array[Order] = []
  for i in order {
    let item = items[i]
    let releases = Array::make(h, 0L)
    let buckets : Array[Bucket] = []
    let mut available = item.on_hand
    for t in 0..<h {
      available += scheduled[i][t]
      let needed = gross[i][t] + item.safety_stock
      if available > quantity_limit || needed > quantity_limit {
        return Err(QuantityLimit(item.sku))
      }
      let net = if needed > available { needed - available } else { 0L }
      let replenishment = match order_quantity(net, item.lot) {
        Ok(q) => q
        Err(_) => return Err(QuantityLimit(item.sku))
      }
      if replenishment > 0L {
        let release = t - item.lead_time
        if release < 0 {
          return Err(BeforeHorizon(item.sku, t, release))
        }
        releases[release] = replenishment
        orders.push({
          item: item.sku,
          receipt_bucket: t,
          release_bucket: release,
          quantity: replenishment,
        })
        for (child, units) in children[i] {
          if replenishment > quantity_limit / units {
            return Err(QuantityLimit(items[child].sku))
          }
          let q = replenishment * units
          let total = gross[child][release] + q
          if total > quantity_limit {
            return Err(QuantityLimit(items[child].sku))
          }
          gross[child][release] = total
          pegs.push({
            item: items[child].sku,
            bucket: release,
            quantity: q,
            source: ParentOrder(item.sku, t),
          })
        }
      }
      // available+replenishment can be at most 2*quantity_limit, well within Int64.
      available = available + replenishment - gross[i][t]
      if available > quantity_limit {
        return Err(QuantityLimit(item.sku))
      }
      buckets.push({
        index: t,
        gross: gross[i][t],
        scheduled: scheduled[i][t],
        net,
        planned_receipt: replenishment,
        planned_release: 0L,
        projected: available,
      })
    }
    let final_buckets = buckets.map(fn(b) {
      { ..b, planned_release: releases[b.index], }
    })
    plans.push({ item: item.sku, buckets: final_buckets, })
  }
  plans.sort_by(fn(a, b) { a.item.lexical_compare(b.item) })
  orders.sort_by(fn(a, b) {
    if a.item == b.item {
      a.receipt_bucket.compare(b.receipt_bucket)
    } else {
      a.item.lexical_compare(b.item)
    }
  })
  pegs.sort_by(fn(a, b) {
    if a.item != b.item {
      a.item.lexical_compare(b.item)
    } else if a.bucket != b.bucket {
      a.bucket.compare(b.bucket)
    } else {
      match (a.source, b.source) {
        (Demand(x), Demand(y)) => x.lexical_compare(y)
        (Demand(_), ParentOrder(_, _)) => -1
        (ParentOrder(_, _), Demand(_)) => 1
        (ParentOrder(x, tx), ParentOrder(y, ty)) =>
          if x == y {
            tx.compare(ty)
          } else {
            x.lexical_compare(y)
          }
      }
    }
  })
  Ok({ horizon: h, items: plans, orders, pegs, })
}
