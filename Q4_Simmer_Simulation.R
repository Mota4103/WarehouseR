###############################################################################
# Q4_Simmer_Simulation.R - FPA Picking Simulation using simmer
###############################################################################

# Install simmer if needed
if (!require(simmer)) install.packages("simmer")
if (!require(simmer.plot)) install.packages("simmer.plot")

library(simmer)
library(simmer.plot)
library(data.table)
library(ggplot2)

cat("=== FPA Picking Simulation (simmer) ===\n\n")

### =========================
### LOAD DATA
### =========================
cat("Loading data...\n")

pick_lines <- fread("Simio_OrderPickLines.csv")
sku_params <- fread("Simio_SKU_Params.csv")
positions <- fread("Simio_Positions_in_FPA.csv")
std_times <- fread("Simio_StandardTime.csv")

cat("  - Pick lines: ", format(nrow(pick_lines), big.mark=","), "\n", sep="")
cat("  - SKUs: ", nrow(sku_params), "\n", sep="")
cat("  - Positions: ", nrow(positions), "\n\n", sep="")

### =========================
### SIMULATION PARAMETERS
### =========================
cat("Setting up parameters...\n")

# Time parameters (in minutes)
WALK_SPEED <- 100  # meters per minute
CHECK_PICK_TIME <- 0.4  # min per line
PICK_PER_BOX_TIME <- 0.1  # min per box
SCAN_TIME <- 0.083  # min per scan
REPLENISH_NORMAL_TIME <- 15  # min per trip
REPLENISH_EMERGENCY_TIME <- 120  # min (open container)

# Resources
NUM_PICKERS <- 40  # Workers per shift (from Q1: 80 total / 2 shifts)

# Simulation duration (simulate 1 day = 480 min for 1 shift)
SIM_DURATION <- 480  # 8 hours in minutes

# Cabinet distances from start point (between Cab 3 and 4)
# Using walking distances calculated in Q3
cabinet_distances <- c(
  "1" = 4.95, "2" = 2.97, "3" = 0.99, "4" = 0.99, "5" = 2.97, "6" = 4.95,
  "7" = 7.63, "8" = 5.65, "9" = 3.67, "10" = 3.67, "11" = 5.65, "12" = 7.63,
  "13" = 10.99, "14" = 9.01, "15" = 7.03, "16" = 7.03, "17" = 9.01, "18" = 10.99,
  "19" = 10.31, "20" = 8.33, "21" = 6.35, "22" = 6.35, "23" = 8.33, "24" = 10.31
)

cat("  - Pickers: ", NUM_PICKERS, "\n", sep="")
cat("  - Simulation duration: ", SIM_DURATION, " min (1 shift)\n", sep="")
cat("  - Walk speed: ", WALK_SPEED, " m/min\n\n", sep="")

### =========================
### PREPARE PICK DATA
### =========================
cat("Preparing pick data...\n")

# Merge pick lines with position info
pick_data <- merge(pick_lines, sku_params[, .(PartNo, CabinetNo, MaxPieces, ReorderPoint)],
                   by = "PartNo", all.x = TRUE)

# Calculate walking distance for each pick
pick_data[, WalkDistance := cabinet_distances[as.character(Cabinet)]]
pick_data[is.na(WalkDistance), WalkDistance := 5]  # Default 5m

# Calculate pick time for each line
pick_data[, PickTime := CHECK_PICK_TIME + PICK_PER_BOX_TIME * ceiling(ScanQty / 10) + SCAN_TIME]

# Calculate walk time (round trip: go and return)
pick_data[, WalkTime := 2 * WalkDistance / WALK_SPEED]

# Total time per pick
pick_data[, TotalTime := WalkTime + PickTime]

# Sample a day's worth of picks for simulation
# Use a specific day with typical volume
sample_day <- pick_data[ShippingDay == 20110901]  # First day in data
if (nrow(sample_day) < 100) {
  # If not enough data, sample from all
  set.seed(42)
  sample_day <- pick_data[sample(.N, min(2000, .N))]
}

cat("  - Sample picks for simulation: ", nrow(sample_day), "\n", sep="")
cat("  - Avg walk distance: ", round(mean(sample_day$WalkDistance), 2), " m\n", sep="")
cat("  - Avg pick time: ", round(mean(sample_day$PickTime), 3), " min\n", sep="")
cat("  - Avg total time: ", round(mean(sample_day$TotalTime), 3), " min\n\n", sep="")

### =========================
### INVENTORY TRACKING
### =========================
# Initialize inventory levels
inventory <- copy(sku_params)
inventory[, CurrentQty := MaxPieces]
inventory[, PickCount := 0L]
inventory[, ReplenishCount := 0L]
inventory[, StockoutCount := 0L]

