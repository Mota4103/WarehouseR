# --- Step 1: Load CSV files ---
df <- read.csv("DataFreq.csv", stringsAsFactors = FALSE)
item_master <- read.csv("itemMaster.txt", stringsAsFactors = FALSE)

# --- Step 2: Clean column names for main data ---
names(df) <- c("PartNo", "Volume", "Freq", "Viscosity")

# --- Step 3: Convert numeric columns ---
df$Volume <- as.numeric(gsub(",", "", df$Volume))
df$Freq <- as.numeric(gsub(",", "", df$Freq))
df$Viscosity <- as.numeric(gsub(",", "", df$Viscosity))

# --- Step 4: Clean item master columns ---
names(item_master)[1:9] <- c("Skus", "PartNo", "PartName", "BoxType", "UnitLabelQt", 
                             "ModuleSizeL", "ModuleSizeV", "ModuleSizeH", "CubM")

df$PartNo <- trimws(df$PartNo)
item_master$PartNo <- trimws(item_master$PartNo)

item_master$ModuleSizeL <- as.numeric(gsub(",", "", item_master$ModuleSizeL))
item_master$ModuleSizeV <- as.numeric(gsub(",", "", item_master$ModuleSizeV))
item_master$ModuleSizeH <- as.numeric(gsub(",", "", item_master$ModuleSizeH))
item_master$CubM <- as.numeric(gsub(",", "", item_master$CubM))

# --- Step 5: Calculate Width (use the larger of L and V) ---
item_master$Width <- pmax(item_master$ModuleSizeL, item_master$ModuleSizeV, na.rm = TRUE)
item_master$Depth <- pmin(item_master$ModuleSizeL, item_master$ModuleSizeV, na.rm = TRUE)

# --- Step 6: Filter items that fit in cabinets ---
cabinet_width_mm <- 1980
cabinet_height_mm <- 300
cabinet_depth_mm <- 680

filtered_items <- item_master[
  !is.na(item_master$ModuleSizeH) & 
    !is.na(item_master$Width) &
    !is.na(item_master$Depth) &
    !is.na(item_master$CubM) &
    item_master$ModuleSizeH <= cabinet_height_mm &
    item_master$Width <= cabinet_width_mm &
    item_master$Depth <= cabinet_depth_mm,
]

cat("\n=== FILTERED ITEMS SUMMARY ===\n")
cat("Total items in master:", nrow(item_master), "\n")
cat("Items that fit in cabinets:", nrow(filtered_items), "\n")
cat("Items filtered out:", nrow(item_master) - nrow(filtered_items), "\n")

# --- Step 7: Cabinet configuration ---
num_cabinets <- 24
num_floors_per_cabinet <- 5
total_floors <- num_cabinets * num_floors_per_cabinet

floor_width_mm <- cabinet_width_mm
floor_depth_mm <- cabinet_depth_mm
floor_height_mm <- cabinet_height_mm
floor_volume_m3 <- (floor_width_mm/1000) * (floor_depth_mm/1000) * (floor_height_mm/1000)
total_cabinet_volume <- floor_volume_m3 * total_floors

cat("\n=== CABINET CONFIGURATION ===\n")
cat("Cabinets:", num_cabinets, "| Floors per cabinet:", num_floors_per_cabinet, "\n")
cat("TOTAL FLOORS:", total_floors, "\n")
cat("Floor: W", floor_width_mm, "× D", floor_depth_mm, "× H", floor_height_mm, "mm\n")
cat("Volume per floor:", floor_volume_m3, "m³\n")
cat("Total capacity:", total_cabinet_volume, "m³\n\n")

# --- Step 8-13: Scenario calculation ---
df <- df[order(-df$Viscosity), ]

total_constant <- 48.47
s_constant <- 2
Cr_constant <- 15

scenario_results <- list()

