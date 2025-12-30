###############################################################################
# Q3_Visualization.R - Better FPA Visualizations
# Shows actual SKU placement and associations
###############################################################################

library(data.table)
library(ggplot2)

cat("=== Q3: Enhanced Visualizations ===\n\n")

# Load slotting result
slotting <- fread("Q3_slotting_result.csv")
cat("Loaded ", nrow(slotting), " SKUs\n\n", sep="")

### =========================
### 1. HEATMAP: Cabinet × Floor with Frequency
### =========================
cat("Creating Cabinet × Floor heatmap...\n")

# Create a summary by Cabinet/Floor
heatmap_data <- slotting[!is.na(Cabinet) & !is.na(Floor), .(
  PartNo = PartNo[1],
  PartName = substr(PartName[1], 1, 15),
  Frequency = Frequency[1],
  Viscosity = round(Viscosity[1], 0)
), by = .(Cabinet, Floor)]

p_heatmap <- ggplot(heatmap_data, aes(x = factor(Cabinet), y = factor(Floor))) +
  geom_tile(aes(fill = Frequency), color = "white", linewidth = 0.5) +
  geom_text(aes(label = paste0(substr(PartNo, 1, 8), "\n", Frequency)),
            size = 2, color = "white") +
  scale_fill_gradient(low = "steelblue", high = "darkred", name = "Frequency") +
  scale_y_discrete(limits = rev(levels(factor(heatmap_data$Floor)))) +
  labs(
    title = "FPA Heatmap: SKU Placement by Cabinet and Floor",
    subtitle = "Each cell shows PartNo (truncated) and annual pick frequency",
    x = "Cabinet Number",
    y = "Floor Level"
  ) +
  theme_minimal() +
  theme(
    axis.text.x = element_text(size = 7),
    plot.title = element_text(size = 14, face = "bold")
  )

ggsave("Q3_heatmap_cabinet_floor.png", p_heatmap, width = 18, height = 8, dpi = 150)
cat("  - Saved: Q3_heatmap_cabinet_floor.png\n")

### =========================
### 2. FLOOR-BY-FLOOR VIEW with Labels
### =========================
cat("Creating floor-by-floor view...\n")

# Create a detailed floor view with dynamic text sizing
floor_plots <- list()

for (f in 1:5) {
  floor_data <- slotting[Floor == f]
  if (nrow(floor_data) == 0) next
  setorder(floor_data, Cabinet, SubPosStart_m)

  # Calculate width ratio for dynamic text sizing
  floor_data[, WidthRatio := (SubPosEnd_m - SubPosStart_m) / 1.98]

  # Shorter labels for narrow boxes
  floor_data[, Label := ifelse(WidthRatio >= 0.5,
                                paste0(substr(PartNo, 1, 8), "\n", Frequency),
                                ifelse(WidthRatio >= 0.3,
                                       substr(PartNo, 1, 6),
                                       substr(PartNo, 1, 4)))]

  floor_data[, TextSize := ifelse(WidthRatio >= 0.5, 2.0,
                                   ifelse(WidthRatio >= 0.3, 1.5, 1.2))]

  p <- ggplot(floor_data, aes(xmin = (Cabinet-1) + SubPosStart_m/1.98,
                               xmax = (Cabinet-1) + SubPosEnd_m/1.98,
                               ymin = 0.1, ymax = 0.9)) +
    geom_rect(aes(fill = Frequency), color = "black", linewidth = 0.3) +
    geom_text(aes(x = (Cabinet-1) + (SubPosStart_m + SubPosEnd_m)/(2*1.98),
                  y = 0.5,
                  label = Label,
                  size = TextSize),
              color = "white", fontface = "bold", show.legend = FALSE) +
    scale_size_identity() +
    scale_fill_gradient(low = "steelblue", high = "red", name = "Freq") +
    scale_x_continuous(breaks = 0:23 + 0.5, labels = 1:24) +
    labs(
      title = paste0("Floor ", f, " - ",
                    ifelse(f == 3, "GOLDEN ZONE (Best Ergonomics)",
                    ifelse(f %in% c(2,4), "Good Ergonomics",
                    "Lower/Upper (Less Ergonomic)"))),
      subtitle = paste0("SKUs: ", nrow(floor_data),
                       " | Total Freq: ", format(sum(floor_data$Frequency), big.mark=","),
                       " | Avg Viscosity: ", round(mean(floor_data$Viscosity), 0)),
      x = "Cabinet", y = ""
    ) +
    theme_minimal() +
    theme(
      axis.text.y = element_blank(),
      axis.ticks.y = element_blank(),
      plot.title = element_text(size = 12, face = "bold"),
      legend.position = "right"
    )

  ggsave(paste0("Q3_floor_", f, "_detail.png"), p, width = 16, height = 3, dpi = 150)
  cat("  - Saved: Q3_floor_", f, "_detail.png\n", sep="")
}