# Function to process a pick (deduct inventory)
process_pick <- function(part_no, qty) {
  idx <- which(inventory$PartNo == part_no)
  if (length(idx) > 0) {
    inventory[idx, CurrentQty := CurrentQty - qty]
    inventory[idx, PickCount := PickCount + 1L]

    # Check for replenishment need
    if (inventory[idx, CurrentQty] <= inventory[idx, ReorderPoint]) {
      inventory[idx, ReplenishCount := ReplenishCount + 1L]
      inventory[idx, CurrentQty := MaxPieces]  # Replenish to max
    }

    # Check for stockout
    if (inventory[idx, CurrentQty] < 0) {
      inventory[idx, StockoutCount := StockoutCount + 1L]
      inventory[idx, CurrentQty := 0]
    }
  }
}

### =========================
### SIMMER SIMULATION
### =========================
cat("Running simulation...\n\n")

# Create simulation environment
env <- simmer("FPA_Picking")

# Define picker trajectory (what each pick order does)
pick_trajectory <- trajectory("pick_order") %>%
  # Seize a picker
  seize("picker", 1) %>%

  # Walk to position (use attribute for walk time)
  timeout(function() get_attribute(env, "walk_time")) %>%

  # Perform picking
  timeout(function() get_attribute(env, "pick_time")) %>%

  # Walk back to start
  timeout(function() get_attribute(env, "walk_time")) %>%

  # Release picker

  release("picker", 1)

# Add picker resources
env %>%
  add_resource("picker", capacity = NUM_PICKERS)

# Add pick orders as arrivals
# Convert to inter-arrival times
sample_day <- sample_day[order(LineNo)]
sample_day[, ArrivalTime := (1:.N) * (SIM_DURATION / .N)]  # Spread evenly

for (i in 1:nrow(sample_day)) {
  env %>%
    add_generator(
      paste0("pick_", i),
      pick_trajectory,
      at(sample_day$ArrivalTime[i]),
      mon = 2
    ) %>%
    # Set attributes for this pick
    add_global(paste0("walk_", i), sample_day$WalkTime[i]) %>%
    add_global(paste0("pick_", i), sample_day$PickTime[i])
}

# Simplified approach: use average times
avg_walk_time <- mean(sample_day$WalkTime)
avg_pick_time <- mean(sample_day$PickTime)

# Recreate with simpler model
env <- simmer("FPA_Picking")

pick_trajectory <- trajectory("pick_order") %>%
  seize("picker", 1) %>%
  timeout(avg_walk_time) %>%  # Walk to position
  timeout(avg_pick_time) %>%   # Pick
  timeout(avg_walk_time) %>%  # Walk back
  release("picker", 1)

env %>%
  add_resource("picker", capacity = NUM_PICKERS) %>%
  add_generator(
    "pick_order",
    pick_trajectory,
    function() rexp(1, nrow(sample_day) / SIM_DURATION),  # Poisson arrivals
    mon = 2
  )

# Run simulation
env %>% run(until = SIM_DURATION)

### =========================
### RESULTS
### =========================
cat("=== SIMULATION RESULTS ===\n\n")

# Get resource statistics
picker_stats <- get_mon_resources(env)
arrival_stats <- get_mon_arrivals(env)

# Calculate metrics
total_picks <- nrow(arrival_stats)
total_time <- SIM_DURATION
picks_per_hour <- total_picks / (total_time / 60)
picks_per_manhour <- total_picks / (NUM_PICKERS * total_time / 60)

cat("Performance Metrics:\n")
cat("  - Total picks completed: ", total_picks, "\n", sep="")
cat("  - Simulation time: ", total_time, " min (", total_time/60, " hours)\n", sep="")
cat("  - Picks per hour: ", round(picks_per_hour, 1), "\n", sep="")
cat("  - Lines per Man-Hour: ", round(picks_per_manhour, 2), "\n", sep="")
cat("  - (Q1 baseline: ~7-8 lines/man-hour)\n\n")

# Resource utilization
if (nrow(picker_stats) > 0) {
  avg_utilization <- mean(picker_stats$server / picker_stats$capacity, na.rm = TRUE)
  cat("Picker Utilization:\n")
  cat("  - Average: ", round(avg_utilization * 100, 1), "%\n", sep="")
  cat("  - Peak queue: ", max(picker_stats$queue, na.rm = TRUE), "\n\n", sep="")
}

# Arrival statistics
if (nrow(arrival_stats) > 0) {
  cat("Pick Order Statistics:\n")
  cat("  - Avg flow time: ", round(mean(arrival_stats$flow_time), 2), " min\n", sep="")
  cat("  - Avg wait time: ", round(mean(arrival_stats$flow_time - arrival_stats$activity_time), 2), " min\n", sep="")
  cat("  - Avg activity time: ", round(mean(arrival_stats$activity_time), 2), " min\n\n", sep="")
}

### =========================
### VISUALIZATIONS
### =========================
cat("Creating visualizations...\n")

