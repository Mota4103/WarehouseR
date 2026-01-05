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

# Calculate walking distance from start point (between Cabinet 3 and 4) to each cabinet
# Aisle width = 2.0m, Cabinet width = 1.98m
aisle_width_m <- 2.0

get_walking_distance <- function(cab) {
  info <- get_cabinet_info(cab)
  row <- info$row
  col <- info$col
  pos <- info$pos  # 1, 2, or 3 within the row

  # Start point is in the center aisle between Column 1 and Column 2, at Row 1
  # X distance: position 3 (Col1) and position 1 (Col2) are closest to center aisle
  # Cabinet 3 is at pos=3 in Col1, Cabinet 4 is at pos=1 in Col2

  # X distance from center aisle to cabinet center
  if (col == 1) {
    # Column 1: pos 3 is closest to aisle, pos 1 is furthest
    x_dist <- (3 - pos) * pos_width + pos_width/2
  } else {
    # Column 2: pos 1 is closest to aisle, pos 3 is furthest
    x_dist <- (pos - 1) * pos_width + pos_width/2
  }

  # Y distance: need to walk through aisles to reach different rows
  # Row 1: Y = 0 (start point)
  # Row 2: Y = aisle (between Row 1-2) = 2.0m
  # Row 3: Y = aisle + back-to-back walk around = need to go via Row 4 aisle
  # Row 4: Y = aisle (Row 1-2) + Row 2 depth + Row 3 depth + aisle (Row 3-4)

  # Simplified: walking distance in Y direction
  if (row == 1) {
    y_dist <- 0
  } else if (row == 2) {
    y_dist <- aisle_width_m + pos_depth  # Walk through aisle to Row 2
  } else if (row == 3) {
    # Row 2-3 are back-to-back, must go around via Row 4 aisle
    y_dist <- aisle_width_m + pos_depth + pos_depth + aisle_width_m + pos_depth
  } else {  # row == 4
    y_dist <- aisle_width_m + pos_depth + pos_depth + aisle_width_m
  }

  return(x_dist + y_dist)  # Manhattan distance (walking along aisles)
}

# Calculate distance for all cabinets and create sorted order
cabinet_distances <- sapply(1:24, get_walking_distance)
cabinets_by_distance <- order(cabinet_distances)

cat("Cabinet order by walking distance from start (Cab 3-4):\n")
cat("  ", paste(cabinets_by_distance, collapse = " → "), "\n")
cat("  Distances: ", paste(round(cabinet_distances[cabinets_by_distance], 2), collapse = ", "), "m\n\n")

### =========================
### STEP 1: Load Data
### =========================
cat("Loading data...\n")

if (!file.exists("DataFreq.csv")) {
  stop("DataFreq.csv not found. Please run Freq.R first.")
}

all_skus <- fread("DataFreq.csv")
itemMaster <- fread("itemMaster.txt", sep = ",", header = TRUE)

cat("  - Total SKUs from DataFreq: ", nrow(all_skus), " items\n", sep="")
cat("  - Will find optimal SKUs using BENEFIT PEAK method (same as Q2)\n", sep="")

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

# Sort by Viscosity (highest first) - this determines selection order
setorder(all_skus, -Viscosity)

# Merge with itemMaster for box dimensions
slotting <- merge(
  all_skus,
  itemMaster[, .(PartNo, PartName, BoxWidth_m, BoxDepth_m, BoxHeight_m, CubM)],
  by = "PartNo",
  all.x = TRUE
)

# Re-sort by Viscosity after merge
setorder(slotting, -Viscosity)

# Rename columns to match expected format
setnames(slotting, "Freq", "Frequency", skip_absent = TRUE)
setnames(slotting, "Volume", "DemandVolume_m3", skip_absent = TRUE)

# Calculate how many boxes fit in depth and height of position
slotting[, BoxesInDepth := pmax(1, floor(pos_depth / BoxDepth_m))]
slotting[, BoxesInHeight := pmax(1, floor(pos_height / BoxHeight_m))]
slotting[, BoxesPerColumn := BoxesInDepth * BoxesInHeight]

# Width needed = 1 box width (minimum allocation per SKU)
# Each SKU gets at least 1 column width in the FPA
slotting[, WidthNeeded_m := BoxWidth_m]
slotting[, TotalBoxesNeeded := BoxesPerColumn]  # 1 column of boxes

