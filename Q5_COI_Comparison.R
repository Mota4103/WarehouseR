###############################################################################
# Q5_COI_Comparison.R - Bonus Question (30 points)
# Compare Fluid Model with COI (Cube-Per-Order Index)
#
# Key Insight from Caron, Marchet & Perego (1998):
# - COI is for LOCATION ASSIGNMENT (where to place items to minimize travel)
# - Fluid Model is for SELECTION + ALLOCATION (which items + how much space)
# - These solve DIFFERENT optimization problems
###############################################################################

library(data.table)
library(ggplot2)

cat("=== Bonus: Fluid Model vs COI Comparison ===\n\n")

cat("Theoretical Background:\n")
cat("  1. FLUID MODEL (Bartholdi & Hackman):\n")
cat("     - Purpose: SELECT which SKUs go in FPA and ALLOCATE space optimally\n")
cat("     - Viscosity: v_i = f_i / sqrt(D_i) - higher = better candidate\n")
cat("     - Allocation: v* = V x sqrt(D_i) / sum(sqrt(D_j)) - optimal from calculus\n")
cat("     - Jointly optimizes selection AND allocation\n\n")

cat("  2. COI - Cube-Per-Order Index (Heskett 1963, Caron et al. 1998):\n")
cat("     - Purpose: LOCATION ASSIGNMENT - where to place items in warehouse\n")
cat("     - COI = Required Storage Space / Order Frequency\n")
cat("     - Lower COI = place closer to I/O point (less space per pick)\n")
cat("     - Originally designed for fixed storage allocation\n\n")

cat("  This comparison tests: Can COI be used for SKU SELECTION like Fluid Model?\n\n")

### =========================
### Parameters
### =========================
V_total <- 36.0  # FPA Volume (m^3)
s_param <- 2.0   # Time saved per pick (min/line)
Cr_param <- 15.0 # Replenishment time (min/trip)

### =========================
### STEP 1: Load Data
### =========================
cat("Loading data...\n")

# Always recalculate both methods for fair comparison
use_q2 <- FALSE
cat("  - Recalculating both methods from scratch for fair comparison\n")

# Load raw data for COI calculation
shipTrans <- fread("shipTrans.txt", sep = ",", header = TRUE)
itemMaster <- fread("itemMaster.txt", sep = ",", header = TRUE)

setnames(shipTrans, names(shipTrans), gsub("[ .]", "", names(shipTrans)))
setnames(itemMaster, names(itemMaster), gsub("[ .]", "", names(itemMaster)))

# IMPORTANT: Apply same filtering as Freq.R (used by Q2) for fair comparison
# Filter out flood period (Oct-Nov 2011) and Sundays
shipTrans[, ShippingDate := as.Date(as.character(as.integer(ShippingDay)), format="%Y%m%d")]
shipTrans[, YearMonth := as.integer(format(ShippingDate, "%Y%m"))]
shipTrans[, DayOfWeek := weekdays(ShippingDate)]

n_before <- nrow(shipTrans)
shipTrans <- shipTrans[!YearMonth %in% c(201110, 201111)]  # Remove flood period
shipTrans <- shipTrans[DayOfWeek != "Sunday"]              # Remove Sundays
n_after <- nrow(shipTrans)

cat("  - Transactions before filtering: ", format(n_before, big.mark=","), "\n", sep="")
cat("  - Transactions after filtering (no flood, no Sunday): ", format(n_after, big.mark=","), "\n", sep="")

if ("PartNo" %in% names(itemMaster) == FALSE) {
  old_names <- names(itemMaster)[1:9]
  new_names <- c("Skus", "PartNo", "PartName", "BoxType", "UnitLabelQt",
                 "ModuleSizeL", "ModuleSizeV", "ModuleSizeH", "CubM")
  setnames(itemMaster, old_names, new_names)
}

if ("Partname" %in% names(itemMaster)) {
  setnames(itemMaster, "Partname", "PartName", skip_absent = TRUE)
}
if ("Boxtype" %in% names(itemMaster)) {
  setnames(itemMaster, "Boxtype", "BoxType", skip_absent = TRUE)
}