for (top_n in 1:nrow(df)) {
  subset_df <- df[1:top_n, ]
  assigned_volumes <- numeric(top_n)
  benefits <- numeric(top_n)
  sqrt_flows <- sqrt(subset_df$Freq)
  
  for (i in 1:top_n) {
    selected_flow <- sqrt_flows[i]
    other_flows <- sqrt_flows[-i]
    denominator <- selected_flow + sum(other_flows)
    fact <- selected_flow / denominator
    assigned_volumes[i] <- total_constant * fact
    benefits[i] <- s_constant * subset_df$Freq[i] - 
      Cr_constant * (subset_df$Volume[i] / assigned_volumes[i])
  }
  
  scenario_results[[top_n]] <- data.frame(
    Scenario = top_n,
    PartNo = subset_df$PartNo,
    AssignedVolume = assigned_volumes,
    Freq = subset_df$Freq,
    Viscosity = subset_df$Viscosity,
    Benefit = benefits,
    stringsAsFactors = FALSE
  )
}

final_results <- do.call(rbind, scenario_results)
total_benefits <- aggregate(Benefit ~ Scenario, data = final_results, sum)
names(total_benefits)[2] <- "TotalBenefit"
best_scenario_num <- total_benefits$Scenario[which.max(total_benefits$TotalBenefit)]

best_scenario_details <- final_results[final_results$Scenario == best_scenario_num, ]
best_scenario_details <- best_scenario_details[order(-best_scenario_details$Viscosity), ]

# --- Step 14: Merge and calculate DYNAMIC position requirements with FRACTIONAL LOGIC ---
best_scenario_with_boxes <- merge(
  best_scenario_details, 
  filtered_items[, c("PartNo", "PartName", "Width", "Depth", "ModuleSizeH", "CubM")],
  by = "PartNo",
  all.x = TRUE
)

best_scenario_with_boxes <- best_scenario_with_boxes[order(-best_scenario_with_boxes$Viscosity), ]

# 1. How many boxes stack VERTICALLY (in 300mm height)
best_scenario_with_boxes$BoxesPerHeight <- floor(cabinet_height_mm / best_scenario_with_boxes$ModuleSizeH)
best_scenario_with_boxes$BoxesPerHeight <- pmax(best_scenario_with_boxes$BoxesPerHeight, 1)

# 2. How many boxes fit DEPTH-WISE (in 680mm depth)
best_scenario_with_boxes$BoxesPerDepth <- floor(cabinet_depth_mm / best_scenario_with_boxes$Depth)
best_scenario_with_boxes$BoxesPerDepth <- pmax(best_scenario_with_boxes$BoxesPerDepth, 1)

# 3. Boxes per position = stacking in height × stacking in depth
best_scenario_with_boxes$BoxesPerPosition <- best_scenario_with_boxes$BoxesPerHeight * 
  best_scenario_with_boxes$BoxesPerDepth

# 4. DYNAMIC Position dimensions: Uses actual box width (not full cabinet width)
best_scenario_with_boxes$PositionWidth_mm <- best_scenario_with_boxes$Width
best_scenario_with_boxes$PositionDepth_mm <- cabinet_depth_mm
best_scenario_with_boxes$PositionHeight_mm <- cabinet_height_mm

# 5. Position volume (the space ONE position occupies)
best_scenario_with_boxes$PositionVolume_m3 <- (best_scenario_with_boxes$PositionWidth_mm / 1000) * 
  (cabinet_depth_mm / 1000) * 
  (cabinet_height_mm / 1000)

# 6. Total boxes needed for this SKU (from assigned volume)
best_scenario_with_boxes$TotalBoxesNeeded <- best_scenario_with_boxes$AssignedVolume / 
  best_scenario_with_boxes$CubM

# 7. FRACTIONAL POSITION LOGIC (50% rule)
best_scenario_with_boxes$FullPositions <- floor(best_scenario_with_boxes$TotalBoxesNeeded / 
                                                  best_scenario_with_boxes$BoxesPerPosition)
best_scenario_with_boxes$RemainingBoxes <- best_scenario_with_boxes$TotalBoxesNeeded - 
  (best_scenario_with_boxes$FullPositions * best_scenario_with_boxes$BoxesPerPosition)
best_scenario_with_boxes$FractionOfPosition <- best_scenario_with_boxes$RemainingBoxes / 
  best_scenario_with_boxes$BoxesPerPosition

# Apply 50% rule: Add position if fraction > 0.5
best_scenario_with_boxes$PositionsNeeded <- best_scenario_with_boxes$FullPositions + 
  ifelse(best_scenario_with_boxes$FractionOfPosition > 0.5, 1, 0)

