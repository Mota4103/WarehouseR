###############################################################################
# Q3_Slotting.R - Slotting Design (Question 3 - 25 points)
# Multiple SKUs per position based on allocated volume and box size
###############################################################################

library(data.table)
library(ggplot2)

cat("=== Q3: Slotting Design (Multi-SKU per Position) ===\n\n")

### =========================
### FPA Physical Constraints
### =========================
n_cabinets <- 24
n_floors <- 5
total_positions <- n_cabinets * n_floors  # 120 positions

# Each position dimensions
pos_width <- 1.98   # meters (can be subdivided among SKUs)
pos_depth <- 0.68   # meters
pos_height <- 0.30  # meters per level

pos_volume <- pos_width * pos_depth * pos_height  # 0.404 m³

cat("FPA Physical Layout:\n")
cat("  - Cabinets: ", n_cabinets, "\n", sep="")
cat("  - Floors per cabinet: ", n_floors, "\n", sep="")
cat("  - Total positions: ", total_positions, "\n", sep="")
cat("  - Position dimensions: ", pos_width, "m (W) × ", pos_depth, "m (D) × ", pos_height, "m (H)\n", sep="")
cat("  - Position volume: ", round(pos_volume, 4), " m³\n", sep="")
cat("  - Position width can be SUBDIVIDED among multiple SKUs\n", sep="")

# Cabinet Layout: 4 rows × 2 columns × 3 cabinets each
# Numbering: left-to-right, bottom-to-top
# Aisles: between columns, between rows EXCEPT Row 2-3 (back-to-back)
#
#         Column 1              Column 2
#        ___________    |      ___________
# Row 4: [19][20][21]   |      [22][23][24]   <- Top
#                       |
#        ~~~~~~~ AISLE ~|~ AISLE ~~~~~~~
#        ___________    |      ___________
# Row 3: [13][14][15]   |      [16][17][18]
#        ___________    |      ___________    <- BACK-TO-BACK
# Row 2: [7] [8] [9]    |      [10][11][12]
#                       |
#        ~~~~~~~ AISLE ~|~ AISLE ~~~~~~~
#        ___________    |      ___________
# Row 1: [1] [2] [3]    |      [4] [5] [6]    <- Bottom (start)

cat("  - Layout: 4 rows × 2 columns × 3 cabinets\n")
cat("  - Row 2 & 3 are back-to-back (no aisle)\n\n")

# Define cabinet positions for distance calculation
get_cabinet_info <- function(cab) {
  row <- ceiling(cab / 6)
  col <- ifelse((cab - 1) %% 6 < 3, 1, 2)
  pos_in_row <- ((cab - 1) %% 3) + 1  # 1, 2, or 3
  return(list(row = row, col = col, pos = pos_in_row))
}

# Check if two cabinets are adjacent (can walk directly between them)
are_adjacent <- function(cab1, cab2) {
  info1 <- get_cabinet_info(cab1)
  info2 <- get_cabinet_info(cab2)

  # Same row, same column, adjacent position (can walk along the row)
  if (info1$row == info2$row && info1$col == info2$col && abs(info1$pos - info2$pos) == 1) {
    return(TRUE)
  }

  # NOTE: Back-to-back (Row 2-3) is NOT adjacent - can't walk through!

  return(FALSE)
}

# Get adjacent cabinets for a given cabinet
get_adjacent_cabinets <- function(cab) {
  adj <- c()
  for (other in 1:24) {
    if (other != cab && are_adjacent(cab, other)) {
      adj <- c(adj, other)
    }
  }
  return(adj)
}

### =========================
### STEP 1: Load Data
### =========================
cat("Loading data...\n")

if (!file.exists("Q2_FPA_Optimal_SKUs.csv")) {
  stop("Q2_FPA_Optimal_SKUs.csv not found. Please run Q2_FluidModel.R first.")
}

optimal_skus <- fread("Q2_FPA_Optimal_SKUs.csv")
itemMaster <- fread("itemMaster.txt", sep = ",", header = TRUE)

cat("  - Optimal SKUs from Q2: ", nrow(optimal_skus), " items\n", sep="")

### =========================
### STEP 2: Clean and Prepare Data
### =========================
setnames(itemMaster, names(itemMaster), gsub("[ .]", "", names(itemMaster)))

if ("PartNo" %in% names(itemMaster) == FALSE) {
  old_names <- names(itemMaster)[1:9]
  new_names <- c("Skus", "PartNo", "PartName", "BoxType", "UnitLabelQt",
                 "ModuleSizeL", "ModuleSizeV", "ModuleSizeH", "CubM")
  setnames(itemMaster, old_names, new_names)
}

if ("Partname" %in% names(itemMaster)) {
  setnames(itemMaster, "Partname", "PartName", skip_absent = TRUE)
}

