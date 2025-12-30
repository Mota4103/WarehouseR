###############################################################################
# SimioData_Export.R - Export data for Simio Simulation
# Supporting Question 4 (35 points)
###############################################################################

library(data.table)

cat("=== Export Data for Simio Simulation ===\n\n")

### =========================
### STEP 1: Load Data
### =========================
cat("Loading data...\n")

# Must run Q2_FluidModel.R and Q3_Slotting.R first
required_files <- c("Q3_slotting_result.csv", "shipTrans.txt")
for (f in required_files) {
  if (!file.exists(f)) {
    cat("ERROR: File not found:", f, "\n")
    cat("Please run Q2_FluidModel.R and Q3_Slotting.R first\n")
    stop("Missing required files")
  }
}

slotting <- fread("Q3_slotting_result.csv")
shipTrans <- fread("shipTrans.txt", sep = ",", header = TRUE)
setnames(shipTrans, names(shipTrans), gsub("[ .]", "", names(shipTrans)))
shipTrans[, PartNo := gsub("[ ]", "", PartNo)]

cat("  - slotting: ", nrow(slotting), " items\n", sep="")
cat("  - shipTrans: ", format(nrow(shipTrans), big.mark=","), " rows\n\n", sep="")

### =========================
### STEP 2: Create SKU_FPA_Layout.csv
### Position coordinates (X, Y) for each SKU in FPA
### =========================
cat("1. Creating SKU_FPA_Layout.csv...\n")

# Physical layout parameters
cabinet_width_m <- 1.98
cabinet_depth_m <- 0.68
floor_height_m <- 0.30
aisle_width_m <- 1.5  # Aisle between rows

# FPA layout: 2 aisles, 12 cabinets per side
# Aisle 1: Cabinet 1-12 (left), Cabinet 13-24 (right)

# Check column names in slotting
if ("Cabinet" %in% names(slotting)) {
  cab_col <- "Cabinet"
  floor_col <- "Floor"
} else if ("CabinetNo" %in% names(slotting)) {
  cab_col <- "CabinetNo"
  floor_col <- "FloorNo"
} else {
  stop("Cannot find Cabinet column in slotting data")
}

# Get column values
slotting[, CabinetNo := get(cab_col)]
slotting[, FloorNo := get(floor_col)]

# Create FPA layout
fpa_layout <- slotting[!is.na(CabinetNo), .(
  PartNo = PartNo,
  PartName = if("PartName" %in% names(slotting)) PartName else NA_character_,
  CabinetNo = CabinetNo,
  FloorNo = FloorNo,
  PositionID = if("PositionID" %in% names(slotting)) PositionID else paste0("C", sprintf("%02d", CabinetNo), "F", FloorNo),
  # Calculate X coordinate (along aisle)
  X_m = ifelse(CabinetNo <= 12,
               (CabinetNo - 1) * cabinet_width_m,
               (CabinetNo - 13) * cabinet_width_m),
  # Calculate Y coordinate (across aisle)
  Y_m = ifelse(CabinetNo <= 12,
               0,  # Left side
               cabinet_depth_m + aisle_width_m),  # Right side
  # Calculate Z coordinate (height)
  Z_m = (FloorNo - 1) * floor_height_m + (floor_height_m / 2),
  # Additional info
  Frequency = if("Frequency" %in% names(slotting)) Frequency else if("Freq" %in% names(slotting)) Freq else NA_integer_,
  AllocatedVolume_m3 = if("AllocatedVolume_m3" %in% names(slotting)) AllocatedVolume_m3 else NA_real_,
  PositionsNeeded = if("PositionsNeeded" %in% names(slotting)) PositionsNeeded else 1,
  BoxesPerPosition = if("BoxesPerPosition" %in% names(slotting)) BoxesPerPosition else 1
)]

# Calculate distance from I/O point (assumed at 0,0)
fpa_layout[, DistanceFromIO := sqrt(X_m^2 + Y_m^2)]

fwrite(fpa_layout, "Simio_SKU_FPA_Layout.csv")
cat("  - Saved: Simio_SKU_FPA_Layout.csv (", nrow(fpa_layout), " rows)\n\n", sep="")

### =========================
### STEP 3: Create Pick_Orders.csv
### Historical pick order data
### =========================
cat("2. Creating Pick_Orders.csv...\n")

