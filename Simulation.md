# FPA Picking Simulation Documentation

## Overview

This document describes the discrete-event simulation model for comparing **Before FPA (Single Order Picking)** vs **After FPA (Optimized Picking)** using **SimPy** (Python) with **Triangular Distribution** for stochastic activity times.

---

## Simulation Model Structure

### Model Type
**Discrete-Event Simulation (DES)** with:
- Entities: Pick orders (individual pick lines)
- Resources: Pickers (workers)
- Queuing: FIFO (First-In-First-Out)
- **Stochastic Times: Triangular Distribution**

### System Flow

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Order     │────▶│   Queue     │────▶│   Picker    │────▶│  Complete   │
│  Arrival    │     │  (Wait)     │     │  Process    │     │             │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
                                              │
                                              ▼
                                    ┌─────────────────┐
                                    │  Walk → Search  │
                                    │  → Pick → Scan  │
                                    │  → Walk Back    │
                                    └─────────────────┘
```

---

## Scenarios Compared

### 1. Before FPA (Single Order Picking)
- Random storage in 5,332 m² warehouse
- Long walking distances
- **Search time dominates (59% of total pick time)**

### 2. After FPA (Optimized Picking)
- Consolidated FPA with 24 cabinets
- Distance-based slotting (high-frequency SKUs near start)
- **Zero search time (fixed known locations)**

---

## Input Data

### 1. Pick Order Data (`Simio_OrderPickLines.csv`)
| Column | Description |
|--------|-------------|
| OrderID | Unique order identifier |
| DateTimeStr | Arrival timestamp |
| PartNo | SKU part number |
| Cabinet | Cabinet location (1-24) |
| Floor | Floor level (1-5) |
| ScanQty | Quantity to pick |

**Total Records:** 203,236 pick lines

### 2. SKU Parameters (`Simio_SKU_Params.csv`)
| Column | Description |
|--------|-------------|
| PartNo | SKU part number |
| CabinetNo | Assigned cabinet |
| MaxPieces | Maximum inventory |
| ReorderPoint | floor(MaxPieces / 2) |

**Total SKUs:** 133

---

## Simulation Parameters

### Effective Workers Calculation
```
Shift Duration:         9 hours
Break Time:             1 hour per worker
Effective Fraction:     8/9 = 0.889

Workers per Shift:      40
Effective Workers:      40 × (8/9) = 35.56 workers

Total Workers (2 shifts): 80
Effective Workers/Day:    80 × (8/9) = 71.11 workers

Man-Hours per Day:
  = 80 workers × 9 hours × (8/9)
  = 80 × 8
  = 640 man-hours
```

### Activity Times - Triangular Distribution (min, mode, max)

| Activity | Before FPA | After FPA | Unit |
|----------|------------|-----------|------|
| Walk Distance | Tri(10, 25, 50) | Cabinet +/-20% | meters |
| Search Time | Tri(1.0, 2.21, 4.0) | **0 (None!)** | min |
| Check & Pick | Tri(0.3, 0.4, 0.6) | Tri(0.3, 0.4, 0.6) | min/line |
| Pick per Box | Tri(0.08, 0.1, 0.15) | Tri(0.08, 0.1, 0.15) | min/box |
| Scan | Tri(0.05, 0.083, 0.12) | Tri(0.05, 0.083, 0.12) | min |

### Cabinet Walking Distances (from Start Point)

Start point is between Cabinet 3 and 4 (center of Row 1 aisle).
Aisle width: 2.0 meters

```
Cabinet Order by Walking Distance:
3 → 4 → 2 → 5 → 9 → 10 → 1 → 6 → 8 → 11 → 21 → 22 → 15 → 16 → 7 → 12 → ...

