###############################################################################
# Q5_COI_Comparison.R - Bonus Question (30 points)
# Compare Fluid Model with COI (Cube-Per-Order Index)
###############################################################################

library(data.table)
library(ggplot2)

cat("=== Bonus: Fluid Model vs COI Comparison ===\n\n")

### =========================
### Parameters
### =========================
V_total <- 36.0  # FPA Volume (m³)
s_param <- 2.0   # Time saved per pick (min/line)
Cr_param <- 15.0 # Replenishment time (min/trip)

### =========================
### STEP 1: Load Data
### =========================
cat("Loading data...\n")

# Load Q2 output for Fluid Model results
if (file.exists("Q2_FPA_Optimal_SKUs.csv")) {
  fluid_skus <- fread("Q2_FPA_Optimal_SKUs.csv")
  cat("  - Loaded Q2 Fluid Model results: ", nrow(fluid_skus), " SKUs\n", sep="")
  use_q2 <- TRUE
} else {
  use_q2 <- FALSE
  cat("  - Q2 output not found, will recalculate Fluid Model\n")
}

# Load raw data for COI calculation
shipTrans <- fread("shipTrans.txt", sep = ",", header = TRUE)
itemMaster <- fread("itemMaster.txt", sep = ",", header = TRUE)

setnames(shipTrans, names(shipTrans), gsub("[ .]", "", names(shipTrans)))
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
if ("Boxtype" %in% names(itemMaster)) {
  setnames(itemMaster, "Boxtype", "BoxType", skip_absent = TRUE)
}

itemMaster[, ModuleSizeL := as.numeric(gsub(",", "", ModuleSizeL))]
itemMaster[, ModuleSizeV := as.numeric(gsub(",", "", ModuleSizeV))]
itemMaster[, ModuleSizeH := as.numeric(gsub(",", "", ModuleSizeH))]
itemMaster[, CubM := as.numeric(gsub(",", "", CubM))]

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
  filtered_SKUs[, .(PartNo, PartName, CubM, ModuleSizeL, ModuleSizeV, ModuleSizeH)],
  by = "PartNo",
  all.x = TRUE
)

sku_data <- sku_data[!is.na(CubM) & CubM > 0]
sku_data[, Volume := Freq * CubM]  # D_i = flow = annual demand volume

cat("  - SKUs with complete data: ", nrow(sku_data), "\n\n", sep="")

### =========================
### STEP 3: METHOD 1 - Fluid Model
### =========================
cat("=== METHOD 1: FLUID MODEL ===\n\n")

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

      # Allocated volume: v_i* = V × √(D_i) / Σ√(D_j)
      # D_i = Volume (annual demand)
      sqrt_D <- sqrt(subset_df$Volume)
      sum_sqrt_D <- sum(sqrt_D)

      if (sum_sqrt_D == 0) next

      allocated_volumes <- V * sqrt_D / sum_sqrt_D

      # Benefit: B_i = s × f_i - Cr × (D_i / v_i*)
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
### STEP 4: METHOD 2 - COI (Cube-Per-Order Index)
### =========================
cat("=== METHOD 2: COI (Cube-Per-Order Index) ===\n\n")

# COI = Storage Space Required / Number of Orders (Picks)
# From Heskett (1963) and Bartholdi & Hackman
#
# For storage space, we use: space needed to store average inventory
# Assuming EOQ-like replenishment: avg inventory ∝ sqrt(demand)
# Storage space ≈ k * sqrt(D_i) where D_i = annual demand volume
#
# COI_i = Storage_i / f_i = k * sqrt(D_i) / f_i
#
# Lower COI → high picks relative to storage → place closer to I/O

# Calculate proper COI
# COI = Storage Cube / Activity = Box Volume / Daily Picks
# This measures: how much space does this item need per pick?
# Lower COI = less space per pick = should be placed in prime location

# CubM = volume per box (m³)
# Freq = annual picks
# Daily picks = Freq / 250 (working days)
# COI = CubM / (Freq / 250) = CubM × 250 / Freq

sku_data[, COI := CubM * 250 / Freq]  # Cube per daily pick

cat("COI Calculation (Heskett 1963 method):\n")
cat("  - COI = Box Volume (m³) / Daily Picks\n")
cat("  - COI = CubM × 250 / Annual Frequency\n")
cat("  - Lower COI = less storage space per pick = higher priority\n\n")