# Filter only SKUs in FPA
fpa_skus <- unique(fpa_layout$PartNo)
shipTrans_fpa <- shipTrans[PartNo %in% fpa_skus]

# Convert date and time
shipTrans_fpa[, ShippingDay := as.Date(as.character(ShippingDay), "%Y%m%d")]
shipTrans_fpa[, DeliveryTime := sprintf("%04d", as.integer(DeliveryTime))]
shipTrans_fpa[, DeliveryHour := as.integer(substr(DeliveryTime, 1, 2))]
shipTrans_fpa[, DeliveryMinute := as.integer(substr(DeliveryTime, 3, 4))]

# Create Order ID
delivery_col <- grep("DeliveryNo", names(shipTrans_fpa), value = TRUE)[1]
shipTrans_fpa[, OrderID := paste(ShippingDay, get(delivery_col), sep = "_")]

# Summary pick orders
pick_orders <- shipTrans_fpa[, .(
  OrderID = OrderID,
  ShippingDay = ShippingDay,
  DeliveryTime = DeliveryTime,
  DeliveryHour = DeliveryHour,
  DeliveryMinute = DeliveryMinute,
  PartNo = PartNo,
  BoxType = BoxType,
  OrderQty = OrderQty,
  ScanQty = ScanQty,
  ReceivingLocation = ReceivingLocation
)]

# Sort by time
setorder(pick_orders, ShippingDay, DeliveryHour, DeliveryMinute)

# Add sequence number
pick_orders[, SequenceNo := 1:.N]

fwrite(pick_orders, "Simio_Pick_Orders.csv")
cat("  - Saved: Simio_Pick_Orders.csv (", format(nrow(pick_orders), big.mark=","), " rows)\n\n", sep="")

### =========================
### STEP 4: Create SKU_Inventory_Params.csv
### Min/Max parameters for each SKU
### =========================
cat("3. Creating SKU_Inventory_Params.csv...\n")

# Calculate boxes per SKU based on allocated volume and box volume
# Merge with itemMaster for CubM
itemMaster <- fread("itemMaster.txt", sep = ",", header = TRUE)
setnames(itemMaster, names(itemMaster), gsub("[ .]", "", names(itemMaster)))

if ("PartNo" %in% names(itemMaster) == FALSE) {
  old_names <- names(itemMaster)[1:9]
  new_names <- c("Skus", "PartNo", "PartName", "BoxType", "UnitLabelQt",
                 "ModuleSizeL", "ModuleSizeV", "ModuleSizeH", "CubM")
  setnames(itemMaster, old_names, new_names)
}

itemMaster[, CubM := as.numeric(gsub(",", "", CubM))]
itemMaster[, PartNo := gsub("[ ]", "", PartNo)]

# Create inventory params
inventory_params <- merge(
  fpa_layout[, .(PartNo, PartName, CabinetNo, FloorNo, AllocatedVolume_m3, Frequency, BoxesPerPosition)],
  itemMaster[, .(PartNo, CubM)],
  by = "PartNo",
  all.x = TRUE
)

# Calculate max boxes
inventory_params[, MaxBoxes := pmax(1, floor(AllocatedVolume_m3 / CubM))]
inventory_params[is.na(MaxBoxes) | MaxBoxes < 1, MaxBoxes := BoxesPerPosition]

# Min = floor(Max/2) per problem statement
inventory_params[, MinBoxes := floor(MaxBoxes / 2)]
inventory_params[MinBoxes < 1, MinBoxes := 1]

# Additional metrics
inventory_params[, AnnualFrequency := Frequency]
inventory_params[, DailyAvgPicks := Frequency / 365]
inventory_params[, ReorderPoint := MinBoxes]
inventory_params[, SafetyStock := ceiling(DailyAvgPicks * 2)]  # 2-day safety

fwrite(inventory_params[, .(PartNo, PartName, CabinetNo, FloorNo, MaxBoxes, MinBoxes,
                             ReorderPoint, SafetyStock, AnnualFrequency, DailyAvgPicks)],
       "Simio_SKU_Inventory_Params.csv")
cat("  - Saved: Simio_SKU_Inventory_Params.csv (", nrow(inventory_params), " rows)\n\n", sep="")