┌─────────┬──────────┐
│ Cabinet │ Distance │
├─────────┼──────────┤
│ 3, 4    │ 0.99 m   │
│ 2, 5    │ 2.97 m   │
│ 9, 10   │ 3.67 m   │
│ 1, 6    │ 4.95 m   │
│ 8, 11   │ 5.65 m   │
│ 21, 22  │ 6.35 m   │
│ 15, 16  │ 7.03 m   │
│ 7, 12   │ 7.63 m   │
│ 20, 23  │ 8.33 m   │
│ 14, 17  │ 9.01 m   │
│ 19, 24  │ 10.31 m  │
│ 13, 18  │ 10.99 m  │
└─────────┴──────────┘

Average FPA Distance: ~6.5 m (mode)
```

---

## Process Logic

### 1. Order Arrival Process (Using ACTUAL Timestamps)
```python
def order_generator(env, pickers, pick_data, stats, scenario):
    """Generate pick orders based on ACTUAL arrival times from order data"""

    # Sort by actual arrival time
    pick_data_sorted = pick_data.sort_values(['DeliveryHour', 'DeliveryMinute'])

    # Get start time (first order's arrival)
    start_time_min = first_hour * 60 + first_minute

    for idx, row in pick_data_sorted.iterrows():
        # Calculate actual arrival time from order data
        arrival_time_min = (row['DeliveryHour'] * 60 + row['DeliveryMinute']) - start_time_min

        # Wait until actual arrival time
        yield env.timeout(wait_until)

        # Create pick order process
        if scenario == 'before':
            env.process(pick_order_before_fpa(env, pickers, row, stats))
        else:
            env.process(pick_order_after_fpa(env, pickers, row, stats))
```

### 2. Before FPA Pick Process (with Search Time)
```python
def pick_order_before_fpa(env, pickers, row, stats):
    """Before FPA: Single order picking with SEARCH TIME"""
    arrival_time = env.now

    # Generate times from TRIANGULAR distributions
    walk_distance = triangular(10, 25, 50)  # meters
    walk_time = 2 * walk_distance / WALK_SPEED  # Round trip

    search_time = triangular(1.0, 2.21, 4.0)  # SEARCH TIME!

    check_pick_time = triangular(0.3, 0.4, 0.6)
    scan_time = triangular(0.05, 0.083, 0.12)

    total_service = walk_time + search_time + check_pick_time + scan_time

    with pickers.request() as request:
        yield request
        yield env.timeout(total_service)
        stats.picks_completed += 1
```

### 3. After FPA Pick Process (No Search Time)
```python
def pick_order_after_fpa(env, pickers, row, stats):
    """After FPA: Optimized picking with NO SEARCH TIME"""
    arrival_time = env.now

    # Walk distance based on actual cabinet location +/- 20%
    cabinet_distance = row['CabinetDistance']
    walk_distance = triangular(
        cabinet_distance * 0.8,
        cabinet_distance,
        cabinet_distance * 1.2
    )
    walk_time = 2 * walk_distance / WALK_SPEED

    search_time = 0  # NO SEARCH TIME!

    check_pick_time = triangular(0.3, 0.4, 0.6)
    scan_time = triangular(0.05, 0.083, 0.12)

    total_service = walk_time + search_time + check_pick_time + scan_time

    with pickers.request() as request:
        yield request
        yield env.timeout(total_service)
        stats.picks_completed += 1
