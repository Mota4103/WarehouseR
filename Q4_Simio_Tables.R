###############################################################################
# Q4_Simio_Tables.R - Create 4 Data Tables for Simio Simulation
###############################################################################

library(data.table)

cat("=== Creating 4 Simio Data Tables ===\n\n")

### =========================
### LOAD DATA
### =========================
slotting <- fread("Q3_slotting_result.csv")
shipTrans <- fread("shipTrans.txt", sep = ",", header = TRUE)
itemMaster <- fread("itemMaster.txt", sep = ",", header = TRUE)

# Clean column names
setnames(shipTrans, names(shipTrans), gsub("[ .]", "", names(shipTrans)))
setnames(itemMaster, names(itemMaster), gsub("[ .]", "", names(itemMaster)))
shipTrans[, PartNo := gsub("[ ]", "", PartNo)]
itemMaster[, PartNo := gsub("[ ]", "", PartNo)]

# Filter flood period (Oct-Nov 2011) and Sundays
shipTrans[, yyyymm := as.integer(yyyymm)]
shipTrans <- shipTrans[!(yyyymm %in% c(201110, 201111))]
shipTrans[, ShippingDate := as.Date(as.character(as.integer(ShippingDay)), "%Y%m%d")]
shipTrans[, WeekDay := weekdays(ShippingDate)]
shipTrans <- shipTrans[WeekDay != "Sunday"]

# Get FPA SKUs
fpa_skus <- unique(slotting$PartNo)
cat("FPA SKUs:", length(fpa_skus), "\n\n")

### =========================
### TABLE 1: Order Pick Lines (FPA only)
### =========================
cat("1. Creating Simio_OrderPickLines.csv...\n")

# Filter only FPA SKUs
pick_lines <- shipTrans[PartNo %in% fpa_skus]

# Format time properly
pick_lines[, DeliveryTime := sprintf("%04d", as.integer(DeliveryTime))]
pick_lines[, DeliveryHour := as.integer(substr(DeliveryTime, 1, 2))]
pick_lines[, DeliveryMinute := as.integer(substr(DeliveryTime, 3, 4))]

# Create proper DateTime for Simio (format: YYYY-MM-DD HH:MM:SS)
pick_lines[, ShippingDate := as.Date(as.character(as.integer(ShippingDay)), "%Y%m%d")]
pick_lines[, DateTimeStr := paste0(format(ShippingDate, "%Y-%m-%d"), " ",
                                    sprintf("%02d", DeliveryHour), ":",
                                    sprintf("%02d", DeliveryMinute), ":00")]

# Create order ID
delivery_col <- grep("DeliveryNo", names(pick_lines), value = TRUE)[1]
pick_lines[, OrderID := paste(as.integer(ShippingDay), get(delivery_col), sep = "_")]

# Merge with SKU position info from slotting
pick_lines <- merge(
  pick_lines,
  slotting[, .(PartNo, Cabinet, Floor, PositionID)],
  by = "PartNo",
  all.x = TRUE
)

# Select columns for Simio
order_pick_lines <- pick_lines[, .(
  OrderID,
  LineNo = 1:.N,
  DateTimeStr,
  ShippingDay = as.integer(ShippingDay),
  DeliveryHour,
  DeliveryMinute,
  PartNo,
  Cabinet,
  Floor,
  PositionID,
  BoxType,
  OrderQty = as.integer(OrderQty),
  ScanQty = as.integer(ScanQty),
  ReceivingLocation
)]

# Remove rows with missing DateTime components
order_pick_lines <- order_pick_lines[!is.na(DateTimeStr) & !is.na(DeliveryHour) & !is.na(DeliveryMinute)]

# Sort by DateTime
setorder(order_pick_lines, DateTimeStr, OrderID)
order_pick_lines[, LineNo := 1:.N]

fwrite(order_pick_lines, "Simio_OrderPickLines.csv")
cat("   Saved:", format(nrow(order_pick_lines), big.mark=","), "rows\n\n")

### =========================
### TABLE 2: Standard Time
### =========================
cat("2. Creating Simio_StandardTime.csv...\n")