itemMaster[, ModuleSizeL := as.numeric(gsub(",", "", ModuleSizeL))]
itemMaster[, ModuleSizeV := as.numeric(gsub(",", "", ModuleSizeV))]
itemMaster[, ModuleSizeH := as.numeric(gsub(",", "", ModuleSizeH))]
itemMaster[, CubM := as.numeric(gsub(",", "", CubM))]
itemMaster[, UnitLabelQt := as.numeric(gsub(",", "", UnitLabelQt))]

itemMaster[, L_m := ModuleSizeL / 1000]
itemMaster[, W_m := ModuleSizeV / 1000]
itemMaster[, H_m := ModuleSizeH / 1000]

# Filter small parts
filtered_SKUs <- itemMaster[H_m < 1.5 & (L_m < 0.68 | W_m < 0.68)]

shipTrans[, PartNo := gsub("[ ]", "", PartNo)]
filtered_SKUs[, PartNo := gsub("[ ]", "", PartNo)]

shipTrans_small <- shipTrans[PartNo %in% filtered_SKUs$PartNo]
shipTrans_small <- shipTrans_small[!is.na(PartNo) & PartNo != ""]

cat("  - Small parts transactions: ", format(nrow(shipTrans_small), big.mark=","), "\n\n", sep="")

### =========================
### STEP 2: Calculate Frequency and Volume
### =========================
cat("Calculating frequency and volume...\n")

sku_data <- shipTrans_small[, .(
  Freq = .N,
  TotalQty = sum(ScanQty, na.rm = TRUE)
), by = PartNo]

sku_data <- merge(
  sku_data,
  filtered_SKUs[, .(PartNo, PartName, CubM, ModuleSizeL, ModuleSizeV, ModuleSizeH, UnitLabelQt)],
  by = "PartNo",
  all.x = TRUE
)

sku_data <- sku_data[!is.na(CubM) & CubM > 0 & !is.na(UnitLabelQt) & UnitLabelQt > 0]

# CORRECT Volume calculation (from Freq.R):
# Volume (D) = TotalQty × (CubM / UnitLabelQt) = total volume flow per year
# This is DIFFERENT from Freq × CubM!
sku_data[, VolumePerPiece := CubM / UnitLabelQt]
sku_data[, Volume := TotalQty * VolumePerPiece]  # D_i = flow = annual demand volume (m^3/year)

cat("  - SKUs with complete data: ", nrow(sku_data), "\n\n", sep="")

### =========================
### STEP 3: METHOD 1 - Fluid Model
### =========================
cat("=== METHOD 1: FLUID MODEL ===\n")
cat("(Selection + Optimal Allocation)\n\n")