```

---

## Comparison Results

### Key Metrics (40 Pickers)

| Metric | Before FPA | After FPA | Change |
|--------|-----------|-----------|--------|
| Avg Service Time | 5.13 min | 2.27 min | **56% faster** |
| Total Service Time | 4,025 min | 1,781 min | **56% less work** |
| Utilization | 21.0% | 9.3% | -11.7% |
| Theoretical LPMH | 11.70 | 26.42 | **+126%** |
| Max Capacity/Day | 3,744 picks | 8,454 picks | **+126%** |

### Time Breakdown per Pick (Mode Values)

**Before FPA:**
```
┌────────────────┬──────────┬─────────┐
│ Activity       │ Time     │ % Total │
├────────────────┼──────────┼─────────┤
│ Walking        │ 0.50 min │ 16%     │
│ SEARCH         │ 2.21 min │ 69%     │  ← BOTTLENECK!
│ Check & Pick   │ 0.40 min │ 13%     │
│ Scan + Box     │ 0.18 min │ 6%      │
├────────────────┼──────────┼─────────┤
│ TOTAL          │ 3.19 min │ 100%    │
└────────────────┴──────────┴─────────┘
```

**After FPA:**
```
┌────────────────┬──────────┬─────────┐
│ Activity       │ Time     │ % Total │
├────────────────┼──────────┼─────────┤
│ Walking        │ 0.13 min │ 21%     │
│ SEARCH         │ 0.00 min │ 0%      │  ← ELIMINATED!
│ Check & Pick   │ 0.40 min │ 66%     │
│ Scan + Box     │ 0.18 min │ 30%     │
├────────────────┼──────────┼─────────┤
│ TOTAL          │ 0.61 min │ 100%    │
└────────────────┴──────────┴─────────┘
```

### Sensitivity Analysis

```
┌─────────┬─────────────┬────────────┬─────────────┬────────────┬──────────────┐
│ Pickers │ Before Util │ After Util │ Before LPMH │ After LPMH │ Capacity Gain│
├─────────┼─────────────┼────────────┼─────────────┼────────────┼──────────────┤
│ 20      │ 41.9%       │ 18.5%      │ 5.52        │ 5.51       │ +126%        │
│ 30      │ 28.0%       │ 12.4%      │ 3.68        │ 3.68       │ +126%        │
│ 40      │ 21.0%       │ 9.3%       │ 2.76        │ 2.76       │ +126%        │
│ 50      │ 16.8%       │ 7.4%       │ 2.21        │ 2.21       │ +126%        │
│ 60      │ 14.0%       │ 6.2%       │ 1.84        │ 1.84       │ +126%        │
└─────────┴─────────────┴────────────┴─────────────┴────────────┴──────────────┘
```

**Key Observations:**
- Utilization decreases as pickers increase (same workload, more workers)
- Actual LPMH decreases as pickers increase (productivity per worker drops)
- Capacity Gain is constant (+126%) - this is a process improvement

---

## Performance Metrics

### Metric Formulas

```
UTILIZATION = Total Service Time / (Pickers × Simulation Duration)
            = Sum of all pick service times / Total available picker-minutes

Example (40 pickers, 480 min, Before FPA):
  = 4,025 min / (40 × 480 min)
  = 4,025 / 19,200
  = 21.0%
```

```
THEORETICAL LPMH = 60 / Avg Service Time
                 = How many picks ONE picker can do per hour at 100% utilization

Example (After FPA):
  = 60 / 2.27 min
  = 26.42 picks/picker/hour
```

```
ACTUAL LPMH = Picks Completed / (Effective Pickers × Hours)
            = Productivity measure (depends on demand, not just capacity)

Example (40 pickers, 8 hours, After FPA):
  = 784 picks / (35.56 effective × 8 hours)
  = 2.76 picks/picker/hour
```

```
MAX CAPACITY = (Pickers × Duration) / Avg Service Time
             = Maximum picks possible at 100% utilization

Example (40 pickers, 480 min, After FPA):
  = (40 × 480) / 2.27
  = 8,454 picks/day
```

### Why Utilization and LPMH Change with Pickers

| More Pickers → | Effect |
|----------------|--------|
| Utilization | **Decreases** (same work divided among more workers) |
| Actual LPMH | **Decreases** (same picks / more workers = less per worker) |
| Wait Time | **Decreases** (more workers available) |
| Theoretical LPMH | **No change** (process property, not resource) |
| Capacity Gain | **No change** (process improvement ratio) |

---

## Simulation Execution

### Running the Simulations
```bash
# Activate virtual environment
source simpy_env/bin/activate

# Run FPA-only simulation
python Q4_SimPy_Simulation.py

