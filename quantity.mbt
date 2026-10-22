///|
/// Fixed-point quantity in milli-units: `1000` milli-units are one unit, so
/// `0.001` is the smallest step and no binary floating point is involved in any
/// calculation. `2` is written `Qty::int(2)`, `0.25` as `Qty::milli(250L)`.
pub(all) struct Qty {
  milli : Int64
} derive(Eq, @debug.Debug)

///|
pub extend Qty with Eq::{equal, not_equal}

///|
pub extend Qty with @debug.Debug::{to_repr}

///|
/// Whole units, for example `Qty::int(3)` is `3`.
pub fn Qty::int(units : Int) -> Qty {
  { milli: units.to_int64() * 1000L, }
}

///|
/// Raw milli-units, for example `Qty::milli(250L)` is `0.25`.
pub fn Qty::milli(milli : Int64) -> Qty {
  { milli, }
}

///|
pub fn Qty::zero() -> Qty {
  { milli: 0L, }
}

///|
pub fn Qty::add(self : Qty, other : Qty) -> Qty {
  { milli: self.milli + other.milli, }
}

///|
pub fn Qty::sub(self : Qty, other : Qty) -> Qty {
  { milli: self.milli - other.milli, }
}

///|
pub fn Qty::is_zero(self : Qty) -> Bool {
  self.milli == 0L
}

///|
pub fn Qty::compare(self : Qty, other : Qty) -> Int {
  if self.milli < other.milli {
    -1
  } else if self.milli > other.milli {
    1
  } else {
    0
  }
}

///|
/// Render a quantity in decimal notation, trimming trailing zeros, so `1500`
/// milli becomes `1.5` and `2000` becomes `2`.
pub fn Qty::to_string(self : Qty) -> String {
  let value = self.milli
  let sign = if value < 0L { "-" } else { "" }
  let abs = if value < 0L { -value } else { value }
  let whole = abs / 1000L
  let fraction = abs % 1000L
  if fraction == 0L {
    sign + whole.to_string()
  } else {
    sign + whole.to_string() + "." + fraction_text(fraction)
  }
}

///|
fn fraction_text(fraction : Int64) -> String {
  let hundreds = fraction / 100L
  let tens = fraction % 100L / 10L
  let ones = fraction % 10L
  if ones != 0L {
    hundreds.to_string() + tens.to_string() + ones.to_string()
  } else if tens != 0L {
    hundreds.to_string() + tens.to_string()
  } else {
    hundreds.to_string()
  }
}