# 1. Resource utilization over time
if (nrow(picker_stats) > 0) {
  p_util <- plot(env, what = "resources", metric = "utilization") +
    labs(title = "Picker Utilization Over Time",
         subtitle = paste0(NUM_PICKERS, " pickers, ", total_picks, " picks")) +
    theme_minimal()

  ggsave("Q4_simmer_utilization.png", p_util, width = 10, height = 6, dpi = 150)
  cat("  - Saved: Q4_simmer_utilization.png\n")
}

# 2. Flow time distribution
if (nrow(arrival_stats) > 0) {
  p_flow <- ggplot(arrival_stats, aes(x = flow_time)) +
    geom_histogram(bins = 30, fill = "steelblue", color = "white") +
    geom_vline(xintercept = mean(arrival_stats$flow_time),
               color = "red", linetype = "dashed", linewidth = 1) +
    labs(title = "Pick Order Flow Time Distribution",
         subtitle = paste0("Mean = ", round(mean(arrival_stats$flow_time), 2), " min"),
         x = "Flow Time (minutes)",
         y = "Count") +
    theme_minimal()

  ggsave("Q4_simmer_flowtime.png", p_flow, width = 10, height = 6, dpi = 150)
  cat("  - Saved: Q4_simmer_flowtime.png\n")
}

# 3. Queue over time
if (nrow(picker_stats) > 0) {
  p_queue <- plot(env, what = "resources", metric = "usage",
                  names = "picker", items = "queue") +
    labs(title = "Picker Queue Length Over Time") +
    theme_minimal()

  ggsave("Q4_simmer_queue.png", p_queue, width = 10, height = 6, dpi = 150)
  cat("  - Saved: Q4_simmer_queue.png\n")
}

### =========================
### SENSITIVITY ANALYSIS
### =========================
cat("\nRunning sensitivity analysis (varying number of pickers)...\n")

run_simulation <- function(n_pickers, n_picks, sim_time) {
  env <- simmer("FPA_test")

  traj <- trajectory() %>%
    seize("picker", 1) %>%
    timeout(avg_walk_time * 2 + avg_pick_time) %>%
    release("picker", 1)

  env %>%
    add_resource("picker", capacity = n_pickers) %>%
    add_generator("pick", traj,
                  function() rexp(1, n_picks / sim_time),
                  mon = 2) %>%
    run(until = sim_time)

  arrivals <- get_mon_arrivals(env)
  resources <- get_mon_resources(env)

  list(
    picks = nrow(arrivals),
    avg_flow = mean(arrivals$flow_time),
    avg_wait = mean(arrivals$flow_time - arrivals$activity_time),
    utilization = mean(resources$server / resources$capacity, na.rm = TRUE)
  )
}

# Test different picker counts
picker_counts <- c(20, 30, 40, 50, 60)
sensitivity_results <- data.table()

for (np in picker_counts) {
  result <- run_simulation(np, nrow(sample_day), SIM_DURATION)
  sensitivity_results <- rbind(sensitivity_results, data.table(
    Pickers = np,
    Picks = result$picks,
    LPMH = result$picks / (np * SIM_DURATION / 60),
    AvgFlowTime = result$avg_flow,
    AvgWaitTime = result$avg_wait,
    Utilization = result$utilization * 100
  ))
}

cat("\nSensitivity Analysis Results:\n")
print(sensitivity_results)

# Plot sensitivity
p_sens <- ggplot(sensitivity_results, aes(x = Pickers)) +
  geom_line(aes(y = LPMH, color = "LPMH"), linewidth = 1) +
  geom_point(aes(y = LPMH, color = "LPMH"), size = 3) +
  geom_line(aes(y = Utilization / 10, color = "Utilization %"), linewidth = 1) +
  geom_point(aes(y = Utilization / 10, color = "Utilization %"), size = 3) +
  scale_y_continuous(
    name = "Lines per Man-Hour",
    sec.axis = sec_axis(~.*10, name = "Utilization %")
  ) +
  scale_color_manual(values = c("LPMH" = "steelblue", "Utilization %" = "coral")) +
  labs(title = "Sensitivity Analysis: Number of Pickers",
       subtitle = "Impact on productivity and utilization",
       x = "Number of Pickers",
       color = "Metric") +
  theme_minimal() +
  theme(legend.position = "bottom")

ggsave("Q4_simmer_sensitivity.png", p_sens, width = 10, height = 6, dpi = 150)
cat("  - Saved: Q4_simmer_sensitivity.png\n")

### =========================
### SAVE RESULTS
### =========================
fwrite(sensitivity_results, "Q4_simmer_sensitivity.csv")
cat("  - Saved: Q4_simmer_sensitivity.csv\n")

if (nrow(arrival_stats) > 0) {
  fwrite(arrival_stats, "Q4_simmer_arrivals.csv")
  cat("  - Saved: Q4_simmer_arrivals.csv\n")
}

cat("\n=== Simulation Complete ===\n")