itemMaster[, PartNo := gsub("[ ]", "", PartNo)]
itemMaster[, ModuleSizeL := as.numeric(gsub(",", "", ModuleSizeL))]
itemMaster[, ModuleSizeV := as.numeric(gsub(",", "", ModuleSizeV))]
itemMaster[, ModuleSizeH := as.numeric(gsub(",", "", ModuleSizeH))]
itemMaster[, CubM := as.numeric(gsub(",", "", CubM))]

# Convert to meters
itemMaster[, BoxWidth_m := ModuleSizeL / 1000]
itemMaster[, BoxDepth_m := ModuleSizeV / 1000]
itemMaster[, BoxHeight_m := ModuleSizeH / 1000]

### =========================
### STEP 3: Merge SKU Info and Calculate Width Needed
### =========================
cat("Calculating width needed per SKU...\n")

slotting <- merge(
  optimal_skus,
  itemMaster[, .(PartNo, PartName, BoxWidth_m, BoxDepth_m, BoxHeight_m, CubM)],
  by = "PartNo",
  all.x = TRUE
)

# Calculate how many boxes fit in depth and height of position
slotting[, BoxesInDepth := pmax(1, floor(pos_depth / BoxDepth_m))]
slotting[, BoxesInHeight := pmax(1, floor(pos_height / BoxHeight_m))]
slotting[, BoxesPerColumn := BoxesInDepth * BoxesInHeight]

# Calculate total boxes needed to hold allocated volume
slotting[, TotalBoxesNeeded := ceiling(AllocatedVolume_m3 / CubM)]

# Calculate how many columns (width-wise) needed
slotting[, ColumnsNeeded := ceiling(TotalBoxesNeeded / BoxesPerColumn)]

# Calculate width needed in meters
slotting[, WidthNeeded_m := ColumnsNeeded * BoxWidth_m]

# Handle NA values
slotting[is.na(WidthNeeded_m), WidthNeeded_m := 0.2]  # Default 20cm
slotting[WidthNeeded_m > pos_width, WidthNeeded_m := pos_width]  # Cap at position width

# Sort by FREQUENCY (highest first for golden zone priority)
# Frequency is better for ergonomic floor assignment:
# - Higher frequency = more picks = more bending/reaching
# - Put highest frequency items at most ergonomic floors
setorder(slotting, -Frequency)
slotting[, FrequencyRank := 1:.N]

# Also keep viscosity rank for reference
setorder(slotting, -Viscosity)
slotting[, ViscosityRank := 1:.N]

# Extract prefix for grouping (first 2-3 characters)
slotting[, Prefix := substr(PartNo, 1, 3)]

# Count items per prefix to identify major groups
prefix_counts <- slotting[, .(Count = .N, TotalFreq = sum(Frequency)), by = Prefix]
setorder(prefix_counts, -Count)

cat("  - Total width needed: ", round(sum(slotting$WidthNeeded_m), 2), " m\n", sep="")
cat("  - Total width available: ", n_cabinets * n_floors * pos_width, " m\n", sep="")
cat("  - Prefix groups found: ", nrow(prefix_counts), "\n", sep="")
cat("  - Top prefixes: ", paste(head(prefix_counts$Prefix, 5), collapse=", "), "\n\n", sep="")

### =========================
### STEP 4: Association Analysis (BEFORE Slotting)
### =========================
cat("Running Association Analysis FIRST (for slotting priority)...\n")

# Load shipTrans for co-occurrence
shipTrans <- fread("shipTrans.txt", sep = ",", header = TRUE)
setnames(shipTrans, names(shipTrans), gsub("[ .]", "", names(shipTrans)))
shipTrans[, PartNo := gsub("[ ]", "", PartNo)]

fpa_skus <- slotting$PartNo

# Pattern Matching (LH/RH, A/B)
fpa_items <- slotting[, .(PartNo, PartName)]

pattern_pairs <- data.table()
for (i in 1:nrow(fpa_items)) {
  pn <- fpa_items$PartNo[i]
  pname <- fpa_items$PartName[i]
  if (is.na(pname)) next

  # Check for A/B variants
  if (grepl("A$", pn)) {
    b_pn <- sub("A$", "B", pn)
    if (b_pn %in% fpa_items$PartNo) {
      pattern_pairs <- rbind(pattern_pairs, data.table(Item1 = pn, Item2 = b_pn, Type = "A-B"))
    }
  }

  # Check for LH/RH in name
  if (grepl(",LH|LH,|-LH", pname, ignore.case = TRUE)) {
    rh_name <- gsub(",LH|LH,|-LH", ",RH", pname, ignore.case = TRUE)
    rh_match <- fpa_items[grepl(gsub(",RH", "", rh_name), PartName, ignore.case = TRUE) &
                           grepl("RH", PartName, ignore.case = TRUE), PartNo]
    for (rh in rh_match) {
      if (rh != pn) {
        pattern_pairs <- rbind(pattern_pairs, data.table(Item1 = pn, Item2 = rh, Type = "LH-RH"))
      }
    }
  }
}

cat("  - Pattern pairs (LH/RH, A/B): ", nrow(pattern_pairs), "\n", sep="")

