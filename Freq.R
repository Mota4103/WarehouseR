library(data.table)

# Assuming sku_freq is already calculated
# sku_freq[, PickCount := .N, by = PartNo]

# Rank by PickCount
setorder(sku_freq, -PickCount)
sku_freq[, Rank := 1:.N]

# Total number of SKUs
total_skus <- nrow(sku_freq)

# Calculate cutoff ranks
high_cut <- ceiling(0.10 * total_skus)   # top 10% SKUs
med_cut  <- ceiling(0.35 * total_skus)   # top 35% = 10% + 25%
# remaining 65% → Low

# Assign category based on SKU rank
sku_freq[, Category := fifelse(Rank <= high_cut, "High",
                               fifelse(Rank <= med_cut, "Medium", "Low"))]

### =========================
### OUTPUT
### =========================
cat("\n=== Top 20 SKUs by pick count ===\n")
print(sku_freq[1:20])

cat("\nSKU count by category:\n")
print(sku_freq[, .N, by = Category])

# Save to CSV
fwrite(sku_freq, "SKU_pick_frequency_pareto_sku_based.csv")