# Handle NA values
slotting[is.na(WidthNeeded_m), WidthNeeded_m := 0.2]  # Default 20cm
slotting[is.na(BoxWidth_m), BoxWidth_m := 0.2]  # Default box width
slotting[WidthNeeded_m > pos_width, WidthNeeded_m := pos_width]  # Cap at position width

# Calculate box volume for each SKU
slotting[, BoxVolume_m3 := BoxWidth_m * BoxDepth_m * BoxHeight_m]
slotting[is.na(BoxVolume_m3), BoxVolume_m3 := 0.2 * 0.2 * 0.2]  # Default

# Sort by Viscosity (highest first) for benefit calculation
setorder(slotting, -Viscosity)
slotting[, ViscosityRank := 1:.N]

### =========================
### STEP 3B: Find Optimal SKUs using BENEFIT PEAK (same method as Q2)
### =========================
cat("\nFinding optimal SKUs using BENEFIT PEAK method...\n")

# Parameters (use cabinet volume, not 36 m³)
V_fpa <- n_cabinets * n_floors * pos_volume   # 24 × 5 × 0.4039 = 48.47 m³
W_fpa <- n_cabinets * n_floors * pos_width    # 24 × 5 × 1.98 = 237.6 m
s <- 2.0             # Time saved per FPA pick (min/line)
Cr <- 15.0           # Replenishment time (min/trip)

cat("  - FPA Volume (cabinet capacity): ", round(V_fpa, 2), " m³\n", sep="")
cat("  - FPA Total Width: ", round(W_fpa, 2), " m\n", sep="")
cat("  - Time saved per pick: ", s, " min\n", sep="")
cat("  - Replenishment time: ", Cr, " min\n\n", sep="")

# Sort by viscosity (highest first)
setorder(slotting, -Viscosity)

### STEP 1: Find optimal SKUs using Q2 method (NO physical constraints)
### This is pure fluid model - find benefit peak first
cat("Step 1: Finding optimal SKUs (Q2 method - no physical constraints)...\n")

n_skus <- nrow(slotting)
results <- data.table(n = 1:n_skus, TotalBenefit = 0)

for (i in 1:n_skus) {
  selected <- slotting[1:i]

  # Fluid model allocation: v_i* = V × sqrt(D_i) / sum(sqrt(D_j))
  sqrt_D <- sqrt(selected$DemandVolume_m3)
  sum_sqrt_D <- sum(sqrt_D)
  v_star <- V_fpa * sqrt_D / sum_sqrt_D

  # Benefit: B_i = s × f_i - Cr × (D_i / v_i*)
  benefit <- s * selected$Frequency - Cr * (selected$DemandVolume_m3 / v_star)
  results[i, TotalBenefit := sum(benefit)]
}

# Find peak (maximum benefit)
optimal_n <- results[which.max(TotalBenefit), n]
max_benefit <- results[which.max(TotalBenefit), TotalBenefit]

cat("  - Optimal SKUs at peak: ", optimal_n, "\n", sep="")
cat("  - Maximum benefit: ", format(round(max_benefit), big.mark=","), " min/year\n\n", sep="")

### STEP 2: Apply physical constraints to optimal SKUs
cat("Step 2: Applying physical constraints (ceil for boxes + cap to 1 position)...\n")

# Keep only optimal SKUs
slotting <- slotting[1:optimal_n]

# Recalculate fluid model allocation for optimal n
sqrt_D <- sqrt(slotting$DemandVolume_m3)
sum_sqrt_D <- sum(sqrt_D)
slotting[, v_fluid := V_fpa * sqrt_D / sum_sqrt_D]

# Convert to physical boxes with CEIL
slotting[, AllocBoxes := ceiling(v_fluid / BoxVolume_m3)]
slotting[AllocBoxes < 1, AllocBoxes := 1]

# Calculate max boxes per position (within 1 depth = 1 SKU, so cap to 1 position)
slotting[, MaxColumns := floor(pos_width / BoxWidth_m)]
slotting[, MaxBoxesPerPos := MaxColumns * BoxesPerColumn]

# Cap each SKU to fit in 1 position (since 1 depth = 1 SKU constraint)
slotting[, AllocBoxes := pmin(AllocBoxes, MaxBoxesPerPos)]
slotting[, ColumnsNeeded := ceiling(AllocBoxes / BoxesPerColumn)]
slotting[, ColumnsNeeded := pmin(ColumnsNeeded, MaxColumns)]
slotting[, AllocWidth := ColumnsNeeded * BoxWidth_m]
slotting[, AllocWidth := pmin(AllocWidth, pos_width)]