standard_time <- data.table(
  Activity = c(
    "Walking",
    "Check_and_Pick",
    "Pick_per_Box",
    "Replenishment_Normal",
    "Replenishment_Emergency",
    "Start_Stop_Cart",
    "Scan"
  ),
  Time = c(
    1.0,      # 1 min per 100m
    0.4,      # 0.4 min per line
    0.1,      # 0.1 min per box
    15.0,     # 15 min per trip
    120.0,    # 120 min emergency
    0.2,      # 0.2 min per stop
    0.083     # 5 sec per scan
  ),
  Unit = c(
    "min/100m",
    "min/line",
    "min/box",
    "min/trip",
    "min/trip",
    "min/stop",
    "min/scan"
  ),
  Speed_or_Rate = c(
    "1.67 m/sec",
    "2.5 lines/min",
    "10 boxes/min",
    "4 trips/hour",
    "0.5 trips/hour",
    "5 stops/min",
    "12 scans/min"
  ),
  Description = c(
    "Walking time in FPA aisle",
    "Check location and pick part",
    "Additional time per box picked",
    "Normal replenishment (min-max system)",
    "Emergency: open container from reserve",
    "Stop and start picking cart",
    "Barcode scanning time"
  )
)

fwrite(standard_time, "Simio_StandardTime.csv")
cat("   Saved: 7 activities\n\n")

### =========================
### TABLE 3: SKUs in FPA
### =========================
cat("3. Creating Simio_SKUs_in_FPA.csv...\n")

# Merge with itemMaster for box dimensions and UnitLabelQt
skus_fpa <- merge(
  slotting[, .(
    PartNo,
    PartName,
    Frequency,
    Viscosity,
    DemandVolume_m3,
    AllocatedVolume_m3,
    Cabinet,
    Floor,
    PositionID,
    SubPosStart_m,
    SubPosEnd_m,
    BoxWidth_m,
    BoxDepth_m,
    BoxHeight_m,
    TotalBoxesNeeded
  )],
  itemMaster[, .(PartNo, UnitLabelQt, CubM)],
  by = "PartNo",
  all.x = TRUE
)

# Clean and convert
skus_fpa[, CubM := as.numeric(gsub(",", "", CubM))]
skus_fpa[, UnitLabelQt := as.integer(gsub(",", "", UnitLabelQt))]
skus_fpa[is.na(UnitLabelQt), UnitLabelQt := 1]  # Default to 1 if missing

# Calculate inventory parameters (in BOXES)
skus_fpa[, MaxBoxes := TotalBoxesNeeded]
skus_fpa[, MinBoxes := pmax(1, floor(MaxBoxes / 2))]
skus_fpa[, ReorderPointBoxes := MinBoxes]

# Calculate inventory parameters (in PIECES)
skus_fpa[, PiecesPerBox := UnitLabelQt]
skus_fpa[, MaxPieceQty := MaxBoxes * PiecesPerBox]
skus_fpa[, InitialQty := MaxPieceQty]  # Start full
skus_fpa[, CurrentQty := InitialQty]   # For simulation start
skus_fpa[, MinPieceQty := MinBoxes * PiecesPerBox]
skus_fpa[, ReorderPointPieces := MinPieceQty]

# Daily average
skus_fpa[, DailyAvgPicks := round(Frequency / 250, 2)]  # 250 working days
skus_fpa[, DailyAvgPieces := round(DailyAvgPicks * PiecesPerBox, 2)]

# Sort by Viscosity (high to low)
setorder(skus_fpa, -Viscosity)
skus_fpa[, ViscosityRank := 1:.N]

# Reorder columns - include position and piece quantities
skus_fpa <- skus_fpa[, .(
  ViscosityRank,
  PartNo,
  PartName,
  Frequency,
  Viscosity = round(Viscosity, 2),
  DemandVolume_m3 = round(DemandVolume_m3, 4),
  Cabinet,
  Floor,
  PositionID,
  SubPosStart_m = round(SubPosStart_m, 3),
  SubPosEnd_m = round(SubPosEnd_m, 3),
  BoxWidth_m,
  BoxDepth_m,
  BoxHeight_m,
  PiecesPerBox,
  MaxBoxes,
  MaxPieceQty,
  InitialQty,
  CurrentQty,
  MinBoxes,
  MinPieceQty,
  ReorderPointBoxes,
  ReorderPointPieces,
  DailyAvgPicks,
  DailyAvgPieces
)]

fwrite(skus_fpa, "Simio_SKUs_in_FPA.csv")
cat("   Saved:", nrow(skus_fpa), "SKUs\n\n")

### =========================
### TABLE 3b: SKU Params for Simio
### =========================
cat("3b. Creating Simio_SKU_Params.csv...\n")

sku_params <- skus_fpa[, .(
  PartNo,
  PartName,
  CabinetNo = Cabinet,
  FloorNo = Floor,
  MaxPieces = MaxPieceQty,
  InitialPieces = InitialQty,
  AnnualFrequency = Frequency,
  Viscosity
)]

fwrite(sku_params, "Simio_SKU_Params.csv")
cat("   Saved:", nrow(sku_params), "SKUs\n\n")