### =========================
### 3. COMBINED FLOOR VIEW (All 5 floors stacked)
### =========================
cat("Creating combined floor view...\n")

p_combined <- ggplot(slotting[!is.na(Cabinet)],
                     aes(x = factor(Cabinet), y = factor(Floor))) +
  geom_tile(aes(fill = log10(Frequency + 1)), color = "white", linewidth = 0.3) +
  geom_text(aes(label = substr(PartNo, 1, 6)), size = 1.8, color = "white") +
  scale_fill_gradient(low = "lightblue", high = "darkred",
                      name = "Log10(Freq)",
                      breaks = c(2, 2.5, 3, 3.5, 4),
                      labels = c("100", "316", "1K", "3.2K", "10K")) +
  scale_y_discrete(limits = rev(c("1", "2", "3", "4", "5"))) +
  labs(
    title = "FPA Complete Layout - All 5 Floors",
    subtitle = paste0("120 Positions (24 Cabinets × 5 Floors) | ",
                      "Floor 3 = Golden Zone (Highest Viscosity SKUs)"),
    x = "Cabinet Number (1-24)",
    y = "Floor Level"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(size = 14, face = "bold"),
    axis.text = element_text(size = 8)
  )

ggsave("Q3_combined_layout.png", p_combined, width = 16, height = 6, dpi = 150)
cat("  - Saved: Q3_combined_layout.png\n")

### =========================
### 4. ASSOCIATION VISUALIZATION
### =========================
cat("Creating association visualization...\n")

# Find associated pairs
associated <- slotting[AssociatedWith != "", .(PartNo, AssociatedWith, Cabinet, Floor, Frequency)]