# Ensure at least 1 position if boxes are needed
best_scenario_with_boxes$PositionsNeeded <- pmax(best_scenario_with_boxes$PositionsNeeded, 
                                                 ifelse(best_scenario_with_boxes$TotalBoxesNeeded > 0, 1, 0))

# 8. Actual boxes allocated (based on positions created)
best_scenario_with_boxes$ActualBoxesAllocated <- best_scenario_with_boxes$PositionsNeeded * 
  best_scenario_with_boxes$BoxesPerPosition

# 9. Calculate utilization per SKU's own positions
best_scenario_with_boxes$TotalPositionVolume_m3 <- best_scenario_with_boxes$PositionsNeeded * 
  best_scenario_with_boxes$PositionVolume_m3

best_scenario_with_boxes$ActualBoxVolume_m3 <- best_scenario_with_boxes$ActualBoxesAllocated * 
  best_scenario_with_boxes$CubM

best_scenario_with_boxes$PositionUtilization_pct <- 
  ifelse(best_scenario_with_boxes$TotalPositionVolume_m3 > 0,
         (best_scenario_with_boxes$ActualBoxVolume_m3 / best_scenario_with_boxes$TotalPositionVolume_m3) * 100,
         0)

# 10. Total width needed
best_scenario_with_boxes$TotalWidthNeeded_mm <- best_scenario_with_boxes$PositionsNeeded * 
  best_scenario_with_boxes$PositionWidth_mm

cat("\n=== DYNAMIC POSITION CALCULATION WITH FRACTIONAL LOGIC ===\n")
cat("Position width = Actual box width (not full cabinet width)\n")
cat("Fractional rule: Add position if remainder > 50%\n\n")

sample_data <- head(best_scenario_with_boxes[, c("PartNo", "Width", "BoxesPerPosition", 
                                                 "TotalBoxesNeeded", "FullPositions",
                                                 "FractionOfPosition", "PositionsNeeded", 
                                                 "PositionUtilization_pct")], 15)
print(sample_data)

cat("\n=== POSITION VERIFICATION (First 5) ===\n")
for (i in 1:min(5, nrow(best_scenario_with_boxes))) {
  part <- best_scenario_with_boxes[i, ]
  cat("SKU:", part$PartNo, "\n")
  cat("  Box size:", part$Width, "W ×", part$Depth, "D ×", part$ModuleSizeH, "H mm\n")
  cat("  Position size:", part$PositionWidth_mm, "W × 680 D × 300 H mm\n")
  cat("  Position volume:", round(part$PositionVolume_m3, 6), "m³\n")
  cat("  Boxes per position:", part$BoxesPerPosition, "=", part$BoxesPerHeight, "(height) ×", 
      part$BoxesPerDepth, "(depth)\n")
  cat("  Total boxes needed:", round(part$TotalBoxesNeeded, 2), "\n")
  cat("  Full positions:", part$FullPositions, "+ fraction:", round(part$FractionOfPosition, 3), "\n")
  cat("  Positions created:", part$PositionsNeeded, "(fraction", 
      ifelse(part$FractionOfPosition > 0.5, ">", "<="), "0.5)\n")
  cat("  Position utilization:", round(part$PositionUtilization_pct, 2), "%\n\n")
}

# --- Step 15: Initialize floor tracking ---
all_floors <- expand.grid(
  CabinetNo = 1:num_cabinets,
  FloorNo = 1:num_floors_per_cabinet
)
all_floors$FloorID <- paste0("C", sprintf("%02d", all_floors$CabinetNo), "F", all_floors$FloorNo)
all_floors$FloorWidth_mm <- floor_width_mm
all_floors$FloorVolume_m3 <- floor_volume_m3
all_floors$UsedWidth_mm <- 0
all_floors$RemainingWidth_mm <- floor_width_mm
all_floors$UsedPositionVolume_m3 <- 0
all_floors$UsedBoxVolume_m3 <- 0
all_floors$PositionUtilization_pct <- 0
all_floors$VolumeUtilization_pct <- 0
all_floors$NumSKUs <- 0
all_floors$NumPositions <- 0
all_floors$NumBoxes <- 0
all_floors$Status <- "Empty"