### =========================
### TABLE 4: Positions in FPA (only cabinets with SKUs)
### =========================
cat("4. Creating Simio_Positions_in_FPA.csv...\n")

# Cabinet layout parameters
cabinet_width_m <- 1.98
cabinet_depth_m <- 0.68
floor_height_m <- 0.30
aisle_width_m <- 2.0

# Get unique positions with SKUs
positions_fpa <- slotting[, .(
  SKUCount = .N,
  SKUs = paste(PartNo, collapse = ";"),
  TotalFrequency = sum(Frequency),
  TotalBoxes = sum(TotalBoxesNeeded)
), by = .(Cabinet, Floor, PositionID)]

# Calculate coordinates based on layout:
# Row 1: Cabinets 1-3 (Col1), 4-6 (Col2)
# Row 2: Cabinets 7-9 (Col1), 10-12 (Col2)
# Row 3: Cabinets 13-15 (Col1), 16-18 (Col2)
# Row 4: Cabinets 19-21 (Col1), 22-24 (Col2)

positions_fpa[, Row := ceiling(Cabinet / 6)]
positions_fpa[, Column := ifelse((Cabinet - 1) %% 6 < 3, 1, 2)]
positions_fpa[, CabInRow := ((Cabinet - 1) %% 3) + 1]

# X coordinate: position along row
positions_fpa[, X_m := (CabInRow - 1) * cabinet_width_m + cabinet_width_m / 2]

# Y coordinate: position across aisles
# Column 1 (left side): Y = 0
# Column 2 (right side): Y = cabinet_depth + aisle_width
positions_fpa[, Y_m := ifelse(Column == 1,
                               cabinet_depth_m / 2,
                               cabinet_depth_m + aisle_width_m + cabinet_depth_m / 2)]

# Adjust Y for different rows (rows are separated by back-to-back + aisle)
row_offset <- cabinet_depth_m * 2 + aisle_width_m
positions_fpa[, Y_m := Y_m + (Row - 1) * row_offset]

# Z coordinate: floor height
positions_fpa[, Z_m := (Floor - 1) * floor_height_m + floor_height_m / 2]

# Ergonomic score by floor
positions_fpa[, ErgonomicScore := fcase(
  Floor == 3, 100,  # Golden zone
  Floor == 2, 90,
  Floor == 4, 90,
  Floor == 1, 60,
  Floor == 5, 60
)]

# Calculate distance from start point (between Cabinet 3 and 4)
# Start point: X = 1.98*3/2 = 2.97m, Y = cabinet_depth/2 = 0.34m
start_x <- 2.97
start_y <- 0.34
positions_fpa[, DistanceFromStart_m := round(sqrt((X_m - start_x)^2 + (Y_m - start_y)^2), 2)]

# Sort by Cabinet and Floor
setorder(positions_fpa, Cabinet, Floor)

# Select final columns
positions_fpa <- positions_fpa[, .(
  Cabinet,
  Floor,
  PositionID,
  Row,
  Column,
  X_m = round(X_m, 2),
  Y_m = round(Y_m, 2),
  Z_m = round(Z_m, 2),
  DistanceFromStart_m,
  ErgonomicScore,
  SKUCount,
  TotalFrequency,
  TotalBoxes,
  SKUs
)]

fwrite(positions_fpa, "Simio_Positions_in_FPA.csv")
cat("   Saved:", nrow(positions_fpa), "positions (cabinets with SKUs only)\n\n")

### =========================
### SUMMARY
### =========================
cat("=== Summary ===\n\n")

cat("Files created:\n")
cat("  1. Simio_OrderPickLines.csv  - ", format(nrow(order_pick_lines), big.mark=","), " pick lines\n", sep="")
cat("  2. Simio_StandardTime.csv    - 7 activity times\n")
cat("  3. Simio_SKUs_in_FPA.csv     - ", nrow(skus_fpa), " SKUs with inventory params\n", sep="")
cat("  3b.Simio_SKU_Params.csv      - ", nrow(sku_params), " SKUs (simplified)\n", sep="")
cat("  4. Simio_Positions_in_FPA.csv- ", nrow(positions_fpa), " positions\n\n", sep="")

cat("Cabinet Layout:\n")
cat("  - Cabinets with SKUs: ", uniqueN(positions_fpa$Cabinet), " / 24\n", sep="")
cat("  - Total positions: ", nrow(positions_fpa), " / 120\n", sep="")
cat("  - Position size: 1.98m x 0.68m x 0.30m\n\n")

cat("=== Done ===\n")