if (use_q2) {
  # Use Q2 results
  n_fluid <- nrow(fluid_skus)
  fluid_benefit <- sum(fluid_skus$Benefit)

  cat("Results from Q2:\n")
  cat("  - SKUs selected: ", n_fluid, "\n", sep="")
  cat("  - Total Benefit: ", format(round(fluid_benefit, 2), big.mark=","), " min/year\n", sep="")
  cat("  - Total Frequency: ", format(sum(fluid_skus$Frequency), big.mark=","), " lines/year\n\n", sep="")

} else {
  # Recalculate Fluid Model with correct formulas

  # Viscosity = Freq / sqrt(Volume) where Volume = D_i = flow
  sku_data[, Viscosity := Freq / sqrt(Volume)]

  # Sort by Viscosity (highest first)
  setorder(sku_data, -Viscosity)

  # Iterative selection
  fluid_model_select <- function(data, V, s, Cr) {
    n <- nrow(data)
    best_benefit <- -Inf
    best_n <- 0

    for (top_n in 1:min(n, 500)) {
      subset_df <- data[1:top_n]

      # Allocated volume: v_i* = V x sqrt(D_i) / sum(sqrt(D_j))
      sqrt_D <- sqrt(subset_df$Volume)
      sum_sqrt_D <- sum(sqrt_D)

      if (sum_sqrt_D == 0) next

      allocated_volumes <- V * sqrt_D / sum_sqrt_D

      # Benefit: B_i = s x f_i - Cr x (D_i / v_i*)
      benefits <- s * subset_df$Freq - Cr * (subset_df$Volume / allocated_volumes)

      total_benefit <- sum(benefits)

      if (total_benefit > best_benefit) {
        best_benefit <- total_benefit
        best_n <- top_n
      }
    }

    return(list(best_n = best_n, best_benefit = best_benefit))
  }

  fluid_result <- fluid_model_select(sku_data, V_total, s_param, Cr_param)
  n_fluid <- fluid_result$best_n
  fluid_benefit <- fluid_result$best_benefit

  cat("Fluid Model Results:\n")
  cat("  - SKUs selected: ", n_fluid, "\n", sep="")
  cat("  - Total Benefit: ", format(round(fluid_benefit, 2), big.mark=","), " min/year\n\n", sep="")

  # Create allocation for Fluid Model
  fluid_skus <- sku_data[1:n_fluid]
  sqrt_D <- sqrt(fluid_skus$Volume)
  sum_sqrt_D <- sum(sqrt_D)
  fluid_skus[, AllocatedVolume_m3 := V_total * sqrt_D / sum_sqrt_D]
  fluid_skus[, Benefit := s_param * Freq - Cr_param * (Volume / AllocatedVolume_m3)]
  fluid_skus[, Frequency := Freq]
  fluid_skus[, DemandVolume_m3 := Volume]
}

### =========================
### STEP 4: METHOD 2 - COI-Based Selection
### =========================
cat("=== METHOD 2: COI-BASED SELECTION ===\n")
cat("(Using COI for selection, not just location assignment)\n\n")

cat("COI Calculation (Caron et al. 1998, Heskett 1963):\n")
cat("  COI = Required Storage Space / Order Frequency\n")
cat("  COI = C / f (simple ratio, NO square root)\n")
cat("  Where:\n")
cat("    - C = CubM (storage cube per unit, m^3)\n")
cat("    - f = Freq (annual order frequency)\n")
cat("  Lower COI = higher picks per cube = better for FPA\n\n")

# Calculate COI per Caron et al. (1998) - simple ratio
# COI = Storage Space / Frequency = CubM / Freq
sku_data[, COI := CubM / Freq]

# Sort by COI (lowest first = highest priority for FPA)
coi_sorted <- copy(sku_data)
setorder(coi_sorted, COI)

# Show COI distribution
cat("COI Distribution (top 10 lowest COI):\n")
print(coi_sorted[1:10, .(PartNo,
                         Freq,
                         CubM = round(CubM, 6),
                         DailyPicks = round(Freq/250, 2),
                         COI = round(COI, 6))])
cat("\n")

### =========================
### STEP 5: Fair Comparison - Same Allocation Method
### =========================
cat("=== FAIR COMPARISON ===\n\n")

cat("To fairly compare SELECTION methods, we use the SAME allocation for both:\n")
cat("  - Allocation: v* = V x sqrt(D) / sum(sqrt(D)) (Fluid Model's optimal)\n")
cat("  - This isolates the effect of different SELECTION criteria\n\n")

# For COI: Select top n SKUs by COI ranking, apply optimal allocation
# Find optimal n for COI-ranked SKUs using optimal allocation

coi_results <- data.table(n = 1:min(500, nrow(coi_sorted)), TotalBenefit = 0)

for (i in 1:nrow(coi_results)) {
  subset_coi <- coi_sorted[1:i]

  # Use OPTIMAL allocation (same as Fluid Model) for fair comparison
  sqrt_D <- sqrt(subset_coi$Volume)
  sum_sqrt_D <- sum(sqrt_D)

  if (sum_sqrt_D == 0) next

  alloc_vol <- V_total * sqrt_D / sum_sqrt_D

  # Benefit calculation: B = s x f - Cr x (D / v)
  benefit <- s_param * subset_coi$Freq - Cr_param * (subset_coi$Volume / alloc_vol)
  coi_results[i, TotalBenefit := sum(benefit)]
}