# --- Step 16: Floor preferences based on frequency ---
get_floor_preference <- function(freq_rank, total_parts) {
  if (freq_rank <= total_parts / 3) {
    # High frequency: prefer middle floors (3, 2, 4)
    return(c(3, 2, 4, 1, 5))
  } else if (freq_rank <= 2 * total_parts / 3) {
    # Medium frequency: prefer accessible floors (2, 4, 3)
    return(c(2, 4, 3, 1, 5))
  } else {
    # Low frequency: top and bottom (1, 5)
    return(c(1, 5, 2, 4, 3))
  }
}

# --- Step 17: ALLOCATION with Backfilling ---
parts_to_allocate <- best_scenario_with_boxes[
  !is.na(best_scenario_with_boxes$PositionsNeeded) &
    best_scenario_with_boxes$PositionsNeeded > 0, 
]

parts_to_allocate <- parts_to_allocate[order(-parts_to_allocate$Viscosity), ]
parts_to_allocate$FreqRank <- rank(-parts_to_allocate$Freq, ties.method = "first")

total_positions_needed <- sum(parts_to_allocate$PositionsNeeded)
total_width_needed <- sum(parts_to_allocate$TotalWidthNeeded_mm)
total_boxes_needed <- sum(parts_to_allocate$ActualBoxesAllocated)
total_position_volume_needed <- sum(parts_to_allocate$TotalPositionVolume_m3)
total_box_volume_needed <- sum(parts_to_allocate$ActualBoxVolume_m3)

cat("\n=== ALLOCATION REQUIREMENTS ===\n")
cat("SKUs to allocate:", nrow(parts_to_allocate), "\n")
cat("Total positions:", total_positions_needed, "\n")
cat("Total boxes:", total_boxes_needed, "\n")
cat("Avg boxes/position:", round(total_boxes_needed / total_positions_needed, 2), "\n")
cat("Total width needed:", format(total_width_needed, big.mark=","), "mm\n")
cat("Total width available:", format(floor_width_mm * total_floors, big.mark=","), "mm\n")
cat("Width fit:", round((total_width_needed / (floor_width_mm * total_floors)) * 100, 2), "%\n")
cat("Position volume:", round(total_position_volume_needed, 4), "m³\n")
cat("Box volume:", round(total_box_volume_needed, 4), "m³\n")
cat("Total capacity:", round(total_cabinet_volume, 4), "m³\n")
cat("Space utilization:", round((total_position_volume_needed / total_cabinet_volume) * 100, 2), "%\n")
cat("Packing efficiency:", round((total_box_volume_needed / total_position_volume_needed) * 100, 2), "%\n\n")

# Create a list to track positions that have empty space
position_tracker <- list()

allocation_list <- list()
unallocated_skus <- c()