# Calculate volume and benefit with CAPPED allocation
slotting[, AllocVolume := AllocBoxes * BoxVolume_m3]
slotting[, SKU_Benefit := s * Frequency - Cr * (DemandVolume_m3 / AllocVolume)]

cat("  - Total physical volume (capped): ", round(sum(slotting$AllocVolume), 2), " m³\n", sep="")
cat("  - Total physical width (capped): ", round(sum(slotting$AllocWidth), 2), " m\n", sep="")
cat("  - Total width available: ", W_fpa, " m\n", sep="")

### STEP 3: If width STILL exceeds capacity, remove lowest viscosity SKUs
if (sum(slotting$AllocWidth) > W_fpa) {
  cat("\nStep 3: Width exceeds capacity, removing lowest viscosity SKUs...\n")

  # Sort by viscosity (already sorted, but ensure)
  setorder(slotting, -Viscosity)

  # Remove from bottom until width fits
  while (sum(slotting$AllocWidth) > W_fpa && nrow(slotting) > 1) {
    slotting <- slotting[1:(nrow(slotting) - 1)]
  }

  cat("  - SKUs after filtering: ", nrow(slotting), "\n", sep="")
  cat("  - Final width: ", round(sum(slotting$AllocWidth), 2), " m\n", sep="")
} else {
  cat("\nStep 3: Width fits, all ", nrow(slotting), " SKUs retained\n", sep="")
}

cat("\n=== BENEFIT PEAK ANALYSIS ===\n")
cat("  - SKUs from fluid model peak: ", optimal_n, "\n", sep="")
cat("  - SKUs after physical constraint: ", nrow(slotting), "\n", sep="")
cat("  - Maximum benefit (fluid): ", format(round(max_benefit), big.mark=","), " min/year\n", sep="")
cat("  - Physical benefit (capped): ", format(round(sum(slotting$SKU_Benefit)), big.mark=","), " min/year\n", sep="")
cat("  - = ", round(sum(slotting$SKU_Benefit) / 60, 1), " hours/year saved\n", sep="")
cat("  - Total width used: ", round(sum(slotting$AllocWidth), 2), " / ", W_fpa, " m\n\n", sep="")

# Update optimal_n to actual count
optimal_n <- nrow(slotting)

# Set final values
slotting[, TotalBoxesNeeded := AllocBoxes]
slotting[, AllocatedVolume_m3 := AllocVolume]
slotting[, Benefit := SKU_Benefit]
slotting[, ReplenishTrips := DemandVolume_m3 / AllocatedVolume_m3]
slotting[, WidthNeeded_m := AllocWidth]

cat("Selected ", optimal_n, " SKUs for FPA (benefit-optimized)\n", sep="")
cat("  - Total allocated volume: ", round(sum(slotting$AllocatedVolume_m3), 2), " m³\n", sep="")
cat("  - Total frequency: ", format(sum(slotting$Frequency), big.mark=","), " picks/year\n", sep="")

# Sort by FREQUENCY for ergonomic floor assignment
setorder(slotting, -Frequency)
slotting[, FrequencyRank := 1:.N]

# Re-sort by Viscosity for reference
setorder(slotting, -Viscosity)

# Extract prefix for grouping
slotting[, Prefix := substr(PartNo, 1, 3)]

# Count items per prefix
prefix_counts <- slotting[, .(Count = .N, TotalFreq = sum(Frequency)), by = Prefix]
setorder(prefix_counts, -Count)

cat("  - Total width needed: ", round(sum(slotting$WidthNeeded_m), 2), " m\n", sep="")
cat("  - Total width available: ", n_cabinets * n_floors * pos_width, " m\n", sep="")
cat("  - Prefix groups: ", nrow(prefix_counts), "\n\n", sep="")

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
# Group by ShippingDay + ReceivingLocation (items shipped together to same location)
shipTrans[, ShippingDay := as.Date(as.character(ShippingDay), "%Y%m%d")]

pair_counts <- data.table()

# Use ReceivingLocation if available, otherwise just ShippingDay
if ("ReceivingLocation" %in% names(shipTrans)) {
  shipTrans[, BasketKey := paste(ShippingDay, ReceivingLocation, sep = "_")]
  cat("  - Grouping by: ShippingDay + ReceivingLocation\n")
} else {
  shipTrans[, BasketKey := as.character(ShippingDay)]
  cat("  - Grouping by: ShippingDay only\n")
}