# Co-occurrence Analysis
shipTrans[, ShippingDay := as.Date(as.character(ShippingDay), "%Y%m%d")]
shipTrans_fpa <- shipTrans[PartNo %in% fpa_skus]

delivery_col <- grep("DeliveryNo", names(shipTrans_fpa), value = TRUE)[1]
pair_counts <- data.table()

if (!is.null(delivery_col) && length(delivery_col) > 0) {
  shipTrans_fpa[, BasketKey := paste(ShippingDay, get(delivery_col), sep = "_")]

  baskets <- shipTrans_fpa[, .(Items = list(unique(PartNo))), by = BasketKey]

  # Count co-occurrences
  cooc_list <- list()
  for (b in 1:nrow(baskets)) {
    items <- baskets$Items[[b]]
    if (length(items) >= 2 && length(items) <= 30) {
      pairs <- t(combn(sort(items), 2))
      cooc_list[[b]] <- data.table(Item1 = pairs[,1], Item2 = pairs[,2])
    }
  }

  if (length(cooc_list) > 0) {
    cooc_pairs <- rbindlist(cooc_list)
    pair_counts <- cooc_pairs[, .(Count = .N), by = .(Item1, Item2)]
    setorder(pair_counts, -Count)
    cat("  - Co-occurrence pairs found: ", nrow(pair_counts), "\n", sep="")
  }
}

# Combine association scores
all_pairs <- unique(rbind(
  if (nrow(pattern_pairs) > 0) pattern_pairs[, .(Item1, Item2)] else data.table(),
  if (nrow(pair_counts) > 0) pair_counts[Count >= 5, .(Item1, Item2)] else data.table()
))

if (nrow(all_pairs) > 0) {
  all_pairs[, PatternScore := 0]
  all_pairs[, CoocScore := 0]

  if (nrow(pattern_pairs) > 0) {
    for (j in 1:nrow(pattern_pairs)) {
      all_pairs[Item1 == pattern_pairs$Item1[j] & Item2 == pattern_pairs$Item2[j],
                PatternScore := 100]
    }
  }

  if (nrow(pair_counts) > 0) {
    max_count <- max(pair_counts$Count)
    for (j in 1:nrow(pair_counts)) {
      all_pairs[Item1 == pair_counts$Item1[j] & Item2 == pair_counts$Item2[j],
                CoocScore := (pair_counts$Count[j] / max_count) * 50]
    }
  }

  all_pairs[, TotalScore := PatternScore + CoocScore]
  setorder(all_pairs, -TotalScore)
  cat("  - Total association pairs: ", nrow(all_pairs), "\n", sep="")
} else {
  all_pairs <- data.table()
}

# Build association lookup for slotting
slotting[, AssociatedWith := ""]
slotting[, AssociationGroup := 0L]

# Create association groups (items that should be placed together)
if (nrow(all_pairs) > 0) {
  top_pairs <- all_pairs[TotalScore >= 30]

  # Build adjacency list
  adj_list <- list()
  for (j in 1:nrow(top_pairs)) {
    item1 <- top_pairs$Item1[j]
    item2 <- top_pairs$Item2[j]

    if (is.null(adj_list[[item1]])) adj_list[[item1]] <- c()
    if (is.null(adj_list[[item2]])) adj_list[[item2]] <- c()

    adj_list[[item1]] <- unique(c(adj_list[[item1]], item2))
    adj_list[[item2]] <- unique(c(adj_list[[item2]], item1))

    # Store in slotting
    slotting[PartNo == item1, AssociatedWith := paste0(AssociatedWith,
                                                        ifelse(AssociatedWith == "", "", ","), item2)]
    slotting[PartNo == item2, AssociatedWith := paste0(AssociatedWith,
                                                        ifelse(AssociatedWith == "", "", ","), item1)]
  }

  # Assign association groups using connected components
  group_id <- 1
  visited <- c()

  for (item in names(adj_list)) {
    if (item %in% visited) next

    # BFS to find all connected items
    queue <- c(item)
    group_items <- c()

    while (length(queue) > 0) {
      current <- queue[1]
      queue <- queue[-1]

      if (current %in% visited) next
      visited <- c(visited, current)
      group_items <- c(group_items, current)

      neighbors <- adj_list[[current]]
      for (n in neighbors) {
        if (!(n %in% visited)) {
          queue <- c(queue, n)
        }
      }
    }

    # Assign group ID
    slotting[PartNo %in% group_items, AssociationGroup := group_id]
    group_id <- group_id + 1
  }

  cat("  - Association groups created: ", group_id - 1, "\n\n", sep="")
} else {
  cat("  - No association pairs found\n\n")
}

### =========================
### STEP 5: Pack SKUs into Positions (Association-Aware Bin Packing)
### =========================
cat("Packing SKUs into positions (association-aware, multi-SKU per position)...\n\n")

# Floor priority: 3 (golden) → 2 → 4 → 1 → 5
floor_priority <- c(3, 2, 4, 1, 5)

