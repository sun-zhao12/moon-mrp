///|
/// Discrete-time replenishment policy.
///
/// - `LotForLot` orders exactly the net requirement.
/// - `FixedQuantity(size)` orders whole batches of `size`.
/// - `Multiple(m)` rounds the order up to a multiple of `m`.
/// - `MinimumMultiple(minimum, m)` satisfies the minimum, then rounds to `m`.
/// - `PeriodOrder(n)` covers the net requirements of the next `n` buckets.
/// - `MinMax(minimum, maximum)` replenishes up to `maximum` whenever the
///   projected balance would fall below `minimum`.
pub(all) enum LotRule {
  LotForLot
  FixedQuantity(Qty)
  Multiple(Qty)
  MinimumMultiple(Qty, Qty)
  PeriodOrder(Int)
  MinMax(Qty, Qty)
} derive(Eq, @debug.Debug)

///|
/// One planning item. `unit` is a label only; BOM rows that use a different
/// label must be converted through `Request.conversions`.
pub(all) struct Item {
  sku : String
  unit : String
  on_hand : Qty
  safety_stock : Qty
  lead_time : Int
  /// Usable fraction of a planned order, in per-mille: `900` means the order
  /// yields 90% good units and must be inflated accordingly.
  yield_per_mille : Int
  lot : LotRule
} derive(Eq, @debug.Debug)

///|
/// A parent unit consumes `units_per` child units at its order release, plus
/// `scrap_per_mille` of extra consumption (`50` means 5% scrap).
pub(all) struct Component {
  parent : String
  child : String
  units_per : Qty
  /// Empty means "the child's base unit"; otherwise a conversion from this
  /// label to the child's `unit` must exist in `Request.conversions`.
  usage_unit : String
  scrap_per_mille : Int
} derive(Eq, @debug.Debug)

///|
/// `factor` is how many child base units one usage unit contains, for example
/// grams to kilograms is `Qty::milli(1L)`.
pub(all) struct UnitConversion {
  from : String
  to : String
  factor : Qty
} derive(Eq, @debug.Debug)

///|
/// IDs must be unique within demands, and separately within receipts.
pub(all) struct Movement {
  id : String
  item : String
  bucket : Int
  quantity : Qty
} derive(Eq, @debug.Debug)

///|
/// What to do when a planned release would start before bucket zero.
pub(all) enum ReleasePolicy {
  /// Reject the entire calculation (default, safest).
  Strict
  /// Clamp the release to bucket zero, keep the plan and record an incident.
  AllowLate
} derive(Eq, @debug.Debug)

///|
pub(all) struct Request {
  horizon : Int
  items : Array[Item]
  bom : Array[Component]
  demands : Array[Movement]
  receipts : Array[Movement]
  conversions : Array[UnitConversion]
  policy : ReleasePolicy
} derive(@debug.Debug)

///|
pub(all) enum Source {
  Demand(String)
  ParentOrder(String, Int)
} derive(Eq, @debug.Debug)

///|
/// Gross demand contribution, before netting with stock and receipts.
pub(all) struct Peg {
  item : String
  bucket : Int
  quantity : Qty
  source : Source
} derive(Eq, @debug.Debug)

///|
/// One planning bucket. `net` is the good-unit requirement, `planned_receipt`
/// is the order quantity (start quantity), `received` is the usable part of
/// that order that reaches stock, and `planned_release` is the order quantity
/// released `lead_time` buckets earlier.
pub(all) struct Bucket {
  index : Int
  gross : Qty
  scheduled : Qty
  net : Qty
  planned_receipt : Qty
  received : Qty
  planned_release : Qty
  projected : Qty
} derive(Eq, @debug.Debug)

///|
pub(all) struct ItemPlan {
  item : String
  buckets : Array[Bucket]
} derive(Eq, @debug.Debug)

///|
pub(all) struct Order {
  item : String
  receipt_bucket : Int
  release_bucket : Int
  quantity : Qty
  /// True when the required release fell before bucket zero and the policy
  /// `AllowLate` clamped it to bucket zero.
  late : Bool
} derive(Eq, @debug.Debug)

///|
/// A non-fatal planning incident, for example a release clamped to bucket zero.
pub(all) struct Incident {
  item : String
  receipt_bucket : Int
  required_release : Int
  actual_release : Int
} derive(Eq, @debug.Debug)

///|
/// Plans contain no promises about finite machine or supplier capacity.
pub(all) struct Plan {
  horizon : Int
  items : Array[ItemPlan]
  orders : Array[Order]
  pegs : Array[Peg]
  incidents : Array[Incident]
} derive(Eq, @debug.Debug)

///|
pub(all) enum PlanningError {
  InvalidHorizon
  SizeLimit
  InvalidItem(String)
  DuplicateItem(String)
  UnknownItem(String)
  InvalidComponent(String, String)
  DuplicateComponent(String, String)
  InvalidMovement(String)
  DuplicateMovement(String)
  Cycle(Array[String])
  QuantityLimit(String)
  BeforeHorizon(String, Int, Int)
  InvalidConversion(String, String)
} derive(Eq, @debug.Debug)

///|
pub extend LotRule with Eq::{equal, not_equal}

///|
pub extend LotRule with @debug.Debug::{to_repr}

///|
pub extend Item with Eq::{equal, not_equal}

///|
pub extend Item with @debug.Debug::{to_repr}

///|
pub extend Component with Eq::{equal, not_equal}

///|
pub extend Component with @debug.Debug::{to_repr}

///|
pub extend UnitConversion with Eq::{equal, not_equal}

///|
pub extend UnitConversion with @debug.Debug::{to_repr}

///|
pub extend Movement with Eq::{equal, not_equal}

///|
pub extend Movement with @debug.Debug::{to_repr}

///|
pub extend ReleasePolicy with Eq::{equal, not_equal}

///|
pub extend ReleasePolicy with @debug.Debug::{to_repr}

///|
pub extend Source with Eq::{equal, not_equal}

///|
pub extend Source with @debug.Debug::{to_repr}

///|
pub extend Peg with Eq::{equal, not_equal}

///|
pub extend Peg with @debug.Debug::{to_repr}

///|
pub extend Bucket with Eq::{equal, not_equal}

///|
pub extend Bucket with @debug.Debug::{to_repr}

///|
pub extend ItemPlan with Eq::{equal, not_equal}

///|
pub extend ItemPlan with @debug.Debug::{to_repr}

///|
pub extend Order with Eq::{equal, not_equal}

///|
pub extend Order with @debug.Debug::{to_repr}

///|
pub extend Incident with Eq::{equal, not_equal}

///|
pub extend Incident with @debug.Debug::{to_repr}

///|
pub extend Plan with Eq::{equal, not_equal}

///|
pub extend Plan with @debug.Debug::{to_repr}

///|
pub extend PlanningError with Eq::{equal, not_equal}

///|
pub extend PlanningError with @debug.Debug::{to_repr}

///|
pub extend Request with @debug.Debug::{to_repr}