# Run Before vs After comparison
python Q4_Comparison_Simulation.py
```

### Output Files

**Q4_SimPy_Simulation.py:**
| File | Description |
|------|-------------|
| `Q4_simpy_sensitivity.csv` | Sensitivity analysis results |
| `Q4_simpy_sensitivity.png` | LPMH vs Pickers chart |
| `Q4_simpy_waittime.png` | Wait time distribution |
| `Q4_simpy_flowtime.png` | Flow time distribution |

**Q4_Comparison_Simulation.py:**
| File | Description |
|------|-------------|
| `Q4_comparison_results.csv` | Before vs After comparison data |
| `Q4_comparison_lpmh.png` | LPMH comparison bar chart |
| `Q4_comparison_service.png` | Service time comparison |
| `Q4_comparison_breakdown.png` | Time breakdown pie charts |
| `Q4_comparison_improvement.png` | Improvement summary |

---

## Model Assumptions

1. **Single shift simulation** (8 hours = 480 min)
2. **Effective workers** = 40 × (8/9) due to 1-hour break
3. **FIFO queue discipline** (no priority)
4. **Actual arrival times** from order data (DeliveryHour, DeliveryMinute) - GIVEN DATA
5. **Triangular distribution** for service times (stochastic)
6. **No inventory constraints** (stockouts not modeled)
7. **Single item per trip** (no batching)

---

## Key Findings

### 1. Service Time Improvement
- Before FPA: **5.13 min/pick**
- After FPA: **2.27 min/pick**
- Reduction: **56%**

### 2. Capacity Improvement
- Theoretical LPMH (Before): 11.70 picks/picker/hour
- Theoretical LPMH (After): 26.42 picks/picker/hour
- **Capacity Gain: +126%**

### 3. Utilization Impact
- Same workload requires **56% less total work time**
- With 40 pickers: Utilization drops from 21% to 9%
- Workers have more idle time (can handle surge demand)

### 4. Root Cause Addressed
- **Before:** Search time = 2.21 min (69% of pick time)
- **After:** Search time = 0 (eliminated with fixed FPA locations)

### 5. Practical Implications
- Same workforce can handle **126% more picks**
- Or: Achieve same output with **fewer pickers** (cost savings)
- Or: Use freed capacity for **other tasks** (replenishment, etc.)

---

## Why Triangular Distribution?

Triangular distribution is used because:
1. **Easy to estimate** - only need min, mode (most likely), max
2. **Bounded** - unlike normal distribution, no extreme outliers
3. **Realistic** - captures variability in warehouse operations
4. **Common in simulation** - industry standard for activity times

### Parameters Used
| Activity | Min | Mode | Max | Rationale |
|----------|-----|------|-----|-----------|
| Walk Distance (Before) | 10m | 25m | 50m | Random storage variability |
| Search Time | 1.0 min | 2.21 min | 4.0 min | Based on Q1 time study |
| Check & Pick | 0.3 min | 0.4 min | 0.6 min | Standard warehouse time |
| Scan | 0.05 min | 0.083 min | 0.12 min | Barcode scanner variability |

---

## File Dependencies

```
Q4_SimPy_Simulation.py
├── Simio_OrderPickLines.csv  (input: 203,236 lines)
├── Simio_SKU_Params.csv      (input: 133 SKUs)
└── outputs/
    ├── Q4_simpy_sensitivity.csv
    └── Q4_simpy_*.png

Q4_Comparison_Simulation.py
├── Simio_OrderPickLines.csv  (input)
├── Simio_SKU_Params.csv      (input)
└── outputs/
    ├── Q4_comparison_results.csv
    └── Q4_comparison_*.png
```

---

## References

1. SimPy Documentation: https://simpy.readthedocs.io/
2. Bartholdi & Hackman - Warehouse & Distribution Science
3. Q1-Q3 Analysis Scripts in this project
4. activity.txt - Effective workers calculation