cat("=== PHASE 1: PRIMARY ALLOCATION ===\n")
# First pass: Allocate primary SKUs
for (i in 1:nrow(parts_to_allocate)) {
  part <- parts_to_allocate[i, ]
  
  positions_remaining <- part$PositionsNeeded
  floor_pref <- get_floor_preference(part$FreqRank, nrow(parts_to_allocate))
  
  for (cabinet in 1:num_cabinets) {
    if (positions_remaining <= 0) break
    
    for (floor in floor_pref) {
      if (positions_remaining <= 0) break
      
      floor_idx <- which(all_floors$CabinetNo == cabinet & all_floors$FloorNo == floor)
      if (length(floor_idx) == 0) next
      
      available_width <- all_floors$RemainingWidth_mm[floor_idx]
      positions_can_fit <- floor(available_width / part$PositionWidth_mm)
      
      if (positions_can_fit > 0) {
        positions_to_allocate <- min(positions_remaining, positions_can_fit)
        boxes_to_allocate <- positions_to_allocate * part$BoxesPerPosition
        width_used <- positions_to_allocate * part$PositionWidth_mm
        position_vol_used <- positions_to_allocate * part$PositionVolume_m3
        box_vol_used <- boxes_to_allocate * part$CubM
        
        position_util <- (box_vol_used / position_vol_used) * 100
        
        allocation_list[[length(allocation_list) + 1]] <- data.frame(
          CabinetNo = cabinet,
          FloorNo = floor,
          FloorID = all_floors$FloorID[floor_idx],
          PartNo = part$PartNo,
          PartName = part$PartName,
          Viscosity = part$Viscosity,
          Freq = part$Freq,
          FreqRank = part$FreqRank,
          PositionsAllocated = positions_to_allocate,
          BoxesAllocated = boxes_to_allocate,
          BoxesPerPosition = part$BoxesPerPosition,
          PositionWidth_mm = part$PositionWidth_mm,
          WidthUsed_mm = width_used,
          PositionVolumeUsed_m3 = position_vol_used,
          BoxVolumeUsed_m3 = box_vol_used,
          PositionUtilization_pct = position_util,
          PercentOfFloorWidth = (width_used / floor_width_mm) * 100,
          PercentOfFloorVolume = (position_vol_used / floor_volume_m3) * 100,
          BoxWidth_mm = part$Width,
          BoxDepth_mm = part$Depth,
          BoxHeight_mm = part$ModuleSizeH,
          BoxesPerHeight = part$BoxesPerHeight,
          BoxesPerDepth = part$BoxesPerDepth,
          IsPrimary = TRUE,
          IsBackfill = FALSE,
          stringsAsFactors = FALSE
        )
        
        # Track positions with empty space for backfilling (less than 80% full)
        if (position_util < 80) {
          position_key <- paste(cabinet, floor, part$PartNo, length(allocation_list), sep = "_")
          position_tracker[[position_key]] <- list(
            cabinet = cabinet,
            floor = floor,
            floor_idx = floor_idx,
            primary_sku = part$PartNo,
            empty_volume = position_vol_used - box_vol_used,
            positions = positions_to_allocate,
            position_volume = part$PositionVolume_m3,
            utilization = position_util
          )
        }
        
        # Update floor tracking
        all_floors$UsedWidth_mm[floor_idx] <- all_floors$UsedWidth_mm[floor_idx] + width_used
        all_floors$RemainingWidth_mm[floor_idx] <- all_floors$RemainingWidth_mm[floor_idx] - width_used
        all_floors$UsedPositionVolume_m3[floor_idx] <- all_floors$UsedPositionVolume_m3[floor_idx] + position_vol_used
        all_floors$UsedBoxVolume_m3[floor_idx] <- all_floors$UsedBoxVolume_m3[floor_idx] + box_vol_used
        all_floors$NumSKUs[floor_idx] <- all_floors$NumSKUs[floor_idx] + 1
        all_floors$NumPositions[floor_idx] <- all_floors$NumPositions[floor_idx] + positions_to_allocate
        all_floors$NumBoxes[floor_idx] <- all_floors$NumBoxes[floor_idx] + boxes_to_allocate
        all_floors$Status[floor_idx] <- "In Use"
        
        positions_remaining <- positions_remaining - positions_to_allocate
      }
    }
  }
  
  if (positions_remaining > 0) {
    unallocated_skus <- c(unallocated_skus, part$PartNo)
    cat("WARNING: Incomplete allocation - SKU:", part$PartNo, "| Missing:", positions_remaining, "positions\n")
  }
}

cat("\nPrimary allocation complete.\n")
cat("Positions with <80% utilization:", length(position_tracker), "\n\n")

# Update floor utilization percentages
for (i in 1:nrow(all_floors)) {
  if (all_floors$UsedPositionVolume_m3[i] > 0) {
    all_floors$PositionUtilization_pct[i] <- (all_floors$UsedPositionVolume_m3[i] / floor_volume_m3) * 100
    all_floors$VolumeUtilization_pct[i] <- (all_floors$UsedBoxVolume_m3[i] / floor_volume_m3) * 100
  }
}

