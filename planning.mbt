///| Engineering bounds. They are large enough for a real planning run and still

///| keep every intermediate value inside Int64.

///|
let max_items : Int = 4096

///|
let max_horizon : Int = 1024

///|
let max_edges : Int = 100000

///|
let max_movements : Int = 100000

///|
let max_lead_time : Int = 4096

///|
/// 10^12 units, the largest quantity accepted or produced (in milli-units).
let qty_limit_milli : Int64 = 1000000000000000L

///|
let int64_max : Int64 = 9223372036854775807L

///|
fn qty_ok(milli : Int64) -> Bool {
  milli >= 0L && milli <= qty_limit_milli
}

///|
fn positive_qty(milli : Int64) -> Bool {
  milli > 0L && milli <= qty_limit_milli
}

///|
fn lot_valid(lot : LotRule) -> Bool {
  match lot {
    LotForLot => true
    FixedQuantity(size) => positive_qty(size.milli)
    Multiple(m) => positive_qty(m.milli)
    MinimumMultiple(minimum, m) =>
      positive_qty(minimum.milli) && positive_qty(m.milli)
    PeriodOrder(periods) => periods >= 1 && periods <= max_horizon
    MinMax(minimum, maximum) =>
      minimum.milli >= 0L &&
      positive_qty(maximum.milli) &&
      minimum.milli <= maximum.milli
  }
}

///|
fn ceil_to_multiple(q : Int64, multiple : Int64) -> Result[Int64, Unit] {
  if q == 0L {
    return Ok(0L)
  }
  let count = q / multiple + (if q % multiple == 0L { 0L } else { 1L })
  if count > int64_max / multiple {
    return Err(())
  }
  Ok(count * multiple)
}

///|
fn apply_lot(q : Int64, lot : LotRule) -> Result[Int64, Unit] {
  match lot {
    LotForLot => Ok(q)
    FixedQuantity(size) => ceil_to_multiple(q, size.milli)
    Multiple(m) => ceil_to_multiple(q, m.milli)
    MinimumMultiple(minimum, m) => {
      let target = if q > minimum.milli { q } else { minimum.milli }
      ceil_to_multiple(target, m.milli)
    }
    PeriodOrder(_) => Ok(q)
    MinMax(_, maximum) =>
      if q < maximum.milli {
        Ok(maximum.milli)
      } else {
        Ok(q)
      }
  }
}

///|
/// Multiply two bounded non-negative numbers and divide by `divisor`, rounding
/// up. `Err` means the intermediate product would overflow Int64.
fn mul_div_ceil(a : Int64, b : Int64, divisor : Int64) -> Result[Int64, Unit] {
  if a == 0L || b == 0L {
    return Ok(0L)
  }
  if a > int64_max / b {
    return Err(())
  }
  let product = a * b
  let quotient = product / divisor
  if product % divisor == 0L {
    Ok(quotient)
  } else {
    Ok(quotient + 1L)
  }
}

///|
/// Child demand for one parent order: scrap padding, unit usage and optional
/// unit conversion, each step rounded up to 0.001.
fn component_demand(
  start : Int64,
  units_per : Int64,
  scrap_per_mille : Int,
  conversion : Int64,
) -> Result[Int64, Unit] {
  let padded = match
    mul_div_ceil(start, 1000L + scrap_per_mille.to_int64(), 1000L) {
    Ok(value) => value
    Err(_) => return Err(())
  }
  let nominal = match mul_div_ceil(padded, units_per, 1000L) {
    Ok(value) => value
    Err(_) => return Err(())
  }
  if conversion == 0L {
    Ok(nominal)
  } else {
    mul_div_ceil(nominal, conversion, 1000L)
  }
}

///|
/// Quantity needed to cover `periods` buckets without dropping below the safety
/// floor, starting from the balance after scheduled receipts.
fn window_requirement(
  available : Int64,
  start_bucket : Int,
  periods : Int,
  horizon : Int,
  gross : Array[Int64],
  scheduled : Array[Int64],
  safety : Int64,
) -> Result[Int64, Unit] {
  let mut required = 0L
  let mut projected = available
  let end = if start_bucket + periods < horizon {
    start_bucket + periods
  } else {
    horizon
  }
  for k in start_bucket..<end {
    projected = projected + scheduled[k] - gross[k]
    if projected < safety {
      let shortfall = safety - projected
      if required > int64_max - shortfall {
        return Err(())
      }
      required = required + shortfall
      projected = safety
    }
  }
  Ok(required)
}