# Find peak benefit for COI selection
n_coi_optimal <- coi_results[which.max(TotalBenefit), n]
coi_benefit_optimal <- coi_results[which.max(TotalBenefit), TotalBenefit]

cat("COI Selection with Optimal Allocation:\n")
cat("  - Optimal n (peak benefit): ", n_coi_optimal, "\n", sep="")
cat("  - Maximum benefit: ", format(round(coi_benefit_optimal), big.mark=","), " min/year\n\n", sep="")

# Use same n as fluid model for direct comparison
n_coi <- n_fluid
coi_skus <- coi_sorted[1:n_coi]

# Apply optimal allocation to COI-selected SKUs
sqrt_D_coi <- sqrt(coi_skus$Volume)
sum_sqrt_D_coi <- sum(sqrt_D_coi)
coi_skus[, AllocatedVolume_COI := V_total * sqrt_D_coi / sum_sqrt_D_coi]

# Calculate benefit
coi_skus[, Benefit_COI := s_param * Freq - Cr_param * (Volume / AllocatedVolume_COI)]
coi_benefit <- sum(coi_skus$Benefit_COI)

cat("COI Method (n = ", n_coi, " SKUs, same as Fluid Model):\n", sep="")
cat("  - Total Benefit: ", format(round(coi_benefit, 2), big.mark=","), " min/year\n", sep="")
cat("  - Total Frequency: ", format(sum(coi_skus$Freq), big.mark=","), " lines/year\n\n", sep="")

### =========================
### STEP 6: Comparison Analysis
### =========================
cat("=== COMPARISON RESULTS ===\n\n")

benefit_diff <- fluid_benefit - coi_benefit
benefit_pct <- (benefit_diff / abs(coi_benefit)) * 100

cat("Benefit Comparison (with optimal allocation for both):\n")
cat("  - Fluid Model: ", format(round(fluid_benefit, 2), big.mark=","), " min/year\n", sep="")
cat("  - COI Method:  ", format(round(coi_benefit, 2), big.mark=","), " min/year\n", sep="")
cat("  - Difference:  ", format(round(benefit_diff, 2), big.mark=","), " min/year\n", sep="")
cat("  - Improvement: ", round(benefit_pct, 2), "%\n\n", sep="")

# Calculate hours saved
hours_saved <- benefit_diff / 60
cat("Fluid Model saves ", round(hours_saved, 2), " hours/year more than COI selection\n\n", sep="")

# SKU overlap analysis
if (use_q2) {
  fluid_parts <- fluid_skus$PartNo
} else {
  fluid_parts <- fluid_skus$PartNo
}
coi_parts <- coi_skus$PartNo

overlap <- length(intersect(fluid_parts, coi_parts))
fluid_only <- setdiff(fluid_parts, coi_parts)
coi_only <- setdiff(coi_parts, fluid_parts)

cat("SKU Selection Overlap:\n")
cat("  - Fluid Model SKUs: ", n_fluid, "\n", sep="")
cat("  - COI SKUs: ", n_coi, "\n", sep="")
cat("  - Common SKUs: ", overlap, " (", round(overlap/n_fluid*100, 1), "%)\n", sep="")
cat("  - Only in Fluid Model: ", length(fluid_only), "\n", sep="")
cat("  - Only in COI: ", length(coi_only), "\n\n", sep="")

### =========================
### DIFFERENT SKUs ANALYSIS
### =========================
cat("=== DIFFERENT SKUs BETWEEN METHODS ===\n\n")