# --- Step 18: RESULTS ---
if (length(allocation_list) > 0) {
  cabinet_allocation <- do.call(rbind, allocation_list)
  cabinet_allocation <- cabinet_allocation[order(cabinet_allocation$CabinetNo, 
                                                 cabinet_allocation$FloorNo,
                                                 -cabinet_allocation$Viscosity), ]
  
  # Calculate actual utilization
  total_width_allocated <- sum(all_floors$UsedWidth_mm)
  total_position_vol_allocated <- sum(all_floors$UsedPositionVolume_m3)
  total_box_vol_allocated <- sum(all_floors$UsedBoxVolume_m3)
  total_positions_allocated <- sum(all_floors$NumPositions)
  total_boxes_allocated <- sum(all_floors$NumBoxes)
  floors_in_use <- sum(all_floors$Status == "In Use")
  
  overall_width_util <- (total_width_allocated / (floor_width_mm * total_floors)) * 100
  overall_position_util <- (total_position_vol_allocated / total_cabinet_volume) * 100
  overall_box_util <- (total_box_vol_allocated / total_cabinet_volume) * 100
  packing_efficiency <- (total_box_vol_allocated / total_position_vol_allocated) * 100
  
  cat("\n========================================\n")
  cat("       OVERALL UTILIZATION\n")
  cat("========================================\n")
  cat("WIDTH (Horizontal Space):\n")
  cat("  Used:", format(total_width_allocated, big.mark=","), "mm /",
      format(floor_width_mm * total_floors, big.mark=","), "mm\n")
  cat("  Utilization:", round(overall_width_util, 2), "%\n\n")
  
  cat("POSITION VOLUME (Allocated Space):\n")
  cat("  Used:", round(total_position_vol_allocated, 4), "m³ /", 
      round(total_cabinet_volume, 4), "m³\n")
  cat("  Utilization:", round(overall_position_util, 2), "%\n\n")
  
  cat("BOX VOLUME (Actual Products - Including Backfill):\n")
  cat("  Used:", round(total_box_vol_allocated, 4), "m³ /", 
      round(total_cabinet_volume, 4), "m³\n")
  cat("  Utilization:", round(overall_box_util, 2), "%\n\n")
  
  cat("PACKING EFFICIENCY:\n")
  cat("  (Box volume / Position volume):", round(packing_efficiency, 2), "%\n")
  cat("  Average boxes per position:", round(total_boxes_allocated / total_positions_allocated, 2), "\n\n")
  
  cat("ALLOCATION SUMMARY:\n")
  cat("  Positions:", total_positions_allocated, "/", total_positions_needed, "\n")
  cat("  Boxes:", total_boxes_allocated, "/", total_boxes_needed, "\n")
  cat("  Floors used:", floors_in_use, "/", total_floors, "\n")
  cat("  SKUs with incomplete allocation:", length(unallocated_skus), "\n")
  cat("  Backfill operations:", backfill_count, "\n")
  
  # Export files
  write.csv(cabinet_allocation, "cabinet_allocation_detailed.csv", row.names = FALSE)
  write.csv(all_floors, "all_120_floors_utilization.csv", row.names = FALSE)
  
  cat("\n========================================\n")
  cat("   SAMPLE ALLOCATION (First 30)\n")
  cat("========================================\n")
  sample_cols <- c("FloorID", "PartNo", "PositionsAllocated", "BoxesAllocated",
                   "BoxesPerPosition", "IsPrimary", "IsBackfill", "WidthUsed_mm", "PercentOfFloorWidth")
  print(head(cabinet_allocation[, sample_cols], 30))
  
  cat("\n========================================\n")
  cat("   FLOOR UTILIZATION SUMMARY (Top 10)\n")
  cat("========================================\n")
  top_floors <- all_floors[order(-all_floors$VolumeUtilization_pct), ][1:10, ]
  print(top_floors[, c("FloorID", "NumSKUs", "NumPositions", "NumBoxes", 
                       "PositionUtilization_pct", "VolumeUtilization_pct")])
  
  cat("\n========================================\n")
  cat("   BACKFILL SUMMARY\n")
  cat("========================================\n")
  backfill_records <- cabinet_allocation[cabinet_allocation$IsBackfill == TRUE, ]
  if (nrow(backfill_records) > 0) {
    cat("Total backfilled SKUs:", length(unique(backfill_records$PartNo)), "\n")
    cat("Total backfilled boxes:", sum(backfill_records$BoxesAllocated), "\n")
    cat("Total backfilled volume:", round(sum(backfill_records$BoxVolumeUsed_m3), 4), "m³\n\n")
    cat("Sample backfill records (first 15):\n")
    print(head(backfill_records[, c("FloorID", "PartNo", "BoxesAllocated", "BoxVolumeUsed_m3", "Viscosity")], 15))
  } else {
    cat("No backfill operations performed.\n")
  }
  
  cat("\nFiles exported successfully!\n")
  cat("  - cabinet_allocation_detailed.csv\n")
  cat("  - all_120_floors_utilization.csv\n")
} else {
  cat("\nNo allocations were made.\n")
}