# Group all items by basket, then filter to only FPA SKUs
baskets <- shipTrans[, .(AllItems = list(unique(PartNo))), by = BasketKey]
baskets[, FPAItems := lapply(AllItems, function(x) x[x %in% fpa_skus])]
baskets[, ItemCount := sapply(FPAItems, length)]

# Debug basket sizes
cat("  - Total baskets: ", nrow(baskets), "\n", sep="")
cat("  - Baskets with 2+ FPA items: ", sum(baskets$ItemCount >= 2), "\n", sep="")
cat("  - FPA items per basket: min=", min(baskets$ItemCount),
    ", median=", median(baskets$ItemCount), ", max=", max(baskets$ItemCount), "\n", sep="")

# Count co-occurrences among FPA SKUs
cooc_list <- list()
valid_baskets <- baskets[ItemCount >= 2 & ItemCount <= 100]

if (nrow(valid_baskets) > 0) {
  for (b in 1:nrow(valid_baskets)) {
    items <- valid_baskets$FPAItems[[b]]
    if (length(items) >= 2) {
      pairs <- t(combn(sort(items), 2))
      cooc_list[[b]] <- data.table(Item1 = pairs[,1], Item2 = pairs[,2])
    }
  }

  if (length(cooc_list) > 0) {
    cooc_pairs <- rbindlist(cooc_list)
    pair_counts <- cooc_pairs[, .(Count = .N), by = .(Item1, Item2)]
    setorder(pair_counts, -Count)
    cat("  - Co-occurrence pairs found: ", nrow(pair_counts), "\n", sep="")
    cat("  - Top 10 co-occurrence pairs:\n")
    print(head(pair_counts, 10))
  }
} else {
  cat("  - No baskets with 2+ FPA items\n")
}

# Combine association scores
all_pairs <- unique(rbind(
  if (nrow(pattern_pairs) > 0) pattern_pairs[, .(Item1, Item2)] else data.table(),
  if (nrow(pair_counts) > 0) pair_counts[Count >= 1, .(Item1, Item2)] else data.table()
))