# Get full data for different SKUs
if (length(fluid_only) > 0 || length(coi_only) > 0) {

  # SKUs only in Fluid Model
  cat("SKUs selected by FLUID MODEL but NOT by COI:\n")
  if (length(fluid_only) > 0) {
    for (pn in fluid_only) {
      row <- sku_data[PartNo == pn]
      fluid_rank <- which(fluid_parts == pn)
      coi_rank <- which(coi_sorted$PartNo == pn)
      cat(sprintf("  - %s:\n", pn))
      cat(sprintf("      Fluid Model Rank: %d (SELECTED)\n", fluid_rank))
      cat(sprintf("      COI Rank: %d (NOT selected, cutoff=%d)\n", coi_rank, n_coi))
      cat(sprintf("      Freq: %d, TotalQty: %d, PiecesPerPick: %.1f\n",
                  row$Freq, row$TotalQty, row$TotalQty/row$Freq))
      cat(sprintf("      CubM: %.6f, UnitLabelQt: %d\n", row$CubM, row$UnitLabelQt))
      cat(sprintf("      Viscosity: %.2f, COI: %.6f\n", row$Viscosity, row$COI))
      cat(sprintf("      Volume (annual flow): %.4f m³/year\n\n", row$Volume))
    }
  } else {
    cat("  (none)\n\n")
  }

  # SKUs only in COI
  cat("SKUs selected by COI but NOT by FLUID MODEL:\n")
  if (length(coi_only) > 0) {
    for (pn in coi_only) {
      row <- sku_data[PartNo == pn]
      fluid_rank <- which(sku_data$PartNo == pn)  # sku_data is sorted by Viscosity
      coi_rank <- which(coi_sorted$PartNo == pn)
      cat(sprintf("  - %s:\n", pn))
      cat(sprintf("      COI Rank: %d (SELECTED)\n", coi_rank))
      cat(sprintf("      Fluid Model Rank: %d (NOT selected, cutoff=%d)\n", fluid_rank, n_fluid))
      cat(sprintf("      Freq: %d, TotalQty: %d, PiecesPerPick: %.1f\n",
                  row$Freq, row$TotalQty, row$TotalQty/row$Freq))
      cat(sprintf("      CubM: %.6f, UnitLabelQt: %d\n", row$CubM, row$UnitLabelQt))
      cat(sprintf("      Viscosity: %.2f, COI: %.6f\n", row$Viscosity, row$COI))
      cat(sprintf("      Volume (annual flow): %.4f m³/year\n\n", row$Volume))
    }
  } else {
    cat("  (none)\n\n")
  }

  # Create a data.table of different SKUs for CSV export
  different_skus <- data.table()

  if (length(fluid_only) > 0) {
    for (pn in fluid_only) {
      row <- sku_data[PartNo == pn]
      fluid_rank <- which(fluid_parts == pn)
      coi_rank <- which(coi_sorted$PartNo == pn)
      different_skus <- rbind(different_skus, data.table(
        PartNo = pn,
        Selected_By = "Fluid Model Only",
        Fluid_Rank = fluid_rank,
        COI_Rank = coi_rank,
        Freq = row$Freq,
        TotalQty = row$TotalQty,
        PiecesPerPick = round(row$TotalQty/row$Freq, 2),
        CubM = row$CubM,
        UnitLabelQt = row$UnitLabelQt,
        Viscosity = round(row$Viscosity, 2),
        COI = round(row$COI, 8),
        Volume_m3_year = round(row$Volume, 4)
      ))
    }
  }

  if (length(coi_only) > 0) {
    for (pn in coi_only) {
      row <- sku_data[PartNo == pn]
      fluid_rank <- which(sku_data$PartNo == pn)
      coi_rank <- which(coi_sorted$PartNo == pn)
      different_skus <- rbind(different_skus, data.table(
        PartNo = pn,
        Selected_By = "COI Only",
        Fluid_Rank = fluid_rank,
        COI_Rank = coi_rank,
        Freq = row$Freq,
        TotalQty = row$TotalQty,
        PiecesPerPick = round(row$TotalQty/row$Freq, 2),
        CubM = row$CubM,
        UnitLabelQt = row$UnitLabelQt,
        Viscosity = round(row$Viscosity, 2),
        COI = round(row$COI, 8),
        Volume_m3_year = round(row$Volume, 4)
      ))
    }
  }

  # Save different SKUs to CSV
  fwrite(different_skus, "Q5_Different_SKUs.csv")
  cat("Saved: Q5_Different_SKUs.csv\n\n")

} else {
  cat("All SKUs are identical between both methods!\n\n")
}