# Sort by COI (lowest first = highest priority for FPA)
coi_sorted <- copy(sku_data)
setorder(coi_sorted, COI)

# Show COI distribution
cat("COI Distribution (top 10 lowest COI - best for FPA):\n")
print(coi_sorted[1:10, .(PartNo, Freq, CubM = round(CubM, 6),
                          DailyPicks = round(Freq/250, 2),
                          COI = round(COI, 6))])
cat("\n")

# For COI method: select items until storage capacity is full
# Allocate storage proportionally to sqrt(demand) like fluid model for fair comparison
# v_i = V × sqrt(D_i) / Σsqrt(D_j)

# Find optimal n for COI by iterating
coi_results <- data.table(n = 1:min(500, nrow(coi_sorted)), TotalBenefit = 0)

for (i in 1:nrow(coi_results)) {
  subset_coi <- coi_sorted[1:i]

  # Allocate using sqrt-proportional (same as fluid for fair comparison)
  sqrt_D <- sqrt(subset_coi$Volume)
  sum_sqrt_D <- sum(sqrt_D)

  if (sum_sqrt_D == 0) next

  alloc_vol <- V_total * sqrt_D / sum_sqrt_D

  # Benefit calculation
  benefit <- s_param * subset_coi$Freq - Cr_param * (subset_coi$Volume / alloc_vol)
  coi_results[i, TotalBenefit := sum(benefit)]
}

# Find peak benefit for COI
n_coi_optimal <- coi_results[which.max(TotalBenefit), n]
coi_benefit_optimal <- coi_results[which.max(TotalBenefit), TotalBenefit]

cat("COI Optimal Selection:\n")
cat("  - Optimal SKUs at peak: ", n_coi_optimal, "\n", sep="")
cat("  - Maximum benefit: ", format(round(coi_benefit_optimal), big.mark=","), " min/year\n\n", sep="")

# Use same number as fluid model for direct comparison
n_coi <- n_fluid
coi_skus <- coi_sorted[1:n_coi]

# Allocate volume using sqrt-proportional method (same as fluid)
sqrt_D_coi <- sqrt(coi_skus$Volume)
sum_sqrt_D_coi <- sum(sqrt_D_coi)
coi_skus[, AllocatedVolume_COI := V_total * sqrt_D_coi / sum_sqrt_D_coi]

# Calculate benefit for COI selection with same allocation
coi_skus[, Benefit_COI := s_param * Freq - Cr_param * (Volume / AllocatedVolume_COI)]

coi_benefit <- sum(coi_skus$Benefit_COI)

cat("COI Method Results (same n as Fluid Model):\n")
cat("  - SKUs selected: ", n_coi, "\n", sep="")
cat("  - Total Benefit: ", format(round(coi_benefit, 2), big.mark=","), " min/year\n", sep="")
cat("  - Total Frequency: ", format(sum(coi_skus$Freq), big.mark=","), " lines/year\n\n", sep="")

### =========================
### STEP 5: Comparison Analysis
### =========================
cat("=== COMPARISON ===\n\n")

benefit_diff <- fluid_benefit - coi_benefit
benefit_pct <- (benefit_diff / abs(coi_benefit)) * 100

cat("Benefit Comparison:\n")
cat("  - Fluid Model: ", format(round(fluid_benefit, 2), big.mark=","), " min/year\n", sep="")
cat("  - COI Method:  ", format(round(coi_benefit, 2), big.mark=","), " min/year\n", sep="")
cat("  - Difference:  ", format(round(benefit_diff, 2), big.mark=","), " min/year\n", sep="")
cat("  - Improvement: ", round(benefit_pct, 2), "%\n\n", sep="")

# Calculate hours saved
hours_saved <- benefit_diff / 60
cat("Fluid Model saves ", round(hours_saved, 2), " hours/year more than COI\n\n", sep="")

# SKU overlap analysis
if (use_q2) {
  fluid_parts <- fluid_skus$PartNo
} else {
  fluid_parts <- fluid_skus$PartNo
}
coi_parts <- coi_skus$PartNo

overlap <- length(intersect(fluid_parts, coi_parts))
cat("SKU Selection Overlap:\n")
cat("  - Fluid Model SKUs: ", n_fluid, "\n", sep="")
cat("  - COI SKUs: ", n_coi, "\n", sep="")
cat("  - Common SKUs: ", overlap, " (", round(overlap/n_fluid*100, 1), "%)\n", sep="")
cat("  - Different SKUs: ", n_fluid - overlap, "\n\n", sep="")