# Initialize position tracking
position_remaining <- matrix(pos_width, nrow = n_cabinets, ncol = n_floors)

# Initialize assignment columns
slotting[, Cabinet := NA_integer_]
slotting[, Floor := NA_integer_]
slotting[, SubPosStart_m := NA_real_]
slotting[, SubPosEnd_m := NA_real_]
slotting[, PositionID := NA_character_]

# Helper function to assign SKU to position
assign_sku <- function(idx, cab, floor, position_remaining, slotting) {
  width_needed <- slotting$WidthNeeded_m[idx]
  remaining <- position_remaining[cab, floor]

  if (remaining >= width_needed) {
    start_pos <- pos_width - remaining
    end_pos <- start_pos + width_needed

    slotting[idx, Cabinet := cab]
    slotting[idx, Floor := floor]
    slotting[idx, SubPosStart_m := start_pos]
    slotting[idx, SubPosEnd_m := end_pos]
    slotting[idx, PositionID := paste0("C", sprintf("%02d", cab), "F", floor)]

    position_remaining[cab, floor] <- remaining - width_needed
    return(TRUE)
  }
  return(FALSE)
}

# Process order (Priority: Association > Frequency > Prefix):
# 1. Association groups first (items picked together)
# 2. Then by Frequency (ergonomic floor assignment)
# 3. Prefix is handled during placement (lowest priority)
slotting[, ProcessOrder := FrequencyRank * 100 - (AssociationGroup > 0) * 5000]
setorder(slotting, ProcessOrder)

cat("Priority: 1) Association → 2) Frequency → 3) Prefix (lowest)\n")

skus_assigned <- 0
skus_not_fit <- 0
association_together <- 0
prefix_together <- 0

for (i in 1:nrow(slotting)) {
  if (!is.na(slotting$Cabinet[i])) next  # Already assigned

  width_needed <- slotting$WidthNeeded_m[i]
  current_sku <- slotting$PartNo[i]
  current_prefix <- slotting$Prefix[i]
  assoc_group <- slotting$AssociationGroup[i]
  assigned <- FALSE

  # PRIORITY 1: If this SKU has associated items already placed, try to place near them
  if (assoc_group > 0) {
    placed_assoc <- slotting[AssociationGroup == assoc_group & !is.na(Cabinet)]

    if (nrow(placed_assoc) > 0) {
      # Try same position as associated items first
      for (row in 1:nrow(placed_assoc)) {
        target_cab <- placed_assoc$Cabinet[row]
        target_floor <- placed_assoc$Floor[row]

        remaining <- position_remaining[target_cab, target_floor]
        if (remaining >= width_needed) {
          start_pos <- pos_width - remaining
          end_pos <- start_pos + width_needed

          slotting[i, Cabinet := target_cab]
          slotting[i, Floor := target_floor]
          slotting[i, SubPosStart_m := start_pos]
          slotting[i, SubPosEnd_m := end_pos]
          slotting[i, PositionID := paste0("C", sprintf("%02d", target_cab), "F", target_floor)]

          position_remaining[target_cab, target_floor] <- remaining - width_needed
          assigned <- TRUE
          association_together <- association_together + 1
          break
        }
      }

      # If not same position, try ACTUALLY adjacent cabinets (using layout)
      if (!assigned) {
        for (row in 1:nrow(placed_assoc)) {
          target_cab <- placed_assoc$Cabinet[row]
          target_floor <- placed_assoc$Floor[row]

          # Get truly adjacent cabinets based on physical layout
          adj_cabs <- get_adjacent_cabinets(target_cab)

          for (adj_cab in adj_cabs) {
            remaining <- position_remaining[adj_cab, target_floor]
            if (remaining >= width_needed) {
              start_pos <- pos_width - remaining
              end_pos <- start_pos + width_needed

              slotting[i, Cabinet := adj_cab]
              slotting[i, Floor := target_floor]
              slotting[i, SubPosStart_m := start_pos]
              slotting[i, SubPosEnd_m := end_pos]
              slotting[i, PositionID := paste0("C", sprintf("%02d", adj_cab), "F", target_floor)]

              position_remaining[adj_cab, target_floor] <- remaining - width_needed
              assigned <- TRUE
              association_together <- association_together + 1
              break
            }
          }
          if (assigned) break
        }
      }
    }
  }

  # PRIORITY 2: Try to place near same-prefix items (product family grouping)
  if (!assigned) {
    placed_prefix <- slotting[Prefix == current_prefix & !is.na(Cabinet)]

    if (nrow(placed_prefix) > 0) {
      # Get the most common cabinet for this prefix
      prefix_cabs <- placed_prefix[, .N, by = Cabinet]
      setorder(prefix_cabs, -N)

      for (pc in 1:nrow(prefix_cabs)) {
        target_cab <- prefix_cabs$Cabinet[pc]

        # Try all floors in priority order for this cabinet
        for (floor in floor_priority) {
          remaining <- position_remaining[target_cab, floor]
          if (remaining >= width_needed) {
            start_pos <- pos_width - remaining
            end_pos <- start_pos + width_needed

            slotting[i, Cabinet := target_cab]
            slotting[i, Floor := floor]
            slotting[i, SubPosStart_m := start_pos]
            slotting[i, SubPosEnd_m := end_pos]
            slotting[i, PositionID := paste0("C", sprintf("%02d", target_cab), "F", floor)]

            position_remaining[target_cab, floor] <- remaining - width_needed
            assigned <- TRUE
            prefix_together <- prefix_together + 1
            break
          }
        }
        if (assigned) break

        # Try ACTUALLY adjacent cabinets (using layout)
        adj_cabs <- get_adjacent_cabinets(target_cab)
        for (adj_cab in adj_cabs) {
          for (floor in floor_priority) {
            remaining <- position_remaining[adj_cab, floor]
            if (remaining >= width_needed) {
              start_pos <- pos_width - remaining
              end_pos <- start_pos + width_needed

              slotting[i, Cabinet := adj_cab]
              slotting[i, Floor := floor]
              slotting[i, SubPosStart_m := start_pos]
              slotting[i, SubPosEnd_m := end_pos]
              slotting[i, PositionID := paste0("C", sprintf("%02d", adj_cab), "F", floor)]

              position_remaining[adj_cab, floor] <- remaining - width_needed
              assigned <- TRUE
              prefix_together <- prefix_together + 1
              break
            }
          }
          if (assigned) break
        }
        if (assigned) break
      }
    }
  }

  # PRIORITY 3: Standard algorithm (floor priority, first fit)
  if (!assigned) {
    for (floor in floor_priority) {
      if (assigned) break

      for (cab in 1:n_cabinets) {
        remaining <- position_remaining[cab, floor]

        if (remaining >= width_needed) {
          start_pos <- pos_width - remaining
          end_pos <- start_pos + width_needed

          slotting[i, Cabinet := cab]
          slotting[i, Floor := floor]
          slotting[i, SubPosStart_m := start_pos]
          slotting[i, SubPosEnd_m := end_pos]
          slotting[i, PositionID := paste0("C", sprintf("%02d", cab), "F", floor)]

          position_remaining[cab, floor] <- remaining - width_needed
          assigned <- TRUE
          break
        }
      }
    }
  }

  if (assigned) {
    skus_assigned <- skus_assigned + 1
  } else {
    skus_not_fit <- skus_not_fit + 1
  }
}