### =========================
### STEP 7: Key Mathematical Finding
### =========================
cat("=== KEY MATHEMATICAL FINDING ===\n\n")

cat("The two methods use DIFFERENT metrics:\n\n")

cat("  1. COI (Caron et al. 1998, Heskett 1963):\n")
cat("     COI = C / f = CubM / Freq\n")
cat("     Where: C = storage cube (CubM per box)\n")
cat("            f = order frequency (picks/year)\n")
cat("     → Lower COI = more picks per cube = better for FPA\n\n")

cat("  2. Fluid Model Viscosity (Bartholdi & Hackman):\n")
cat("     μ = f / sqrt(D)\n")
cat("     Where: f = Freq (picks/year)\n")
cat("            D = Volume per year (m³/year) = TotalQty × VolumePerPiece\n")
cat("              = TotalQty × (CubM / UnitLabelQt)\n")
cat("     → Higher viscosity = better for FPA\n\n")

cat("KEY DIFFERENCE:\n")
cat("  COI uses: CubM (box volume) / Freq\n")
cat("  Viscosity uses: Freq / sqrt(Volume per year)\n\n")

cat("  Volume per year (D) = TotalQty × (CubM / UnitLabelQt)\n")
cat("  This is the ANNUAL FLOW - total volume shipped per year\n\n")

cat("  COI measures: storage space efficiency per pick\n")
cat("  Viscosity measures: pick rate relative to volume flow\n\n")

cat("KEY INSIGHT FROM CARON ET AL. (1998):\n")
cat("  - COI designed for LOCATION ASSIGNMENT (where to place items)\n")
cat("  - Fluid Model designed for SELECTION + ALLOCATION\n")
cat("  - The real power of Fluid Model is the OPTIMAL ALLOCATION:\n")
cat("    v* = V × sqrt(D) / Σsqrt(D)\n\n")

# Show difference in rankings
cat("Ranking Comparison (top 20):\n")
fluid_ranking <- if(use_q2) fluid_skus[1:20, .(PartNo, Rank = 1:20)] else sku_data[1:20, .(PartNo, Rank = 1:20)]
coi_ranking <- coi_sorted[1:20, .(PartNo, Rank = 1:20)]

rank_compare <- merge(fluid_ranking, coi_ranking, by = "PartNo", suffixes = c("_Fluid", "_COI"), all = TRUE)
rank_compare[is.na(Rank_Fluid), Rank_Fluid := NA]
rank_compare[is.na(Rank_COI), Rank_COI := NA]
rank_compare[, RankDiff := abs(Rank_Fluid - Rank_COI)]
setorder(rank_compare, Rank_Fluid)

cat("\nTop 20 by Fluid Model vs their COI rank:\n")
print(rank_compare[1:min(20, .N)])

### =========================
### STEP 8: Save Results
### =========================
cat("\nSaving results...\n")

# Save COI SKUs
fwrite(coi_skus[, .(PartNo, Freq, Volume, COI, AllocatedVolume_COI, Benefit_COI)],
       "Q5_COI_SKUs.csv")

# Save Fluid Model SKUs
if (use_q2) {
  fwrite(fluid_skus, "Q5_FluidModel_SKUs.csv")
} else {
  fwrite(fluid_skus[, .(PartNo, Freq, Volume, Viscosity, AllocatedVolume_m3, Benefit)],
         "Q5_FluidModel_SKUs.csv")
}

# Save comparison summary
comparison <- data.table(
  Method = c("Fluid Model", "COI"),
  SKUs_Selected = c(n_fluid, n_coi),
  Total_Benefit_min = c(round(fluid_benefit, 2), round(coi_benefit, 2)),
  Total_Benefit_hrs = c(round(fluid_benefit/60, 2), round(coi_benefit/60, 2)),
  Improvement_pct = c(NA, round(benefit_pct, 2))
)
fwrite(comparison, "Q5_Comparison_Summary.csv")

