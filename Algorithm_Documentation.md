# Algorithm and Calculation Documentation
## FPA (Fast Picking Area) Design Project

This document explains all algorithms and calculations used in Q1-Q5.

---

## Table of Contents
1. [Q1: Lines Per Man-Hour](#q1-lines-per-man-hour)
2. [Q2: Fluid Model FPA Design](#q2-fluid-model-fpa-design)
3. [Q3: Slotting Design](#q3-slotting-design)
4. [Q4: Simio Data Export](#q4-simio-data-export)
5. [Q5: COI Comparison](#q5-coi-comparison)
6. [Data Preprocessing (Freq.R)](#data-preprocessing-freqr)

---

## Q1: Lines Per Man-Hour

### Objective
Calculate the picking productivity (lines per man-hour) for small parts warehouse operations.

### Algorithm

#### Step 1: Filter Small Parts
```
Filter Criteria:
- Height < 1.5m AND (Length < 0.68m OR Width < 0.68m)

This selects SKUs that can fit in the FPA cabinet positions.
```

#### Step 2: Calculate Man-Hours per Day

**Input Data Analysis:**
```
From shipTrans.txt DeliveryTime column:
- Morning shift (08:00-16:59): 293,784 lines (~50%)
- Evening shift (23:00-07:59): 290,166 lines (~50%)

Conclusion: Picks are evenly distributed across 2 shifts
```

**Shift Structure (from Shift.txt):**
```
+------------------+-------------+----------+---------+
| Shift            | Time        | Hours    | Break   |
+------------------+-------------+----------+---------+
| Morning Regular  | 08:00-17:00 | 9 hrs    | 1 hr    |
| Morning OT       | 17:00-19:00 | 2 hrs    | -       |
| Evening Regular  | 23:00-08:00 | 9 hrs    | 1 hr    |
+------------------+-------------+----------+---------+
```

**Man-Hours Calculation:**
```
Total workers = 80
Number of shifts = 2 (Morning + Evening)
Workers per shift = 80 / 2 = 40

Effective hours per worker = Shift hours - Break
                           = 9 - 1 = 8 hours

Man-hours per shift = 40 workers × 8 hours = 320 hours
Total man-hours per day = 320 × 2 shifts = 640 hours
```

#### Step 3: Calculate LPMH

**Daily Calculation:**
```
Lines Per Man-Hour (daily) = Total Pick Lines / Man-Hours
                           = Total Lines / 640

Working Day Filter: Days with >= 500 lines are considered working days
```

**Monthly Aggregation:**
```
Monthly LPMH = Sum(Daily Lines for working days) / Sum(Daily Man-Hours)
```

### Output
- **Average LPMH (excluding flood months):** 2.19 lines/man-hour
- **Average LPMH (all months):** 2.11 lines/man-hour

---

## Q2: Fluid Model FPA Design

### Objective
Select optimal SKUs for FPA using the Fluid Model (Bartholdi & Hackman) to maximize time savings.

### Theory: Fluid Model

The Fluid Model treats inventory as a continuous fluid rather than discrete units. Key insight: **SKUs with high frequency relative to their volume (high viscosity) should be in FPA.**

### Algorithm

#### Step 1: Calculate Flow (D_i)

**Definition:** Annual demand volume for SKU i

```
D_i = TotalQty_i × (CubM_i / UnitLabelQt_i)

Where:
- TotalQty_i = Total pieces picked per year (sum of ScanQty)
- CubM_i = Volume per box (m³)
- UnitLabelQt_i = Pieces per box

Note: ScanQty is in PIECES, not boxes!
Volume per piece = CubM / UnitLabelQt
D_i = Total pieces × Volume per piece
```

**Example:**
```
SKU: D65133047B
- TotalQty = 184,536 pieces/year
- CubM = 0.00576 m³/box
- UnitLabelQt = 1 piece/box
- D_i = 184,536 × (0.00576 / 1) = 1,063.0 m³/year
```

#### Step 2: Calculate Viscosity (η_i)

**Definition:** Ratio of frequency to square root of flow

```
η_i = f_i / √(D_i)

Where:
- f_i = Frequency (number of picks per year)
- D_i = Flow (demand volume per year)

High viscosity = High frequency relative to volume = Good FPA candidate
```

**Example:**
```
SKU: D65133047B
- f_i = 9,225 picks/year
- D_i = 1,063.0 m³/year
- η_i = 9,225 / √1,063 = 9,225 / 32.6 = 283
```

#### Step 3: Rank SKUs by Viscosity

```
Sort all SKUs by Viscosity in descending order
Highest viscosity SKUs are best candidates for FPA
```

#### Step 4: Calculate Optimal Volume Allocation

**For n selected SKUs:**
```
v_i* = V × √(D_i) / Σ√(D_j)  for j = 1 to n

Where:
- v_i* = Optimal allocated volume for SKU i
- V = Total FPA volume = 36.0 m³
- The allocation is proportional to √(D_i), not D_i
```

**Why √(D) instead of D?**
```
This is the key insight of the Fluid Model:
- If we allocate proportional to D, high-volume SKUs get too much space
- √(D) balances between frequency and volume needs
- This minimizes total replenishment trips
```

#### Step 5: Calculate Benefit

**Benefit Formula:**
```
B_i = s × f_i - Cr × (D_i / v_i*)

Where:
- B_i = Net benefit for SKU i (minutes/year)
- s = Time saved per pick = 2.0 min
- f_i = Annual frequency (picks/year)
- Cr = Replenishment time = 15.0 min/trip
- D_i / v_i* = Replenishment trips per year

Components:
- Saving = s × f_i (time saved from picking at FPA vs reserve)
- Cost = Cr × (D_i / v_i*) (time spent replenishing)
```

**Example:**
```
SKU: D65133047B
- f_i = 9,225 picks/year
- D_i = 1,063.0 m³/year
- v_i* = 2.5 m³ (allocated)

Saving = 2.0 × 9,225 = 18,450 min/year
Replenish trips = 1,063.0 / 2.5 = 425 trips/year
Cost = 15.0 × 425 = 6,375 min/year

B_i = 18,450 - 6,375 = 12,075 min/year
```

#### Step 6: Iterative Selection

```
Algorithm: Find optimal number of SKUs

1. Sort SKUs by Viscosity (descending)
2. For n = 1 to N (all available SKUs):
   a. Select top n SKUs
   b. Calculate volume allocation for these n SKUs
   c. Calculate total benefit = Σ B_i
3. Find n* where Total Benefit is maximized
4. Return top n* SKUs
```

**Why does benefit eventually decrease?**
```
As we add more SKUs:
- Each new SKU has lower viscosity
- Volume allocation per SKU decreases
- Replenishment trips increase
- Eventually, new SKUs have negative benefit
- Total benefit peaks and then decreases
```

### Parameters
| Parameter | Symbol | Value | Description |
|-----------|--------|-------|-------------|
| FPA Volume | V | 36.0 m³ | Total storage capacity |
| Time Saved per Pick | s | 2.0 min | Saving vs picking from reserve |
| Replenishment Time | Cr | 15.0 min | Time per replenishment trip |

### Output
- **Optimal SKUs:** 154
- **Maximum Benefit:** 274,590 min/year (4,577 hours/year)

---

## Q3: Slotting Design

### Objective
Assign SKUs to physical positions (Cabinet × Floor) in the FPA, considering ergonomics and associations.

### Physical Layout

```
         Column 1              Column 2
        ___________    |      ___________
 Row 4: [19][20][21]   |      [22][23][24]   <- Top
                       |
        ~~~~~~~ AISLE ~|~ AISLE ~~~~~~~
        ___________    |      ___________
 Row 3: [13][14][15]   |      [16][17][18]
        ___________    |      ___________    <- BACK-TO-BACK
 Row 2: [7] [8] [9]    |      [10][11][12]
                       |
        ~~~~~~~ AISLE ~|~ AISLE ~~~~~~~
        ___________    |      ___________
 Row 1: [1] [2] [3]    |      [4] [5] [6]    <- Bottom (Start)

- 24 Cabinets × 5 Floors = 120 Positions
- Each position: 1.98m (W) × 0.68m (D) × 0.30m (H)
- Position width can be subdivided among multiple SKUs
```

### Algorithm

#### Step 1: Load SKUs from DataFreq.csv

```
Q3 is INDEPENDENT from Q2:
- Loads all SKUs from DataFreq.csv (not Q2_FPA_Optimal_SKUs.csv)
- Selects by Viscosity until all 120 positions are filled
- This allows different cabinet space allocation than Q2's 36 m³
```

#### Step 2: Calculate Width Needed per SKU

```
Each SKU gets minimum 1 box width (not allocated volume from Q2)

WidthNeeded = BoxWidth_m  (from itemMaster)

This ensures:
- Every SKU has at least 1 column of boxes
- No fractional box widths
- Simple bin-packing problem
```

#### Step 3: Association Analysis

**Purpose:** Items often picked together should be placed nearby

**Method 1: Pattern Matching (LH/RH, A/B)**
```
Detect part number patterns:
- LH ↔ RH (Left/Right hand variants)
- A ↔ B (Size variants)
- L ↔ R (Position variants)

Score: 100 points per matching pair
```

**Method 2: Co-occurrence Analysis**
```
1. Create baskets: (ShippingDay, DeliveryNo#) combinations
2. For each basket with 2-30 items:
   - Generate all pairs of items
   - Count frequency of each pair
3. Normalize: CoocScore = (Count / MaxCount) × 50

Score: 0-50 points based on co-occurrence frequency
```

**Method 3: Association Groups**
```
1. Combine pattern and co-occurrence scores
2. If TotalScore >= 30, items should be placed together
3. Build connected components (BFS/DFS)
4. Assign group IDs to related items
```

#### Step 4: Ergonomic Floor Priority

```
Floor Priority: 3 → 2 → 4 → 1 → 5

Floor   Score   Description
  3     100     GOLDEN ZONE (waist height, no bending)
  2      90     Good (slight bending)
  4      90     Good (slight reaching)
  1      60     Lower (heavy bending)
  5      60     Upper (heavy reaching)
```

**Why use Frequency for floor assignment (not Viscosity)?**
```
Viscosity considers volume, but for ergonomics:
- If SKU is picked 10,000 times → worker bends/reaches 10,000 times
- High-frequency SKUs should be at comfortable heights
- Frequency directly correlates with physical strain
```

#### Step 5: Bin Packing (First Fit Decreasing with Association)

```
Algorithm:

1. Sort SKUs by:
   - Association groups first (items picked together)
   - Then by Frequency (ergonomic priority)

2. For each SKU:
   a. PRIORITY 1: If associated items already placed:
      - Try same position first
      - Then try adjacent cabinets (using layout rules)

   b. PRIORITY 2: If same-prefix items already placed:
      - Try same cabinet or adjacent cabinets

   c. PRIORITY 3: Standard placement:
      - Follow floor priority (3 → 2 → 4 → 1 → 5)
      - First cabinet with enough remaining width

3. Update position's remaining width
4. Stop when no position can fit the next SKU
```

**Adjacency Rules:**
```
Cabinet A and B are adjacent if:
- Same row AND same column AND |position_in_row| = 1

NOT adjacent:
- Row 2-3 back-to-back (can't walk through)
- Different columns (aisle in between)
```

#### Step 6: Track Sub-positions

```
For multi-SKU positions:
- SubPosStart_m: Where this SKU starts within position
- SubPosEnd_m: Where this SKU ends

Example: Position C01F3 (width = 1.98m)
  SKU A: SubPos 0.00 - 0.56m (uses 0.56m)
  SKU B: SubPos 0.56 - 1.12m (uses 0.56m)
  SKU C: SubPos 1.12 - 1.52m (uses 0.40m)
  Remaining: 0.46m
```

### Output
- **SKUs Assigned:** 669
- **Positions Used:** 120 (all filled)
- **Average Width Utilization:** ~94%

---

## Q4: Simio Data Export

### Objective
Export slotting results in format suitable for Simio simulation.

### Algorithm

#### Step 1: Calculate 3D Coordinates

```
For each assigned SKU:

X coordinate:
  X = (CabCol - 1) × (3 × cabinet_spacing + aisle_gap) +
      (CabPosInRow - 1) × cabinet_spacing +
      (SubPosStart + SubPosEnd) / 2

Y coordinate (with aisle gaps):
  Y = (CabRow - 1) × row_height +
      aisle_gap if CabRow >= 2 +
      aisle_gap if CabRow >= 4 +
      Floor × floor_height

Z coordinate:
  Z = (Floor - 1) × 0.30m
```

#### Step 2: Calculate Distance from I/O Point

```
I/O Point: Between Cabinet 3 and 4 (center of Aisle 1)

Distance = √(X² + Y²)

Where X, Y are from start position to SKU position
```

#### Step 3: Export Pick Orders

```
From shipTrans, filter FPA SKUs:
- OrderID = unique identifier
- ShippingDay, DeliveryTime
- PartNo, ScanQty
- Map to FPA position coordinates
```

#### Step 4: Export Inventory Parameters

```
For each SKU:
- MaxBoxes = Allocated boxes (based on width)
- MinBoxes = 20% of Max (reorder point)
- SafetyStock = 10% of Max
- DailyAvgPicks = Frequency / 247 working days
```

### Output Files
1. `Simio_SKU_FPA_Layout.csv` - SKU positions with coordinates
2. `Simio_Pick_Orders.csv` - Historical pick data
3. `Simio_SKU_Inventory_Params.csv` - Inventory parameters
4. `Simio_Activity_Times.csv` - Time standards

---

## Q5: COI Comparison

### Objective
Compare Fluid Model with traditional COI (Cube-per-Order Index) method.

### COI Method

**Definition:**
```
COI_i = D_i / f_i = Volume per pick

Where:
- D_i = Annual demand volume (m³/year)
- f_i = Annual frequency (picks/year)

Low COI = Small volume per pick = Should be near I/O point
```

**Volume Allocation (COI method):**
```
v_i = V × D_i / ΣD_j  (proportional to demand volume)

This differs from Fluid Model's √(D) allocation
```

### Algorithm

#### Step 1: Calculate COI for All SKUs

```
For each SKU:
  COI = Volume / Frequency

Sort by COI ascending (lowest COI = highest priority)
```

#### Step 2: Select Same Number of SKUs as Fluid Model

```
n = Number of SKUs selected by Fluid Model (e.g., 154)
Select top n SKUs by lowest COI
```

#### Step 3: Calculate Volume Allocation (COI method)

```
v_i = V × D_i / ΣD_j

Note: COI uses proportional allocation (D), not √(D)
```

#### Step 4: Calculate Benefit Using Same Formula

```
B_i = s × f_i - Cr × (D_i / v_i)

Same formula, but different:
- SKU selection (COI vs Viscosity)
- Volume allocation (D vs √D)
```

#### Step 5: Compare Results

```
Metrics:
1. Total Benefit (min/year)
2. SKU overlap between methods
3. Volume allocation efficiency
```

### Key Differences

| Aspect | Fluid Model | COI Method |
|--------|-------------|------------|
| Selection Criterion | Viscosity (f/√D) | COI (D/f) |
| Volume Allocation | v* ∝ √D | v ∝ D |
| Considers Replenishment | Yes (optimized) | No |
| Trade-off Optimization | Yes (s vs Cr) | No |

### Why Fluid Model is Better

```
1. √(D) allocation is mathematically optimal for minimizing
   replenishment while maximizing pick savings

2. Viscosity captures the RIGHT trade-off:
   - High frequency = more pick savings
   - Low volume = fewer replenishment trips

3. COI overweights high-volume SKUs:
   - Gets too much space for slow movers
   - Causes more replenishment for fast movers
```

### Output
- **Fluid Model Benefit:** ~274,590 min/year
- **COI Benefit:** ~109,908 min/year
- **Improvement:** ~150% better with Fluid Model

---

## Data Preprocessing (Freq.R)

### Objective
Calculate Frequency and Viscosity for all SKUs, with data cleaning.

### Algorithm

#### Step 1: Load and Clean Data

```
shipTrans:
- Clean column names (remove spaces, dots)
- Convert dates: ShippingDay → Date format

itemMaster:
- Clean column names
- Convert dimensions to meters (mm → m)
- Calculate box volume
```

#### Step 2: Filter Data

**Remove Flood Period:**
```
Flood months: October 2011 (201110), November 2011 (201111)

Reason:
- Unusual operating conditions
- Not representative of normal operations
- Would skew frequency calculations
```

**Remove Sundays:**
```
Filter: weekday(ShippingDay) != Sunday

Reason:
- Non-working days with minimal activity
- Would artificially lower daily averages
```

#### Step 3: Filter Small Parts

```
Criteria: H < 1.5m AND (L < 0.68m OR W < 0.68m)

Only these SKUs can fit in FPA positions
```

#### Step 4: Calculate Frequency

```
For each SKU:
  Freq = COUNT(rows in shipTrans)
  TotalQty = SUM(ScanQty)  -- pieces, not boxes!
```

#### Step 5: Calculate Flow (Volume)

```
Volume_i = TotalQty_i × (CubM_i / UnitLabelQt_i)

Where:
- TotalQty = total pieces picked
- CubM = volume per box
- UnitLabelQt = pieces per box
- CubM / UnitLabelQt = volume per piece
```

#### Step 6: Calculate Viscosity

```
Viscosity_i = Freq_i / √(Volume_i)
```

### Output
- `DataFreq.csv`: All small-part SKUs with Freq, Volume, Viscosity

---

## Summary of Key Formulas

### Fluid Model (Q2)
```
Flow:       D_i = TotalQty × (CubM / UnitLabelQt)
Viscosity:  η_i = f_i / √(D_i)
Allocation: v_i* = V × √(D_i) / Σ√(D_j)
Benefit:    B_i = s × f_i - Cr × (D_i / v_i*)
```

### COI Method (Q5)
```
COI:        COI_i = D_i / f_i
Allocation: v_i = V × D_i / ΣD_j
```

### Man-Hours (Q1)
```
Workers per shift = Total workers / Number of shifts = 80/2 = 40
Effective hours = Shift hours - Break = 9 - 1 = 8
Man-hours/shift = 40 × 8 = 320
Man-hours/day = 320 × 2 = 640
LPMH = Total Lines / 640
```

---

## Script Execution Order

```bash
# 1. Preprocess data and calculate Viscosity
Rscript Freq.R

# 2. Calculate Lines per Man-Hour (independent)
Rscript Q1_LinesPerManHour.R

# 3. Run Fluid Model to find optimal SKUs
Rscript Q2_FluidModel.R

# 4. Assign SKUs to positions (independent from Q2)
Rscript Q3_Slotting.R

# 5. Export for Simio simulation
Rscript SimioData_Export.R

# 6. Compare with COI method
Rscript Q5_COI_Comparison.R
```

---

## References

1. Bartholdi, J.J. and Hackman, S.T. (2014). *Warehouse & Distribution Science*. Release 0.96. The Supply Chain and Logistics Institute, Georgia Tech.

2. Fluid Model for Forward-Reserve Allocation: Chapter 4, Section 4.4.

3. Cube-per-Order Index (COI): Traditional method for slotting based on volume-to-frequency ratio.