if (nrow(associated) > 0) {
  # Parse associations
  assoc_list <- list()
  for (i in 1:nrow(associated)) {
    partners <- strsplit(associated$AssociatedWith[i], ",")[[1]]
    for (p in partners) {
      if (nchar(trimws(p)) > 0) {
        assoc_list[[length(assoc_list) + 1]] <- data.table(
          Item1 = associated$PartNo[i],
          Item2 = trimws(p),
          Item1_Cab = associated$Cabinet[i],
          Item1_Floor = associated$Floor[i],
          Item1_Freq = associated$Frequency[i]
        )
      }
    }
  }

  if (length(assoc_list) > 0) {
    assoc_pairs <- rbindlist(assoc_list)

    # Find Item2 positions
    assoc_pairs <- merge(assoc_pairs,
                         slotting[, .(PartNo, Cabinet, Floor, Frequency)],
                         by.x = "Item2", by.y = "PartNo", all.x = TRUE)
    setnames(assoc_pairs, c("Cabinet", "Floor", "Frequency"),
             c("Item2_Cab", "Item2_Floor", "Item2_Freq"))

    # Filter to only pairs where both are in FPA
    valid_pairs <- assoc_pairs[!is.na(Item2_Cab)]

    if (nrow(valid_pairs) > 0) {
      # Calculate distance
      valid_pairs[, CabDistance := abs(Item1_Cab - Item2_Cab)]
      valid_pairs[, FloorDistance := abs(Item1_Floor - Item2_Floor)]
      valid_pairs[, TotalDistance := CabDistance + FloorDistance]

      # Summary
      cat("\n  Associated pairs in FPA: ", nrow(valid_pairs), "\n", sep="")
      cat("  Average cabinet distance: ", round(mean(valid_pairs$CabDistance), 2), "\n", sep="")
      cat("  Average floor distance: ", round(mean(valid_pairs$FloorDistance), 2), "\n", sep="")

      # Show some examples
      cat("\n  Top 20 Associated Pairs:\n")
      setorder(valid_pairs, TotalDistance)
      print(head(valid_pairs[, .(Item1, Item2,
                                 Item1_Pos = paste0("C", Item1_Cab, "F", Item1_Floor),
                                 Item2_Pos = paste0("C", Item2_Cab, "F", Item2_Floor),
                                 CabDist = CabDistance, FloorDist = FloorDistance)], 20))

      # Save association summary
      fwrite(valid_pairs, "Q3_associated_pairs_positions.csv")
      cat("\n  - Saved: Q3_associated_pairs_positions.csv\n")

      # Create association distance plot
      p_assoc <- ggplot(valid_pairs, aes(x = CabDistance, y = FloorDistance)) +
        geom_jitter(aes(size = Item1_Freq + Item2_Freq, color = TotalDistance),
                    alpha = 0.6, width = 0.2, height = 0.2) +
        scale_color_gradient(low = "green", high = "red", name = "Total\nDistance") +
        scale_size_continuous(name = "Combined\nFrequency", range = c(2, 10)) +
        labs(
          title = "Association Pair Distances",
          subtitle = paste0(nrow(valid_pairs), " pairs | Closer = Better (green)"),
          x = "Cabinet Distance",
          y = "Floor Distance"
        ) +
        theme_minimal()

      ggsave("Q3_association_distances.png", p_assoc, width = 10, height = 8, dpi = 150)
      cat("  - Saved: Q3_association_distances.png\n")
    }
  }
}

### =========================
### 5. FLOOR DISTRIBUTION with SKU details
### =========================
cat("Creating enhanced floor distribution...\n")

floor_summary <- slotting[!is.na(Floor), .(
  SKUs = .N,
  TotalFrequency = sum(Frequency),
  AvgViscosity = round(mean(Viscosity), 0),
  TopSKU = PartNo[which.max(Frequency)],
  TopFreq = max(Frequency)
), by = Floor]
setorder(floor_summary, Floor)

# Add ergonomic labels
floor_summary[, Ergonomic := c("Lower (Score=60)", "Good (Score=90)",
                                "GOLDEN ZONE (Score=100)", "Good (Score=90)",
                                "Upper (Score=60)")]

p_floor <- ggplot(floor_summary, aes(x = factor(Floor), y = SKUs)) +
  geom_bar(stat = "identity", aes(fill = Ergonomic)) +
  geom_text(aes(label = paste0(SKUs, " SKUs\n",
                               format(TotalFrequency, big.mark=","), " picks")),
            vjust = -0.3, size = 3) +
  scale_fill_manual(values = c("GOLDEN ZONE (Score=100)" = "gold",
                               "Good (Score=90)" = "steelblue",
                               "Lower (Score=60)" = "gray50",
                               "Upper (Score=60)" = "gray50")) +
  labs(
    title = "SKU Distribution by Floor with Ergonomic Zones",
    subtitle = "Golden Zone (Floor 3) has highest viscosity SKUs for best ergonomics",
    x = "Floor Level",
    y = "Number of SKUs"
  ) +
  theme_minimal() +
  theme(legend.position = "bottom")

ggsave("Q3_floor_distribution_enhanced.png", p_floor, width = 10, height = 7, dpi = 150)
cat("  - Saved: Q3_floor_distribution_enhanced.png\n")

### =========================
### 6. TABLE: Floor Summary
### =========================
cat("\n=== Floor Summary ===\n")
print(floor_summary[, .(Floor, Ergonomic, SKUs, TotalFrequency, AvgViscosity, TopSKU, TopFreq)])

cat("\n=== Visualization Complete ===\n")