///|
/// Lot rounding for one net requirement. `PeriodOrder` and `MinMax` need a
/// calendar, so here they return the requirement unchanged (or the `MinMax`
/// maximum when it is larger).
pub fn order_quantity(net : Qty, lot : LotRule) -> Result[Qty, PlanningError] {
  if !qty_ok(net.milli) || !lot_valid(lot) {
    return Err(InvalidItem("lot or net quantity"))
  }
  if net.milli == 0L {
    return Ok(Qty::zero())
  }
  match apply_lot(net.milli, lot) {
    Ok(value) =>
      if qty_ok(value) {
        Ok(Qty::milli(value))
      } else {
        Err(QuantityLimit("lot rounding"))
      }
    Err(_) => Err(QuantityLimit("lot rounding"))
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
      m.quantity.milli <= 0L ||
      !qty_ok(m.quantity.milli) {
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

///|
/// Validate the whole graph, net parents before children, apply scrap, yield,
/// unit conversion and the lot policy, then peg every gross requirement.
///
/// `ReleasePolicy::Strict` rejects the calculation when an order would have to
/// be released before bucket zero; `AllowLate` clamps it to bucket zero, flags
/// the order and records an `Incident` instead. No input array is mutated and no
/// partial plan is returned on error.
pub fn plan(request : Request) -> Result[Plan, PlanningError] {
  let h = request.horizon
  if h < 1 || h > max_horizon {
    return Err(InvalidHorizon)
  }
  let n = request.items.length()
  if n == 0 ||
    n > max_items ||
    request.bom.length() > max_edges ||
    request.demands.length() > max_movements ||
    request.receipts.length() > max_movements {
    return Err(SizeLimit)
  }
  let items = request.items.copy()
  items.sort_by(fn(a, b) { a.sku.lexical_compare(b.sku) })
  let index : Map[String, Int] = Map([])
  for i, item in items {
    if item.sku == "" ||
      !qty_ok(item.on_hand.milli) ||
      !qty_ok(item.safety_stock.milli) ||
      item.lead_time < 0 ||
      item.lead_time > max_lead_time ||
      item.yield_per_mille < 1 ||
      item.yield_per_mille > 1000 ||
      !lot_valid(item.lot) {
      return Err(InvalidItem(item.sku))
    }
    if index.contains(item.sku) {
      return Err(DuplicateItem(item.sku))
    }
    index[item.sku] = i
  }
  let conversions : Map[String, Int64] = Map([])
  for c in request.conversions {
    if c.from == "" ||
      c.to == "" ||
      c.from == c.to ||
      !positive_qty(c.factor.milli) {
      return Err(InvalidConversion(c.from, c.to))
    }
    let key = c.from + "->" + c.to
    if conversions.contains(key) {
      return Err(InvalidConversion(c.from, c.to))
    }
    conversions[key] = c.factor.milli
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
  let children : Array[Array[(Int, Int64, Int, Int64)]] = Array::makei(n, fn(
    _,
  ) {
    []
  })
  for i, edge in bom {
    if !index.contains(edge.parent) {
      return Err(UnknownItem(edge.parent))
    }
    if !index.contains(edge.child) {
      return Err(UnknownItem(edge.child))
    }
    if edge.parent == edge.child ||
      !positive_qty(edge.units_per.milli) ||
      edge.scrap_per_mille < 0 ||
      edge.scrap_per_mille > 1000 {
      return Err(InvalidComponent(edge.parent, edge.child))
    }
    if i > 0 &&
      bom[i - 1].parent == edge.parent &&
      bom[i - 1].child == edge.child {
      return Err(DuplicateComponent(edge.parent, edge.child))
    }
    let p = index[edge.parent]
    let c = index[edge.child]
    let mut conversion = 0L
    if edge.usage_unit != "" && edge.usage_unit != items[c].unit {
      let key = edge.usage_unit + "->" + items[c].unit
      match conversions.get(key) {
        Some(factor) => conversion = factor
        None => return Err(InvalidConversion(edge.usage_unit, items[c].unit))
      }
    }
    children[p].push(
      (c, edge.units_per.milli, edge.scrap_per_mille, conversion),
    )
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
    let total = gross[i][d.bucket] + d.quantity.milli
    if total > qty_limit_milli {
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
    let total = scheduled[i][r.bucket] + r.quantity.milli
    if total > qty_limit_milli {
      return Err(QuantityLimit(r.item))
    }
    scheduled[i][r.bucket] = total
  }
  let plans : Array[ItemPlan] = []
  let orders : Array[Order] = []
  let incidents : Array[Incident] = []
  for i in order {
    let item = items[i]
    let releases = Array::make(h, 0L)
    let buckets : Array[Bucket] = []
    let mut available = item.on_hand.milli
    for t in 0..<h {
      available = available + scheduled[i][t]
      if available > qty_limit_milli {
        return Err(QuantityLimit(item.sku))
      }
      let needed = gross[i][t] + item.safety_stock.milli
      if needed > qty_limit_milli {
        return Err(QuantityLimit(item.sku))
      }
      let net = if needed > available { needed - available } else { 0L }
      let mut required_good = 0L
      match item.lot {
        MinMax(minimum, maximum) => {
          let after_demand = available - gross[i][t]
          if after_demand < minimum.milli {
            let target = maximum.milli - after_demand
            if target < 0L || target > qty_limit_milli {
              return Err(QuantityLimit(item.sku))
            }
            required_good = target
          }
        }
        PeriodOrder(periods) =>
          if net > 0L {
            match
              window_requirement(
                available,
                t,
                periods,
                h,
                gross[i],
                scheduled[i],
                item.safety_stock.milli,
              ) {
              Ok(value) => required_good = value
              Err(_) => return Err(QuantityLimit(item.sku))
            }
          }
        _ => required_good = net
      }
      let mut start = 0L
      let mut received = 0L
      if required_good > 0L {
        start = match
          mul_div_ceil(required_good, 1000L, item.yield_per_mille.to_int64()) {
          Ok(value) => value
          Err(_) => return Err(QuantityLimit(item.sku))
        }
        match item.lot {
          PeriodOrder(_) => ()
          MinMax(_, _) => ()
          _ =>
            start = match apply_lot(start, item.lot) {
              Ok(value) => value
              Err(_) => return Err(QuantityLimit(item.sku))
            }
        }
        if !qty_ok(start) {
          return Err(QuantityLimit(item.sku))
        }
        received = start * item.yield_per_mille.to_int64() / 1000L
        if received > qty_limit_milli {
          return Err(QuantityLimit(item.sku))
        }
        let required_release = t - item.lead_time
        let release = if required_release < 0 {
          match request.policy {
            Strict => return Err(BeforeHorizon(item.sku, t, required_release))
            AllowLate => 0
          }
        } else {
          required_release
        }
        if required_release < 0 {
          incidents.push({
            item: item.sku,
            receipt_bucket: t,
            required_release,
            actual_release: release,
          })
        }
        releases[release] = releases[release] + start
        if releases[release] > qty_limit_milli {
          return Err(QuantityLimit(item.sku))
        }
        orders.push({
          item: item.sku,
          receipt_bucket: t,
          release_bucket: release,
          quantity: Qty::milli(start),
          late: required_release < 0,
        })
        for child in children[i] {
          let (child_index, units, scrap, conversion) = child
          let demand = match component_demand(start, units, scrap, conversion) {
            Ok(value) => value
            Err(_) => return Err(QuantityLimit(items[child_index].sku))
          }
          let total = gross[child_index][release] + demand
          if total > qty_limit_milli {
            return Err(QuantityLimit(items[child_index].sku))
          }
          gross[child_index][release] = total
          pegs.push({
            item: items[child_index].sku,
            bucket: release,
            quantity: Qty::milli(demand),
            source: ParentOrder(item.sku, t),
          })
        }
      }
      available = available + received - gross[i][t]
      if available > qty_limit_milli {
        return Err(QuantityLimit(item.sku))
      }
      buckets.push({
        index: t,
        gross: Qty::milli(gross[i][t]),
        scheduled: Qty::milli(scheduled[i][t]),
        net: Qty::milli(net),
        planned_receipt: Qty::milli(start),
        received: Qty::milli(received),
        planned_release: Qty::zero(),
        projected: Qty::milli(available),
      })
    }
    let final_buckets = buckets.map(fn(b) {
      { ..b, planned_release: Qty::milli(releases[b.index]), }
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
  incidents.sort_by(fn(a, b) {
    if a.item == b.item {
      a.receipt_bucket.compare(b.receipt_bucket)
    } else {
      a.item.lexical_compare(b.item)
    }
  })
  Ok({ horizon: h, items: plans, orders, pegs, incidents, })
}
