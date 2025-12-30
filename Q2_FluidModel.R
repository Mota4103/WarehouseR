###############################################################################
# Q2_FluidModel.R - Fluid Model FPA Design (Question 2 - 20 points)
# หาจำนวน SKU ที่เหมาะสมและจัดสรรปริมาตรใน FPA 36 m³
###############################################################################

library(data.table)
library(ggplot2)

cat("=== Q2: Fluid Model FPA Design ===\n\n")

### =========================
### PARAMETERS (from case)
### =========================
V_fpa <- 36.0        # FPA total volume (m³)
s <- 2.0             # Time saved per FPA pick (min/line)
Cr <- 15.0           # Replenishment time (min/trip)

cat("Parameters:\n")
cat("  - FPA Volume (V): ", V_fpa, " m³\n", sep="")
cat("  - Time saved per pick (s): ", s, " min/line\n", sep="")
cat("  - Replenishment time (Cr): ", Cr, " min/trip\n\n", sep="")

### =========================
### STEP 1: Load Data
### =========================
cat("Loading data...\n")

# Load from Freq.R output
if (!file.exists("DataFreq.csv")) {
  stop("DataFreq.csv not found. Please run Freq.R first.")
}

sku_data <- fread("DataFreq.csv")
cat("  - Loaded ", nrow(sku_data), " SKUs from DataFreq.csv\n\n", sep="")

# Rename columns for clarity
# Volume = D_i (annual demand volume = Freq × CubM)
# Freq = f_i (annual pick frequency)
# Viscosity = η_i = f_i / √(D_i)
setnames(sku_data, c("Volume", "Freq", "Viscosity"),
         c("D_i", "f_i", "eta_i"), skip_absent = TRUE)

# Sort by viscosity (highest first)
setorder(sku_data, -eta_i)
sku_data[, Rank := 1:.N]

### =========================
### STEP 2: Iterative Benefit Calculation
### =========================
cat("Calculating optimal SKU selection...\n\n")

# Function to calculate total benefit for first n SKUs
calculate_total_benefit <- function(n, sku_dt, V, s, Cr) {
  if (n == 0) return(0)

  # Select first n SKUs (by viscosity rank)
  selected <- sku_dt[1:n]

  # Calculate volume allocation: v_i* = V × √(D_i) / Σ√(D_j)
  sqrt_D <- sqrt(selected$D_i)
  sum_sqrt_D <- sum(sqrt_D)

  # Allocated volume for each SKU
  v_star <- V * sqrt_D / sum_sqrt_D

  # Calculate benefit for each SKU: B_i = s × f_i - Cr × (D_i / v_i*)
  # D_i / v_i* = replenishment trips per year
  benefit <- s * selected$f_i - Cr * (selected$D_i / v_star)

  # Total benefit = sum of all individual benefits
  return(sum(benefit))
}

# Calculate benefit for each possible number of SKUs
n_skus <- nrow(sku_data)
results <- data.table(
  n = 1:n_skus,
  TotalBenefit = sapply(1:n_skus, function(n) {
    calculate_total_benefit(n, sku_data, V_fpa, s, Cr)
  })
)

# Find the marginal benefit (change in total benefit)
results[, MarginalBenefit := TotalBenefit - shift(TotalBenefit, 1, fill = 0)]

# Find optimal n (where total benefit is maximized)
optimal_n <- results[which.max(TotalBenefit), n]
max_benefit <- results[which.max(TotalBenefit), TotalBenefit]

cat("Benefit Analysis:\n")
cat("  - Optimal number of SKUs: ", optimal_n, "\n", sep="")
cat("  - Maximum total benefit: ", round(max_benefit, 2), " minutes saved per year\n\n", sep="")

### =========================
### STEP 3: Volume Allocation for Optimal SKUs
### =========================
cat("Allocating FPA volume to ", optimal_n, " SKUs...\n\n", sep="")

# Select optimal SKUs
optimal_skus <- sku_data[1:optimal_n]

# Calculate volume allocation
sqrt_D <- sqrt(optimal_skus$D_i)
sum_sqrt_D <- sum(sqrt_D)

optimal_skus[, v_star := V_fpa * sqrt(D_i) / sum_sqrt_D]

# Calculate individual benefit
optimal_skus[, Benefit := s * f_i - Cr * (D_i / v_star)]

# Calculate replenishment trips
optimal_skus[, ReplenishTrips := D_i / v_star]

# Verify total volume
total_allocated <- sum(optimal_skus$v_star)
cat("Volume Allocation Summary:\n")
cat("  - Total volume allocated: ", round(total_allocated, 4), " m³\n", sep="")
cat("  - FPA capacity: ", V_fpa, " m³\n", sep="")
cat("  - Utilization: ", round(total_allocated / V_fpa * 100, 2), "%\n\n", sep="")

### =========================
### STEP 4: Summary Statistics
### =========================
cat("=== Optimal FPA Design Summary ===\n\n")

cat("Selected SKUs: ", optimal_n, " out of ", n_skus, " (",
    round(optimal_n/n_skus*100, 1), "%)\n", sep="")
cat("Total Pick Frequency: ", format(sum(optimal_skus$f_i), big.mark=","), " lines/year\n", sep="")
cat("Total Demand Volume: ", round(sum(optimal_skus$D_i), 2), " m³/year\n", sep="")
cat("Total Benefit: ", round(max_benefit, 2), " minutes saved/year\n", sep="")
cat("  = ", round(max_benefit / 60, 2), " hours saved/year\n\n", sep="")