cat("  - SKUs assigned: ", skus_assigned, "\n", sep="")
cat("  - SKUs not fitting: ", skus_not_fit, "\n", sep="")
cat("  - Associated pairs placed together: ", association_together, "\n", sep="")
cat("  - Prefix-grouped placements: ", prefix_together, "\n\n", sep="")

# Calculate X, Y coordinates for visualization (based on 4x2x3 layout)
# Convert cabinet number to row, column, position
slotting[!is.na(Cabinet), CabRow := ceiling(Cabinet / 6)]
slotting[!is.na(Cabinet), CabCol := ifelse((Cabinet - 1) %% 6 < 3, 1, 2)]
slotting[!is.na(Cabinet), CabPosInRow := ((Cabinet - 1) %% 3) + 1]

# X coordinate: based on column and position within row
# Column 1: positions 0-2 (cabinets at x = 0, 2.5, 5)
# Column 2: positions 0-2 (cabinets at x = 8, 10.5, 13) with aisle gap
cabinet_spacing <- 2.5  # meters between cabinet centers
aisle_gap <- 3.0        # gap between columns (aisle)

slotting[!is.na(Cabinet), X := (CabCol - 1) * (3 * cabinet_spacing + aisle_gap) +
                                (CabPosInRow - 1) * cabinet_spacing +
                                SubPosStart_m + (SubPosEnd_m - SubPosStart_m)/2]

# Y coordinate: based on row (with gap for aisle between rows 1-2 and 3-4)
row_height <- 2.0       # vertical spacing per row
aisle_height <- 1.5     # vertical gap for aisle

slotting[!is.na(Cabinet), Y_row :=
           (CabRow - 1) * row_height +
           ifelse(CabRow >= 2, aisle_height, 0) +    # Aisle after row 1
           ifelse(CabRow >= 4, aisle_height, 0) +    # Aisle after row 3 (2-3 back-to-back)
           Floor * 0.4]  # Floor height within cabinet

# Add ergonomic score
ergonomic_scores <- c("1" = 60, "2" = 90, "3" = 100, "4" = 90, "5" = 60)
slotting[!is.na(Floor), ErgonomicScore := ergonomic_scores[as.character(Floor)]]

# Re-sort by ViscosityRank for output
setorder(slotting, ViscosityRank)

### =========================
### STEP 6: Summary Statistics
### =========================
cat("=== SLOTTING SUMMARY ===\n\n")