cat("  - Saved: Q5_COI_SKUs.csv\n")
cat("  - Saved: Q5_FluidModel_SKUs.csv\n")
cat("  - Saved: Q5_Comparison_Summary.csv\n")

### =========================
### STEP 9: Visualizations
### =========================
cat("\nCreating visualizations...\n")

# Plot 1: Benefit by n for both methods
benefit_comparison <- data.table(n = 1:min(500, nrow(sku_data)))

# Calculate viscosity for sku_data if not already done
if (!"Viscosity" %in% names(sku_data)) {
  sku_data[, Viscosity := Freq / sqrt(Volume)]
}

# Fluid model benefit by n
setorder(sku_data, -Viscosity)
for (i in 1:nrow(benefit_comparison)) {
  subset_fluid <- sku_data[1:i]
  sqrt_D <- sqrt(subset_fluid$Volume)
  sum_sqrt_D <- sum(sqrt_D)
  if (sum_sqrt_D == 0) {
    benefit_comparison[i, Fluid_Benefit := NA]
    next
  }
  alloc_vol <- V_total * sqrt_D / sum_sqrt_D
  benefit <- s_param * subset_fluid$Freq - Cr_param * (subset_fluid$Volume / alloc_vol)
  benefit_comparison[i, Fluid_Benefit := sum(benefit)]
}

# COI benefit by n (with optimal allocation)
for (i in 1:nrow(benefit_comparison)) {
  subset_coi <- coi_sorted[1:i]
  sqrt_D <- sqrt(subset_coi$Volume)
  sum_sqrt_D <- sum(sqrt_D)
  if (sum_sqrt_D == 0) {
    benefit_comparison[i, COI_Benefit := NA]
    next
  }
  alloc_vol <- V_total * sqrt_D / sum_sqrt_D
  benefit <- s_param * subset_coi$Freq - Cr_param * (subset_coi$Volume / alloc_vol)
  benefit_comparison[i, COI_Benefit := sum(benefit)]
}

plot_data_benefit <- melt(benefit_comparison, id.vars = "n",
                          measure.vars = c("Fluid_Benefit", "COI_Benefit"),
                          variable.name = "Method", value.name = "Benefit")
plot_data_benefit[, Method := gsub("_Benefit", "", Method)]
plot_data_benefit[Method == "Fluid", Method := "Fluid Model"]

p1 <- ggplot(plot_data_benefit, aes(x = n, y = Benefit, color = Method)) +
  geom_line(size = 1) +
  geom_vline(xintercept = n_fluid, linetype = "dashed", color = "gray50") +
  annotate("text", x = n_fluid + 20, y = max(benefit_comparison$Fluid_Benefit, na.rm=TRUE) * 0.9,
           label = paste0("n = ", n_fluid), hjust = 0) +
  scale_y_continuous(labels = scales::comma) +
  labs(
    title = "Total Benefit vs Number of SKUs Selected",
    subtitle = "Both methods use optimal allocation v* = V x sqrt(D) / sum(sqrt(D))",
    x = "Number of SKUs in FPA",
    y = "Total Benefit (min/year)"
  ) +
  theme_minimal() +
  theme(legend.position = "bottom")

ggsave("Q5_benefit_vs_n.png", p1, width = 10, height = 6, dpi = 150)
cat("  - Saved: Q5_benefit_vs_n.png\n")

# Plot 2: Viscosity vs COI scatter
sku_data[, COI_rank := rank(COI)]
sku_data[, Viscosity_rank := rank(-Viscosity)]

p2 <- ggplot(sku_data[1:min(300, .N)], aes(x = Viscosity_rank, y = COI_rank)) +
  geom_point(alpha = 0.5, color = "steelblue") +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "red") +
  labs(
    title = "Viscosity Ranking vs COI Ranking",
    subtitle = "Points on diagonal = same rank in both methods",
    x = "Rank by Viscosity (Fluid Model)",
    y = "Rank by COI"
  ) +
  theme_minimal()