# Show top 20 SKUs
cat("Top 20 SKUs by Viscosity:\n")
print(optimal_skus[1:min(20, .N), .(
  Rank, PartNo,
  Freq = f_i,
  Demand_m3 = round(D_i, 4),
  Viscosity = round(eta_i, 2),
  Allocated_m3 = round(v_star, 4),
  Benefit_min = round(Benefit, 2)
)])

### =========================
### STEP 5: Visualization
### =========================
cat("\nCreating visualizations...\n")

# Plot 1: Total Benefit vs Number of SKUs
p1 <- ggplot(results, aes(x = n, y = TotalBenefit)) +
  geom_line(color = "blue", linewidth = 1) +
  geom_vline(xintercept = optimal_n, color = "red", linetype = "dashed", linewidth = 1) +
  geom_point(data = results[n == optimal_n], aes(x = n, y = TotalBenefit),
             color = "red", size = 4) +
  annotate("text", x = optimal_n + 20, y = max_benefit,
           label = paste0("Optimal: ", optimal_n, " SKUs\nBenefit: ",
                          format(round(max_benefit), big.mark=","), " min"),
           hjust = 0, vjust = 1) +
  labs(
    title = "Total Benefit vs Number of SKUs in FPA",
    subtitle = paste0("Fluid Model Optimization (V=", V_fpa, " m³, s=", s, " min, Cr=", Cr, " min)"),
    x = "Number of SKUs",
    y = "Total Benefit (minutes saved/year)"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(size = 14, face = "bold"),
    plot.subtitle = element_text(size = 11, color = "gray40")
  )

ggsave("Q2_benefit_vs_skus.png", p1, width = 10, height = 6, dpi = 150)
cat("  - Saved: Q2_benefit_vs_skus.png\n")

# Plot 2: Marginal Benefit
p2 <- ggplot(results[1:min(200, .N)], aes(x = n, y = MarginalBenefit)) +
  geom_line(color = "darkgreen", linewidth = 0.8) +
  geom_hline(yintercept = 0, color = "red", linetype = "dashed") +
  geom_vline(xintercept = optimal_n, color = "orange", linetype = "dashed") +
  labs(
    title = "Marginal Benefit per Additional SKU",
    subtitle = "When marginal benefit approaches zero, stop adding SKUs",
    x = "Number of SKUs",
    y = "Marginal Benefit (minutes)"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(size = 14, face = "bold")
  )

ggsave("Q2_marginal_benefit.png", p2, width = 10, height = 6, dpi = 150)
cat("  - Saved: Q2_marginal_benefit.png\n")

# Plot 3: Volume Allocation (top 50 SKUs)
top_50 <- optimal_skus[1:min(50, .N)]
top_50[, PartNo_short := substr(PartNo, 1, 15)]

p3 <- ggplot(top_50, aes(x = reorder(PartNo_short, -v_star), y = v_star)) +
  geom_bar(stat = "identity", fill = "steelblue") +
  labs(
    title = "Volume Allocation - Top 50 SKUs",
    subtitle = paste0("Total FPA Volume: ", V_fpa, " m³"),
    x = "Part Number",
    y = "Allocated Volume (m³)"
  ) +
  theme_minimal() +
  theme(
    axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5, size = 6),
    plot.title = element_text(size = 14, face = "bold")
  )

ggsave("Q2_volume_allocation.png", p3, width = 14, height = 6, dpi = 150)
cat("  - Saved: Q2_volume_allocation.png\n")

### =========================
### STEP 6: Save Results
### =========================
cat("\nSaving results...\n")

# Save optimal SKUs with allocation
output_cols <- c("Rank", "PartNo", "f_i", "D_i", "eta_i", "v_star", "Benefit", "ReplenishTrips")
setnames(optimal_skus, c("f_i", "D_i", "eta_i", "v_star"),
         c("Frequency", "DemandVolume_m3", "Viscosity", "AllocatedVolume_m3"),
         skip_absent = TRUE)

fwrite(optimal_skus[, .(Rank, PartNo, Frequency, DemandVolume_m3, Viscosity,
                        AllocatedVolume_m3, Benefit, ReplenishTrips)],
       "Q2_FPA_Optimal_SKUs.csv")
cat("  - Saved: Q2_FPA_Optimal_SKUs.csv (", nrow(optimal_skus), " SKUs)\n", sep="")

# Save benefit analysis
fwrite(results, "Q2_Benefit_Analysis.csv")
cat("  - Saved: Q2_Benefit_Analysis.csv\n")

# Save summary
summary_dt <- data.table(
  Parameter = c("FPA Volume (m³)", "Time Saved per Pick (min)",
                "Replenishment Time (min)", "Optimal Number of SKUs",
                "Total SKUs Available", "Percentage Selected",
                "Total Pick Frequency (lines/year)",
                "Total Demand Volume (m³/year)",
                "Maximum Total Benefit (min/year)",
                "Benefit in Hours/Year"),
  Value = c(V_fpa, s, Cr, optimal_n, n_skus,
            round(optimal_n/n_skus*100, 2),
            sum(optimal_skus$Frequency),
            round(sum(optimal_skus$DemandVolume_m3), 2),
            round(max_benefit, 2),
            round(max_benefit/60, 2))
)
fwrite(summary_dt, "Q2_Summary.csv")
cat("  - Saved: Q2_Summary.csv\n")

cat("\n=== Q2 Complete ===\n")