# Count SKUs per position
position_summary <- slotting[!is.na(Cabinet), .(
  SKUsInPosition = .N,
  TotalFrequency = sum(Frequency),
  TotalWidth_m = sum(WidthNeeded_m),
  WidthUsed_pct = round(sum(WidthNeeded_m) / pos_width * 100, 1)
), by = .(Cabinet, Floor)]

cat("Position Utilization:\n")
cat("  - Positions with 1 SKU: ", sum(position_summary$SKUsInPosition == 1), "\n", sep="")
cat("  - Positions with 2 SKUs: ", sum(position_summary$SKUsInPosition == 2), "\n", sep="")
cat("  - Positions with 3+ SKUs: ", sum(position_summary$SKUsInPosition >= 3), "\n", sep="")
cat("  - Average SKUs per position: ", round(mean(position_summary$SKUsInPosition), 2), "\n", sep="")
cat("  - Average width utilization: ", round(mean(position_summary$WidthUsed_pct), 1), "%\n\n", sep="")

# Floor summary
floor_summary <- slotting[!is.na(Floor), .(
  SKUs = .N,
  Positions = uniqueN(paste(Cabinet, Floor)),
  TotalFrequency = sum(Frequency),
  AvgViscosity = round(mean(Viscosity), 0),
  AvgSKUsPerPos = round(.N / uniqueN(paste(Cabinet, Floor)), 2)
), by = Floor]
setorder(floor_summary, Floor)

cat("Floor Summary:\n")
print(floor_summary)

# Prefix grouping summary
cat("\nPrefix Grouping Summary:\n")
prefix_summary <- slotting[!is.na(Cabinet), .(
  SKUs = .N,
  Cabinets = uniqueN(Cabinet),
  CabinetRange = paste0(min(Cabinet), "-", max(Cabinet)),
  TotalFreq = sum(Frequency)
), by = Prefix]
setorder(prefix_summary, -SKUs)
print(head(prefix_summary, 10))

# Re-sort by FrequencyRank for display
setorder(slotting, FrequencyRank)

cat("\nTop 20 SKUs (highest frequency - ergonomic priority):\n")
print(slotting[1:min(20, .N), .(
  FreqRank = FrequencyRank, PartNo, Frequency,
  Viscosity = round(Viscosity, 0),
  Width_m = round(WidthNeeded_m, 3),
  Cabinet, Floor,
  SubPos = paste0(round(SubPosStart_m, 2), "-", round(SubPosEnd_m, 2), "m")
)])

### =========================
### STEP 7: Save Results
### =========================
cat("\nSaving results...\n")

output_cols <- c("FrequencyRank", "ViscosityRank", "PartNo", "PartName", "Prefix", "Frequency", "DemandVolume_m3",
                 "Viscosity", "AllocatedVolume_m3", "Benefit", "ReplenishTrips",
                 "BoxWidth_m", "BoxDepth_m", "BoxHeight_m", "TotalBoxesNeeded",
                 "WidthNeeded_m", "Cabinet", "Floor", "PositionID",
                 "SubPosStart_m", "SubPosEnd_m", "X", "Y",
                 "ErgonomicScore", "AssociatedWith", "AssociationGroup")

output_cols <- intersect(output_cols, names(slotting))
fwrite(slotting[, ..output_cols], "Q3_slotting_result.csv")
cat("  - Saved: Q3_slotting_result.csv (", nrow(slotting), " SKUs)\n", sep="")

fwrite(all_pairs, "Q3_association_pairs.csv")
cat("  - Saved: Q3_association_pairs.csv\n")

fwrite(position_summary, "Q3_position_utilization.csv")
cat("  - Saved: Q3_position_utilization.csv\n")

### =========================
### STEP 8: Visualizations
### =========================
cat("\nCreating visualizations...\n")

# 1. Multi-SKU Layout View (4 rows × 2 columns × 3 cabinets)
assigned_skus <- slotting[!is.na(Cabinet)]

# Calculate proper x/y coordinates for 4x2x3 layout
assigned_skus[, PlotX := (CabCol - 1) * (3 * cabinet_spacing + aisle_gap) +
                         (CabPosInRow - 1) * cabinet_spacing + SubPosStart_m]
assigned_skus[, PlotXEnd := (CabCol - 1) * (3 * cabinet_spacing + aisle_gap) +
                            (CabPosInRow - 1) * cabinet_spacing + SubPosEnd_m]
assigned_skus[, PlotY := CabRow]

# Create labels for cabinet positions
cabinet_labels <- data.table(
  Cabinet = 1:24,
  CabRow = ceiling(1:24 / 6),
  CabCol = ifelse((1:24 - 1) %% 6 < 3, 1, 2),
  CabPosInRow = ((1:24 - 1) %% 3) + 1
)
cabinet_labels[, PlotX := (CabCol - 1) * (3 * cabinet_spacing + aisle_gap) +
                          (CabPosInRow - 1) * cabinet_spacing + pos_width/2]
cabinet_labels[, PlotY := CabRow]