### =========================
### STEP 5: Create Activity_Times.csv
### Standard times for activities
### =========================
cat("4. Creating Activity_Times.csv...\n")

activity_times <- data.table(
  Activity = c(
    "Walking",
    "Check_and_Pick",
    "Pick_per_Box",
    "Replenishment_Normal",
    "Replenishment_Emergency",
    "Start_Stop_Cart",
    "Scan"
  ),
  Time_min = c(
    1.0,    # 1 min/100m → 0.01 min/m
    0.4,    # 0.4 min/line
    0.1,    # 0.1 min/box
    15.0,   # 15 min/trip
    120.0,  # 120 min (open container)
    0.2,    # 12 sec = 0.2 min
    0.083   # 5 sec = 0.083 min
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
  Description = c(
    "Walking time in FPA",
    "Check and pick part",
    "Time per box",
    "Normal replenishment (min-max)",
    "Emergency container open",
    "Cart stop/start time",
    "Barcode scan time"
  )
)

fwrite(activity_times, "Simio_Activity_Times.csv")
cat("  - Saved: Simio_Activity_Times.csv\n\n")

### =========================
### STEP 6: Create Order_Arrival_Distribution.csv
### Order arrival distribution
### =========================
cat("5. Analyzing Order Arrival Distribution...\n")

# Analyze hourly distribution
hourly_dist <- pick_orders[, .(OrderCount = .N), by = DeliveryHour]
hourly_dist[, Percentage := OrderCount / sum(OrderCount) * 100]
setorder(hourly_dist, DeliveryHour)

fwrite(hourly_dist, "Simio_Hourly_Arrival_Distribution.csv")
cat("  - Saved: Simio_Hourly_Arrival_Distribution.csv\n")

# Analyze inter-arrival time
pick_orders[, DateTime := as.POSIXct(paste(ShippingDay,
                                            paste0(sprintf("%02d", DeliveryHour), ":",
                                                   sprintf("%02d", DeliveryMinute), ":00")),
                                     format = "%Y-%m-%d %H:%M:%S")]
setorder(pick_orders, DateTime)
pick_orders[, InterArrivalSec := as.numeric(difftime(DateTime, shift(DateTime), units = "secs"))]
pick_orders[is.na(InterArrivalSec), InterArrivalSec := 0]

# Inter-arrival statistics
cat("\n  Inter-arrival time statistics:\n")
cat("    - Mean: ", round(mean(pick_orders$InterArrivalSec[pick_orders$InterArrivalSec > 0], na.rm = TRUE), 2), " seconds\n", sep="")
cat("    - Median: ", round(median(pick_orders$InterArrivalSec[pick_orders$InterArrivalSec > 0], na.rm = TRUE), 2), " seconds\n", sep="")
cat("    - SD: ", round(sd(pick_orders$InterArrivalSec[pick_orders$InterArrivalSec > 0], na.rm = TRUE), 2), " seconds\n\n", sep="")

### =========================
### STEP 7: Summary for Simio
### =========================
cat("\n=== Summary for Simio ===\n\n")

cat("Main Parameters:\n")
cat("  - SKUs in FPA: ", uniqueN(fpa_layout$PartNo), "\n", sep="")
cat("  - Pick Orders: ", format(nrow(pick_orders), big.mark=","), "\n", sep="")
cat("  - Cabinets: 24\n")
cat("  - Floors per Cabinet: 5\n")
cat("  - FPA Volume: 36.0 m³\n\n")

cat("Simio Parameters:\n")
cat("  - Walking speed: 100 m/min\n")
cat("  - Check + Pick: 0.4 min/line + 0.1 min/box\n")
cat("  - Normal Replenishment: 15 min\n")
cat("  - Emergency Replenishment: 120 min\n")
cat("  - Min = floor(Max/2)\n\n")

cat("Exported Files:\n")
cat("  1. Simio_SKU_FPA_Layout.csv - SKU positions in FPA\n")
cat("  2. Simio_Pick_Orders.csv - Pick order data\n")
cat("  3. Simio_SKU_Inventory_Params.csv - Min/Max parameters\n")
cat("  4. Simio_Activity_Times.csv - Standard times\n")
cat("  5. Simio_Hourly_Arrival_Distribution.csv - Order distribution\n")

cat("\n=== Export Complete ===\n")