# Debug: show co-occurrence stats
if (nrow(pair_counts) > 0) {
  cat("  - Co-occurrence pairs with Count >= 1: ", nrow(pair_counts), "\n", sep="")
  cat("  - Top 10 co-occurrence pairs:\n")
  print(head(pair_counts, 10))
} else {
  cat("  - No co-occurrence pairs found in shipment data\n")
}

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
# Use only top 40 pairs for slotting
if (nrow(all_pairs) > 0) {
  setorder(all_pairs, -TotalScore)
  top_pairs <- all_pairs[1:min(40, nrow(all_pairs))]

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

  # Check if ANY position can fit this SKU
  max_remaining <- max(position_remaining)
  if (max_remaining < width_needed) {
    cat("  - FPA is full, no position can fit SKU ", i, " (needs ", round(width_needed, 2), "m)\n", sep="")
    break
  }
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

  # PRIORITY 3: Standard algorithm (cabinet/walking distance first, then floor)
  # Use cabinets_by_distance as outer loop for walking distance priority
  if (!assigned) {
    for (cab in cabinets_by_distance) {
      if (assigned) break

      for (floor in floor_priority) {
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
cat("  - SKUs not fitting (FPA full): ", skus_not_fit, "\n", sep="")
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

# Filter to only assigned SKUs for all summaries
slotting_assigned <- slotting[!is.na(Cabinet)]

# Count SKUs per position
position_summary <- slotting_assigned[, .(
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
floor_summary <- slotting_assigned[, .(
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
prefix_summary <- slotting_assigned[, .(
  SKUs = .N,
  Cabinets = uniqueN(Cabinet),
  CabinetRange = paste0(min(Cabinet), "-", max(Cabinet)),
  TotalFreq = sum(Frequency)
), by = Prefix]
setorder(prefix_summary, -SKUs)
print(head(prefix_summary, 10))

# Re-sort by FrequencyRank for display
setorder(slotting_assigned, FrequencyRank)

cat("\nTop 20 SKUs (highest frequency - ergonomic priority):\n")
print(slotting_assigned[1:min(20, .N), .(
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

# Filter only assigned SKUs for output
assigned_output <- slotting[!is.na(Cabinet)]

output_cols <- c("FrequencyRank", "ViscosityRank", "PartNo", "PartName", "Prefix", "Frequency", "DemandVolume_m3",
                 "Viscosity", "AllocatedVolume_m3", "Benefit", "ReplenishTrips",
                 "BoxWidth_m", "BoxDepth_m", "BoxHeight_m", "TotalBoxesNeeded",
                 "WidthNeeded_m", "Cabinet", "Floor", "PositionID",
                 "SubPosStart_m", "SubPosEnd_m", "X", "Y",
                 "ErgonomicScore", "AssociatedWith", "AssociationGroup")

output_cols <- intersect(output_cols, names(assigned_output))
fwrite(assigned_output[, ..output_cols], "Q3_slotting_result.csv")
cat("  - Saved: Q3_slotting_result.csv (", nrow(assigned_output), " SKUs)\n", sep="")

# Save top 40 association pairs by TotalScore
setorder(all_pairs, -TotalScore)
fwrite(all_pairs[1:min(40, nrow(all_pairs))], "Q3_association_pairs.csv")
cat("  - Saved: Q3_association_pairs.csv\n")

fwrite(position_summary, "Q3_position_utilization.csv")
cat("  - Saved: Q3_position_utilization.csv\n")

### =========================
### STEP 8: Visualizations
### =========================
cat("\nCreating visualizations...\n")

# Layout coordinates to match dataguide.md:
#          Column 1              Column 2
#         ___________    |      ___________
#  Row 4: [19][20][21]   |      [22][23][24]   <- Top
#                        |
#         ~~~~~~~ AISLE ~|~ AISLE ~~~~~~~
#         ___________    |      ___________
#  Row 3: [13][14][15]   |      [16][17][18]
#         ___________    |      ___________    <- BACK-TO-BACK
#  Row 2: [7] [8] [9]    |      [10][11][12]
#                        |
#         ~~~~~~~ AISLE ~|~ AISLE ~~~~~~~
#         ___________    |      ___________
#  Row 1: [1] [2] [3]    |      [4] [5] [6]    <- Bottom (start)

# 1. Multi-SKU Layout View (4 rows × 2 columns × 3 cabinets)
assigned_skus <- slotting_assigned

# X: Column 1 = 0-6, Aisle gap, Column 2 = 8-14
# Y: Row 1 at bottom (y=1), Row 4 at top (y=10)
#    With aisles between Row 1-2 and Row 3-4

# Y coordinates with proper spacing:
# Row 1: y = 1
# AISLE: y = 2
# Row 2: y = 3  (back-to-back with Row 3)
# Row 3: y = 4  (back-to-back with Row 2)
# AISLE: y = 5
# Row 4: y = 6

get_row_y <- function(row) {
  c(1, 3, 4, 6)[row]
}

# Calculate plot coordinates
# Layout: Column 1 (X: 0-6), Aisle (X: 6-8), Column 2 (X: 8-14)
# Each cabinet width = 2 units, 3 cabinets per column = 6 units
# Aisle width = 2 units (centered at X=7)
cabinet_labels <- data.table(
  Cabinet = 1:24,
  CabRow = ceiling(1:24 / 6),
  CabCol = ifelse((1:24 - 1) %% 6 < 3, 1, 2),
  CabPosInRow = ((1:24 - 1) %% 3) + 1
)
cabinet_labels[, PlotY := get_row_y(CabRow), by = Cabinet]
# Column 1: X = 1, 3, 5 (centers), spans 0-6
# Column 2: X = 9, 11, 13 (centers), spans 8-14
# Aisle at X = 6-8 (center at 7)
cabinet_labels[, PlotX := ifelse(CabCol == 1,
                                  (CabPosInRow - 1) * 2 + 1,      # Col 1: 1, 3, 5
                                  8 + (CabPosInRow - 1) * 2 + 1)]  # Col 2: 9, 11, 13

assigned_skus[, PlotY := get_row_y(CabRow), by = 1:nrow(assigned_skus)]
assigned_skus[, PlotX := ifelse(CabCol == 1,
                                 (CabPosInRow - 1) * 2 + SubPosStart_m/pos_width*2,
                                 8 + (CabPosInRow - 1) * 2 + SubPosStart_m/pos_width*2)]
assigned_skus[, PlotXEnd := ifelse(CabCol == 1,
                                    (CabPosInRow - 1) * 2 + SubPosEnd_m/pos_width*2,
                                    8 + (CabPosInRow - 1) * 2 + SubPosEnd_m/pos_width*2)]

# Calculate daily frequency for visualization
assigned_skus[, DailyFreq := Frequency / 250]

p_layout <- ggplot() +
  # Background for cabinets
  geom_rect(data = cabinet_labels, aes(xmin = PlotX - 1, xmax = PlotX + 1,
                                        ymin = PlotY - 0.4, ymax = PlotY + 0.4),
            fill = "gray90", color = "gray50", linewidth = 0.5) +
  # SKU boxes (floors stacked within cabinet) - use daily frequency, normal scale
  geom_rect(data = assigned_skus, aes(xmin = PlotX, xmax = PlotXEnd,
                                       ymin = PlotY - 0.35 + (Floor-1)*0.14,
                                       ymax = PlotY - 0.35 + Floor*0.14,
                                       fill = DailyFreq),
            color = "white", linewidth = 0.1) +
  # Cabinet number labels
  geom_text(data = cabinet_labels, aes(x = PlotX, y = PlotY + 0.55, label = Cabinet),
            size = 3.5, fontface = "bold") +
  # Aisle between Row 1 and 2
  annotate("rect", xmin = -0.5, xmax = 14.5, ymin = 1.7, ymax = 2.3, fill = "gray70", alpha = 0.3) +
  annotate("text", x = 7, y = 2, label = "═════════════ AISLE ═════════════", size = 3, color = "gray30") +
  # Back-to-back between Row 2 and 3
  annotate("rect", xmin = -0.5, xmax = 14.5, ymin = 3.35, ymax = 3.65, fill = "brown", alpha = 0.3) +
  annotate("text", x = 7, y = 3.5, label = "══════ BACK-TO-BACK ══════", size = 3, color = "brown") +
  # Aisle between Row 3 and 4
  annotate("rect", xmin = -0.5, xmax = 14.5, ymin = 4.7, ymax = 5.3, fill = "gray70", alpha = 0.3) +
  annotate("text", x = 7, y = 5, label = "═════════════ AISLE ═════════════", size = 3, color = "gray30") +
  # Vertical aisle between columns (X: 6-8, centered at 7)
  annotate("rect", xmin = 6, xmax = 8, ymin = 0.4, ymax = 6.6, fill = "gray60", alpha = 0.3) +
  annotate("text", x = 7, y = 0.1, label = "AISLE", size = 2.5, color = "gray30") +
  # Row labels on right side
  annotate("text", x = 15.5, y = 1, label = "Row 1 (Start)", hjust = 0, size = 3, fontface = "bold") +
  annotate("text", x = 15.5, y = 3, label = "Row 2", hjust = 0, size = 3) +
  annotate("text", x = 15.5, y = 4, label = "Row 3", hjust = 0, size = 3) +
  annotate("text", x = 15.5, y = 6, label = "Row 4 (Top)", hjust = 0, size = 3, fontface = "bold") +
  # Column labels (centered over each column)
  annotate("text", x = 3, y = 7, label = "Column 1", size = 4, fontface = "bold") +
  annotate("text", x = 11, y = 7, label = "Column 2", size = 4, fontface = "bold") +
  # Start point marker (between Cabinet 3 and 4)
  annotate("point", x = 7, y = 1, size = 4, color = "green", shape = 18) +
  annotate("text", x = 7, y = 0.6, label = "START", size = 2.5, color = "darkgreen", fontface = "bold") +
  scale_fill_gradient(low = "steelblue", high = "darkred",
                      name = "Daily Picks") +
  scale_y_continuous(limits = c(-0.2, 7.5), breaks = NULL) +
  scale_x_continuous(limits = c(-0.5, 18), breaks = NULL) +
  labs(
    title = "FPA Layout - 4 Rows × 2 Columns × 3 Cabinets",
    subtitle = paste0(nrow(assigned_skus), " SKUs in ", nrow(position_summary), " positions | ",
                      "Floors 1-5 stacked within each cabinet | Cabinet numbers shown above"),
    x = NULL,
    y = NULL
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(size = 14, face = "bold"),
    panel.grid = element_blank(),
    axis.text = element_blank()
  )

ggsave("Q3_fpa_layout.png", p_layout, width = 14, height = 10, dpi = 150)
cat("  - Saved: Q3_fpa_layout.png\n")

# 2. Position Utilization Heatmap (4×2×3 layout - matching dataguide.md)
# Add cabinet info to position summary
position_summary[, CabRow := ceiling(Cabinet / 6)]
position_summary[, CabCol := ifelse((Cabinet - 1) %% 6 < 3, 1, 2)]
position_summary[, CabPosInRow := ((Cabinet - 1) %% 3) + 1]

# Reorder rows so Row 1 is at bottom, Row 4 at top (matching dataguide layout)
position_summary[, RowLabel := factor(paste("Row", CabRow),
                                       levels = c("Row 4", "Row 3", "Row 2", "Row 1"))]
position_summary[, ColLabel := paste("Column", CabCol)]

p_util <- ggplot(position_summary, aes(x = factor(CabPosInRow), y = factor(Floor))) +
  geom_tile(aes(fill = SKUsInPosition), color = "white") +
  geom_text(aes(label = paste0("C", Cabinet, "\n", SKUsInPosition, " SKU\n", WidthUsed_pct, "%")),
            size = 2, color = "white") +
  facet_grid(RowLabel ~ CabCol, labeller = labeller(
    CabCol = c("1" = "Column 1", "2" = "Column 2")
  )) +
  scale_fill_gradient(low = "steelblue", high = "darkred", name = "SKUs\nper Pos") +
  scale_y_discrete(limits = rev(c("1", "2", "3", "4", "5"))) +
  scale_x_discrete(labels = c("Cab 1", "Cab 2", "Cab 3")) +
  labs(
    title = "Position Utilization - Layout Matches dataguide.md",
    subtitle = "Row 4 (Top) to Row 1 (Bottom) | Row 2-3 are BACK-TO-BACK | Each cell: Cabinet#, SKUs, utilization%",
    x = "Cabinet Position within Row",
    y = "Floor Level (1=Bottom, 5=Top)"
  ) +
  theme_minimal() +
  theme(
    strip.background = element_rect(fill = "gray30"),
    strip.text = element_text(color = "white", face = "bold")
  )

ggsave("Q3_position_utilization.png", p_util, width = 12, height = 12, dpi = 150)
cat("  - Saved: Q3_position_utilization.png\n")

# 3. Floor Distribution
# Assign ergonomic labels based on floor number
ergonomic_map <- c("1" = "Lower", "2" = "Good", "3" = "GOLDEN ZONE", "4" = "Good", "5" = "Upper")
floor_summary[, Ergonomic := ergonomic_map[as.character(Floor)]]

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

# 4. Detailed floor views (matching dataguide.md layout: Row 1 at bottom, Row 4 at top)
for (f in 1:5) {
  floor_data <- slotting_assigned[Floor == f]
  if (nrow(floor_data) == 0) next

  # Calculate width ratio for each SKU to determine text size
  floor_data[, WidthRatio := (SubPosEnd_m - SubPosStart_m) / pos_width]

  # Create label - shorter for narrow boxes (no frequency)
  floor_data[, Label := ifelse(WidthRatio >= 0.5,
                                substr(PartNo, 1, 10),
                                ifelse(WidthRatio >= 0.3,
                                       substr(PartNo, 1, 6),
                                       substr(PartNo, 1, 4)))]

  # Calculate daily frequency for coloring
  floor_data[, DailyFreq := Frequency / 250]

  # Dynamic text size based on width
  floor_data[, TextSize := ifelse(WidthRatio >= 0.5, 2.0,
                                   ifelse(WidthRatio >= 0.3, 1.5, 1.2))]

  # Calculate plot positions using layout matching dataguide.md
  # X: Column 1 at left (0-3), Column 2 at right (5-8) with aisle gap in middle
  floor_data[, PlotX := (CabCol - 1) * 5 + (CabPosInRow - 1) + SubPosStart_m/pos_width]
  floor_data[, PlotXEnd := (CabCol - 1) * 5 + (CabPosInRow - 1) + SubPosEnd_m/pos_width]

  # Y: Row 1 at bottom, Row 4 at top with proper spacing for aisles
  # Row 1: Y=1, Row 2: Y=3, Row 3: Y=4.5, Row 4: Y=6.5
  get_floor_row_y <- function(row) c(1, 3, 4.5, 6.5)[row]
  floor_data[, PlotY := get_floor_row_y(CabRow), by = 1:nrow(floor_data)]

  # Create cabinet position markers
  cab_markers <- data.table(
    Cabinet = 1:24,
    CabRow = ceiling(1:24 / 6),
    CabCol = ifelse((1:24 - 1) %% 6 < 3, 1, 2),
    CabPosInRow = ((1:24 - 1) %% 3) + 1
  )
  cab_markers[, PlotX := (CabCol - 1) * 5 + (CabPosInRow - 1) + 0.5]
  cab_markers[, PlotY := get_floor_row_y(CabRow), by = 1:nrow(cab_markers)]

  p <- ggplot() +
    # Cabinet background outlines
    geom_rect(data = cab_markers, aes(xmin = PlotX - 0.5, xmax = PlotX + 0.5,
                                       ymin = PlotY - 0.4, ymax = PlotY + 0.4),
              fill = "gray95", color = "gray50", linewidth = 0.3) +
    # SKU boxes (colored by daily frequency)
    geom_rect(data = floor_data, aes(xmin = PlotX, xmax = PlotXEnd,
                                      ymin = PlotY - 0.35, ymax = PlotY + 0.35, fill = DailyFreq),
              color = "black", linewidth = 0.3) +
    geom_text(data = floor_data, aes(x = (PlotX + PlotXEnd)/2, y = PlotY,
                                      label = Label, size = TextSize),
              color = "white", fontface = "bold", show.legend = FALSE) +
    # Cabinet number labels below
    geom_text(data = cab_markers, aes(x = PlotX, y = PlotY - 0.55, label = Cabinet),
              size = 2.5, fontface = "bold") +
    # Aisle between columns (centered between X=3 and X=5)
    annotate("rect", xmin = 3.5, xmax = 4.5, ymin = 0.3, ymax = 7.2, fill = "gray60", alpha = 0.3) +
    annotate("text", x = 4, y = 0, label = "AISLE", size = 2.5, color = "gray40") +
    # Aisle between Row 1 (Y=1) and Row 2 (Y=3)
    annotate("rect", xmin = -0.7, xmax = 8.7, ymin = 1.8, ymax = 2.2, fill = "gray70", alpha = 0.3) +
    annotate("text", x = 4, y = 2, label = "AISLE", size = 2.5, color = "gray40") +
    # Back-to-back between Row 2 (Y=3) and Row 3 (Y=4.5)
    annotate("rect", xmin = -0.7, xmax = 8.7, ymin = 3.6, ymax = 3.9, fill = "brown", alpha = 0.3) +
    annotate("text", x = 4, y = 3.75, label = "BACK-TO-BACK", size = 2.5, color = "brown") +
    # Aisle between Row 3 (Y=4.5) and Row 4 (Y=6.5)
    annotate("rect", xmin = -0.7, xmax = 8.7, ymin = 5.3, ymax = 5.7, fill = "gray70", alpha = 0.3) +
    annotate("text", x = 4, y = 5.5, label = "AISLE", size = 2.5, color = "gray40") +
    # Row labels on right side
    annotate("text", x = 9, y = 1, label = "Row 1 (Start)", hjust = 0, size = 2.5, fontface = "bold") +
    annotate("text", x = 9, y = 3, label = "Row 2", hjust = 0, size = 2.5) +
    annotate("text", x = 9, y = 4.5, label = "Row 3", hjust = 0, size = 2.5) +
    annotate("text", x = 9, y = 6.5, label = "Row 4 (Top)", hjust = 0, size = 2.5, fontface = "bold") +
    # Column labels at top
    annotate("text", x = 1.5, y = 7.3, label = "Column 1", size = 3, fontface = "bold") +
    annotate("text", x = 6.5, y = 7.3, label = "Column 2", size = 3, fontface = "bold") +
    scale_size_identity() +
    scale_fill_gradient(low = "steelblue", high = "red", name = "Daily Picks") +
    scale_x_continuous(limits = c(-0.7, 11)) +
    scale_y_continuous(limits = c(-0.5, 7.8)) +
    labs(
      title = paste0("Floor ", f, " Detail - ",
                    ifelse(f == 3, "GOLDEN ZONE",
                    ifelse(f %in% c(2,4), "Good Ergonomics", "Lower Priority")),
                    " (Layout matches dataguide.md)"),
      subtitle = paste0(nrow(floor_data), " SKUs | Row 4 at Top, Row 1 at Bottom | Row 2-3 back-to-back"),
      x = NULL, y = NULL
    ) +
    theme_minimal() +
    theme(
      axis.text = element_blank(),
      axis.ticks = element_blank(),
      panel.grid = element_blank()
    )

  ggsave(paste0("Q3_floor_", f, "_detail.png"), p, width = 12, height = 10, dpi = 150)
  cat("  - Saved: Q3_floor_", f, "_detail.png\n", sep="")
}

cat("\n=== Q3 Complete ===\n")
