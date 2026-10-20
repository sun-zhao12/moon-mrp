///|
/// Discrete-time replenishment policy; quantities are indivisible units.
pub(all) enum LotRule {
  LotForLot
  Multiple(Int64)
  MinimumMultiple(Int64, Int64)
} derive(Eq, @debug.Debug)

///|
pub(all) struct Item {
  sku : String
  on_hand : Int64
  safety_stock : Int64
  lead_time : Int
  lot : LotRule
} derive(Eq, @debug.Debug)

///|
/// Each parent unit consumes units_per child units at its order release.
pub(all) struct Component {
  parent : String
  child : String
  units_per : Int64
} derive(Eq, @debug.Debug)

///|
/// IDs must be unique within demands, and separately within receipts.
pub(all) struct Movement {
  id : String
  item : String
  bucket : Int
  quantity : Int64
} derive(Eq, @debug.Debug)

///|
pub(all) struct Request {
  horizon : Int
  items : Array[Item]
  bom : Array[Component]
  demands : Array[Movement]
  receipts : Array[Movement]
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
  quantity : Int64
  source : Source
} derive(Eq, @debug.Debug)

///|
pub(all) struct Bucket {
  index : Int
  gross : Int64
  scheduled : Int64
  net : Int64
  planned_receipt : Int64
  planned_release : Int64
  projected : Int64
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
  quantity : Int64
} derive(Eq, @debug.Debug)

///|
/// Plans contain no promises about finite machine or supplier capacity.
pub(all) struct Plan {
  horizon : Int
  items : Array[ItemPlan]
  orders : Array[Order]
  pegs : Array[Peg]
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
pub extend Movement with Eq::{equal, not_equal}

///|
pub extend Movement with @debug.Debug::{to_repr}

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
pub extend Plan with Eq::{equal, not_equal}

///|
pub extend Plan with @debug.Debug::{to_repr}

///|
pub extend PlanningError with Eq::{equal, not_equal}

///|
pub extend PlanningError with @debug.Debug::{to_repr}

///|
pub extend Request with @debug.Debug::{to_repr}