ggsave("Q5_ranking_comparison.png", p2, width = 8, height = 8, dpi = 150)
cat("  - Saved: Q5_ranking_comparison.png\n")

# Plot 3: Benefit Distribution
plot_data_dist <- rbind(
  data.table(Method = "Fluid Model", Benefit = if(use_q2) fluid_skus$Benefit else fluid_skus$Benefit),
  data.table(Method = "COI", Benefit = coi_skus$Benefit_COI)
)

p3 <- ggplot(plot_data_dist, aes(x = Benefit, fill = Method)) +
  geom_histogram(bins = 50, alpha = 0.7, position = "identity") +
  facet_wrap(~Method, ncol = 1, scales = "free_y") +
  labs(
    title = "Benefit Distribution: Fluid Model vs COI Selection",
    subtitle = paste0("Fluid Model: ", format(round(fluid_benefit), big.mark=","),
                      " min | COI: ", format(round(coi_benefit), big.mark=","), " min"),
    x = "Benefit per SKU (minutes/year)",
    y = "Count"
  ) +
  theme_minimal() +
  theme(legend.position = "none")

ggsave("Q5_benefit_distribution.png", p3, width = 10, height = 8, dpi = 150)
cat("  - Saved: Q5_benefit_distribution.png\n")

# Plot 4: Frequency vs CubM with method selection overlay
sku_data[, InFluid := PartNo %in% fluid_parts]
sku_data[, InCOI := PartNo %in% coi_parts]
sku_data[, Selection := "Neither"]
sku_data[InFluid & InCOI, Selection := "Both"]
sku_data[InFluid & !InCOI, Selection := "Fluid Only"]
sku_data[!InFluid & InCOI, Selection := "COI Only"]

p4 <- ggplot(sku_data[Selection != "Neither"],
             aes(x = Freq, y = CubM, color = Selection)) +
  geom_point(alpha = 0.6) +
  scale_x_log10() +
  scale_y_log10() +
  scale_color_manual(values = c("Both" = "purple", "Fluid Only" = "blue", "COI Only" = "red")) +
  labs(
    title = "SKU Selection Comparison: Frequency vs Box Volume",
    subtitle = "Log-log scale showing which SKUs each method selects",
    x = "Annual Frequency (picks/year)",
    y = "Box Volume CubM (m^3)"
  ) +
  theme_minimal() +
  theme(legend.position = "bottom")

ggsave("Q5_selection_comparison.png", p4, width = 10, height = 8, dpi = 150)
cat("  - Saved: Q5_selection_comparison.png\n")

cat("\n=== Bonus Question Complete ===\n")
cat("\nConclusion:\n")
if (fluid_benefit > coi_benefit) {
  cat("  Fluid Model outperforms COI-based selection by ", round(benefit_pct, 2), "%\n", sep="")
  cat("  (", format(round(hours_saved, 1), big.mark=","), " hours/year additional savings)\n\n", sep="")
  cat("  WHY: Viscosity considers FLOW (TotalQty × VolumePerPiece)\n")
  cat("       COI only considers box volume (CubM) per frequency\n\n")
} else if (coi_benefit > fluid_benefit) {
  cat("  COI outperforms Fluid Model by ", round(-benefit_pct, 2), "%\n", sep="")
  cat("  (", format(round(-hours_saved, 1), big.mark=","), " hours/year additional savings)\n\n", sep="")
} else {
  cat("  Both methods achieve SAME benefit!\n")
  cat("  SKU overlap: ", overlap, " / ", n_fluid, " (", round(overlap/n_fluid*100, 1), "%)\n\n", sep="")
}
cat("  CRITICAL DISTINCTION from Caron et al. (1998):\n")
cat("    - COI: Designed for LOCATION assignment (where in warehouse)\n")
cat("    - Fluid Model: Designed for SELECTION + ALLOCATION\n\n")
cat("  The real advantage of Fluid Model is its OPTIMAL ALLOCATION:\n")
cat("    v* = V x sqrt(D) / sum(sqrt(D))\n")
cat("  This minimizes total replenishment cost for a given selection.\n")