### =========================
### STEP 6: Save Results
### =========================
cat("Saving results...\n")

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
### STEP 7: Visualizations
### =========================
cat("\nCreating visualizations...\n")

# Plot 1: Benefit Distribution Comparison
plot_data <- rbind(
  data.table(Method = "Fluid Model", Benefit = if(use_q2) fluid_skus$Benefit else fluid_skus$Benefit),
  data.table(Method = "COI", Benefit = coi_skus$Benefit_COI)
)

p1 <- ggplot(plot_data, aes(x = Benefit, fill = Method)) +
  geom_histogram(bins = 50, alpha = 0.7, position = "identity") +
  facet_wrap(~Method, ncol = 1, scales = "free_y") +
  labs(
    title = "Benefit Distribution: Fluid Model vs COI",
    subtitle = paste0("Total Benefit - Fluid: ", format(round(fluid_benefit), big.mark=","),
                      " min, COI: ", format(round(coi_benefit), big.mark=","), " min"),
    x = "Benefit per SKU (minutes/year)",
    y = "Count"
  ) +
  theme_minimal() +
  theme(legend.position = "none")

ggsave("Q5_benefit_distribution.png", p1, width = 10, height = 8, dpi = 150)
cat("  - Saved: Q5_benefit_distribution.png\n")

# Plot 2: Volume Allocation Comparison
if (use_q2) {
  # Merge for comparison
  compare_alloc <- merge(
    fluid_skus[, .(PartNo, AllocVol_Fluid = AllocatedVolume_m3)],
    coi_skus[, .(PartNo, AllocVol_COI = AllocatedVolume_COI)],
    by = "PartNo",
    all = TRUE
  )
} else {
  compare_alloc <- merge(
    fluid_skus[, .(PartNo, AllocVol_Fluid = AllocatedVolume_m3)],
    coi_skus[, .(PartNo, AllocVol_COI = AllocatedVolume_COI)],
    by = "PartNo",
    all = TRUE
  )
}

compare_alloc[is.na(AllocVol_Fluid), AllocVol_Fluid := 0]
compare_alloc[is.na(AllocVol_COI), AllocVol_COI := 0]

p2 <- ggplot(compare_alloc[AllocVol_Fluid > 0 | AllocVol_COI > 0][1:min(50, .N)],
             aes(x = AllocVol_Fluid, y = AllocVol_COI)) +
  geom_point(alpha = 0.6, color = "steelblue") +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "red") +
  labs(
    title = "Volume Allocation: Fluid Model vs COI",
    subtitle = "Points above line = COI allocates more volume",
    x = "Fluid Model Allocated Volume (m³)",
    y = "COI Allocated Volume (m³)"
  ) +
  theme_minimal()

ggsave("Q5_volume_allocation_comparison.png", p2, width = 8, height = 8, dpi = 150)
cat("  - Saved: Q5_volume_allocation_comparison.png\n")

# Plot 3: Frequency vs COI scatter
p3 <- ggplot(sku_data[1:min(200, .N)], aes(x = Freq, y = COI)) +
  geom_point(alpha = 0.5, color = "darkgreen") +
  scale_x_log10() +
  scale_y_log10() +
  labs(
    title = "Frequency vs COI (Cube-Per-Order Index)",
    subtitle = "Lower COI with high frequency = ideal for FPA",
    x = "Pick Frequency (log scale)",
    y = "COI (log scale)"
  ) +
  theme_minimal()

ggsave("Q5_freq_vs_coi.png", p3, width = 10, height = 6, dpi = 150)
cat("  - Saved: Q5_freq_vs_coi.png\n")

cat("\n=== Bonus Question Complete ===\n")
cat("\nConclusion:\n")
if (fluid_benefit > coi_benefit) {
  cat("  Fluid Model outperforms COI by ", round(benefit_pct, 2), "%\n", sep="")
  cat("  This is because Fluid Model optimizes the trade-off between\n")
  cat("  pick frequency and replenishment costs using viscosity ranking.\n")
} else {
  cat("  COI outperforms Fluid Model by ", round(-benefit_pct, 2), "%\n", sep="")
}