p_layout <- ggplot() +
  # Background for cabinets
  geom_rect(data = cabinet_labels, aes(xmin = PlotX - pos_width/2, xmax = PlotX + pos_width/2,
                                        ymin = PlotY - 0.4, ymax = PlotY + 0.4),
            fill = "gray90", color = "gray50", linewidth = 0.5) +
  # SKU boxes
  geom_rect(data = assigned_skus, aes(xmin = PlotX, xmax = PlotXEnd,
                                       ymin = PlotY - 0.3 + (Floor-1)*0.12,
                                       ymax = PlotY - 0.3 + Floor*0.12,
                                       fill = log10(Frequency + 1)),
            color = "white", linewidth = 0.1) +
  # Cabinet number labels
  geom_text(data = cabinet_labels, aes(x = PlotX, y = PlotY + 0.5, label = Cabinet),
            size = 3, fontface = "bold") +
  # Aisle labels
  annotate("text", x = 6, y = 1.5, label = "=== AISLE ===", size = 3, color = "gray40") +
  annotate("text", x = 6, y = 2.5, label = "BACK-TO-BACK", size = 2.5, color = "red", fontface = "italic") +
  annotate("text", x = 6, y = 3.5, label = "=== AISLE ===", size = 3, color = "gray40") +
  annotate("text", x = 5.5, y = 0.5, label = "AISLE", size = 2.5, color = "gray40", angle = 90) +
  scale_fill_gradient(low = "steelblue", high = "darkred",
                      name = "Log10(Freq)",
                      breaks = c(2, 2.5, 3, 3.5, 4),
                      labels = c("100", "316", "1K", "3.2K", "10K")) +
  scale_y_continuous(breaks = 1:4, labels = paste("Row", 1:4)) +
  scale_x_continuous(breaks = c(1, 4, 9, 12), labels = c("Col 1", "Center", "Col 2", "")) +
  labs(
    title = "FPA Layout - 4 Rows × 2 Columns × 3 Cabinets",
    subtitle = paste0(nrow(assigned_skus), " SKUs in ", nrow(position_summary), " positions | ",
                      "Cabinet numbers shown above | Floors 1-5 stacked within each cabinet"),
    x = "Position",
    y = "Row"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(size = 14, face = "bold"),
    panel.grid.major = element_line(color = "gray80")
  )

ggsave("Q3_fpa_layout.png", p_layout, width = 14, height = 10, dpi = 150)
cat("  - Saved: Q3_fpa_layout.png\n")

# 2. Position Utilization Heatmap (4×2×3 layout)
# Add cabinet info to position summary
position_summary[, CabRow := ceiling(Cabinet / 6)]
position_summary[, CabCol := ifelse((Cabinet - 1) %% 6 < 3, 1, 2)]
position_summary[, CabPosInRow := ((Cabinet - 1) %% 3) + 1]
position_summary[, PlotX := (CabCol - 1) * 4 + CabPosInRow]
position_summary[, PlotY := CabRow]

# Create cabinet labels for facets
position_summary[, RowLabel := paste("Row", CabRow)]
position_summary[, ColLabel := paste("Column", CabCol)]

p_util <- ggplot(position_summary, aes(x = factor(CabPosInRow), y = factor(Floor))) +
  geom_tile(aes(fill = SKUsInPosition), color = "white") +
  geom_text(aes(label = paste0("C", Cabinet, "\n", SKUsInPosition, " SKU\n", WidthUsed_pct, "%")),
            size = 2, color = "white") +
  facet_grid(CabRow ~ CabCol, labeller = labeller(
    CabRow = c("1" = "Row 1 (Bottom)", "2" = "Row 2", "3" = "Row 3", "4" = "Row 4 (Top)"),
    CabCol = c("1" = "Column 1", "2" = "Column 2")
  )) +
  scale_fill_gradient(low = "steelblue", high = "darkred", name = "SKUs\nper Pos") +
  scale_y_discrete(limits = rev(c("1", "2", "3", "4", "5"))) +
  scale_x_discrete(labels = c("Pos 1", "Pos 2", "Pos 3")) +
  labs(
    title = "Position Utilization - 4 Rows × 2 Columns × 3 Cabinets",
    subtitle = "Each cell shows Cabinet#, SKU count, and width utilization % | Note: Row 2-3 are back-to-back",
    x = "Position within Row",
    y = "Floor Level"
  ) +
  theme_minimal() +
  theme(
    strip.background = element_rect(fill = "gray30"),
    strip.text = element_text(color = "white", face = "bold")
  )

ggsave("Q3_position_utilization.png", p_util, width = 12, height = 12, dpi = 150)
cat("  - Saved: Q3_position_utilization.png\n")

# 3. Floor Distribution
floor_summary[, Ergonomic := c("Lower", "Good", "GOLDEN ZONE", "Good", "Upper")]

p_floor <- ggplot(floor_summary, aes(x = factor(Floor), y = SKUs)) +
  geom_bar(stat = "identity", aes(fill = Ergonomic)) +
  geom_text(aes(label = paste0(SKUs, " SKUs\n~", AvgSKUsPerPos, "/pos")),
            vjust = -0.3, size = 3) +
  scale_fill_manual(values = c("GOLDEN ZONE" = "gold", "Good" = "steelblue",
                               "Lower" = "gray50", "Upper" = "gray50")) +
  labs(
    title = "SKU Distribution by Floor",
    subtitle = paste0("Total ", sum(floor_summary$SKUs), " SKUs | Multiple SKUs per position"),
    x = "Floor Level",
    y = "Number of SKUs"
  ) +
  theme_minimal() +
  theme(legend.position = "bottom")

ggsave("Q3_floor_distribution.png", p_floor, width = 10, height = 7, dpi = 150)
cat("  - Saved: Q3_floor_distribution.png\n")

# 4. Detailed floor views (with 4×2×3 layout and dynamic text sizing)
for (f in 1:5) {
  floor_data <- slotting[Floor == f]
  if (nrow(floor_data) == 0) next

  # Calculate width ratio for each SKU to determine text size
  floor_data[, WidthRatio := (SubPosEnd_m - SubPosStart_m) / pos_width]

  # Create label - shorter for narrow boxes
  floor_data[, Label := ifelse(WidthRatio >= 0.5,
                                paste0(substr(PartNo, 1, 8), "\n", Frequency),
                                ifelse(WidthRatio >= 0.3,
                                       substr(PartNo, 1, 6),
                                       substr(PartNo, 1, 4)))]

  # Dynamic text size based on width
  floor_data[, TextSize := ifelse(WidthRatio >= 0.5, 2.0,
                                   ifelse(WidthRatio >= 0.3, 1.5, 1.2))]

  # Calculate plot positions using 4×2×3 layout
  floor_data[, PlotX := (CabCol - 1) * 4 + (CabPosInRow - 1) + SubPosStart_m/pos_width]
  floor_data[, PlotXEnd := (CabCol - 1) * 4 + (CabPosInRow - 1) + SubPosEnd_m/pos_width]

  # Create cabinet position markers
  cab_markers <- data.table(
    Cabinet = 1:24,
    CabRow = ceiling(1:24 / 6),
    CabCol = ifelse((1:24 - 1) %% 6 < 3, 1, 2),
    CabPosInRow = ((1:24 - 1) %% 3) + 1
  )
  cab_markers[, PlotX := (CabCol - 1) * 4 + (CabPosInRow - 1) + 0.5]

  p <- ggplot() +
    # Cabinet background outlines
    geom_rect(data = cab_markers, aes(xmin = PlotX - 0.5, xmax = PlotX + 0.5,
                                       ymin = 0.05, ymax = 0.95),
              fill = "gray95", color = "gray50", linewidth = 0.3) +
    # SKU boxes
    geom_rect(data = floor_data, aes(xmin = PlotX, xmax = PlotXEnd,
                                      ymin = 0.1, ymax = 0.9, fill = Frequency),
              color = "black", linewidth = 0.3) +
    geom_text(data = floor_data, aes(x = (PlotX + PlotXEnd)/2, y = 0.5,
                                      label = Label, size = TextSize),
              color = "white", fontface = "bold", show.legend = FALSE) +
    # Cabinet number labels at top
    geom_text(data = cab_markers, aes(x = PlotX, y = 1.1, label = Cabinet),
              size = 2.5, fontface = "bold") +
    # Aisle separator line
    geom_vline(xintercept = 3.5, color = "gray30", linewidth = 1, linetype = "dashed") +
    annotate("text", x = 3.5, y = 1.2, label = "AISLE", size = 2.5, color = "gray40") +
    scale_size_identity() +
    scale_fill_gradient(low = "steelblue", high = "red", name = "Frequency") +
    scale_x_continuous(breaks = c(1.5, 5.5), labels = c("Column 1", "Column 2")) +
    facet_wrap(~CabRow, ncol = 1, labeller = labeller(
      CabRow = c("1" = "Row 1 (Bottom)", "2" = "Row 2", "3" = "Row 3", "4" = "Row 4 (Top)")
    )) +
    labs(
      title = paste0("Floor ", f, " - ",
                    ifelse(f == 3, "GOLDEN ZONE",
                    ifelse(f %in% c(2,4), "Good Ergonomics", "Lower Priority"))),
      subtitle = paste0(nrow(floor_data), " SKUs | 4 Rows × 2 Columns × 3 Cabinets | Row 2-3 back-to-back"),
      x = "", y = ""
    ) +
    theme_minimal() +
    theme(
      axis.text.y = element_blank(),
      axis.ticks.y = element_blank(),
      strip.background = element_rect(fill = "gray30"),
      strip.text = element_text(color = "white", face = "bold")
    )

  ggsave(paste0("Q3_floor_", f, "_detail.png"), p, width = 12, height = 10, dpi = 150)
  cat("  - Saved: Q3_floor_", f, "_detail.png\n", sep="")
}

cat("\n=== Q3 Complete ===\n")
