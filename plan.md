# FPA Design Solution Plan for Ford Mock Case

## Project Overview
Design a Fast Picking Area (FPA) for small automotive parts warehouse using data from:
- `shipTrans.txt` - Shipping transaction data (Sep 2011 - Aug 2012)
- `itemMaster.txt` - Item master data with dimensions
- `Activity.txt` - Activity time standards
- `Shift.txt` - Shift information
- `ford_mock_case.pdf` - Case study reference

## Data Structure
### shipTrans.txt columns:
- ShippingDay, yyyymm, DeliveryDay, ReceivingLocation, DeliveryTime
- DeliveryNo#, SupplierCode, Part No, BoxType, OrderQty, ScanQty, WMS MO SerialNo#

### itemMaster.txt columns:
- Skus, Part No, Part name, Box type, UnitLabel Qt
- ModuleSizeL, ModuleSizeV, ModuleSizeH (mm), Cub M (m³)

### FPA Physical Constraints:
- Standard shelf: 1.98m (W) × 0.68m (D) × 1.50m (H) with 5 levels at 0.3m each
- 24 cabinets × 5 floors = 120 storage positions
- FPA Volume = 36.0 m³ (after 74.25% efficiency)

---

## Question 1 (15 points): Lines Per Man-Hour Analysis

### Objective
Calculate daily lines per man-hour and compare with monthly data (Figure 7 in PDF)

### Formula
```
Lines per Man-Hour = Total Pick Lines / Total Man-Hours
```

### Implementation Steps
1. **Load and filter data** for small parts only (H < 1.5m, L or W < 0.68m)
2. **Calculate daily metrics:**
   - Count unique pick lines per day (each Part No in shipTrans is a line)
   - Use shift data: Morning shift (08:00-17:00 = 9 hrs regular + 2 hrs OT)
   - 80 workers for small parts picking
3. **Calculate monthly aggregates** to match Figure 7
4. **Exclude flood months** (Oct-Nov 2011) as per footnote

### Expected Output
- Daily lines per man-hour chart
- Monthly comparison with Figure 7 values (avg ~7.76 lines/man-hour)

---

## Question 2 (20 points): Fluid Model FPA Design

### Objective
Design FPA using Fluid Model to select optimal SKUs and allocate volumes

### Parameters Given
| Parameter | Value | Unit |
|-----------|-------|------|
| FPA Volume (V) | 36.0 | m³ |
| Time saved per FPA pick (s) | 2.0 | min/line |
| Replenishment time (Cr) | 15.0 | min/trip |

### Fluid Model Formulas (from Bartholdi & Hackman)

**Viscosity (η) for each SKU:**
```
η_i = f_i / √(D_i) = picks / √(flow)
Where:
- f_i = frequency (number of picks per year)
- D_i = flow (total volume demand per year = f_i × volume_per_pick)
```

**Optimal Volume Allocation:**
```
v_i* = V × √(D_i) / Σ√(D_j)  for all selected SKUs
Where:
- V = total FPA volume (36.0 m³)
- D_i = annual demand volume for SKU i
```

**Net Benefit per SKU:**
```
Benefit_i = s × f_i - Cr × (D_i / v_i*)
Where:
- s = time saved per pick = 2.0 min
- f_i = annual frequency (picks)
- Cr = replenishment time = 15 min
- D_i = annual demand volume
- v_i* = allocated FPA volume
```

### Implementation Steps
1. **Calculate for each SKU:**
   - Frequency (f_i) = count of pick transactions
   - Volume per pick (D_i/f_i) = CubM from itemMaster
   - Annual demand volume (D_i) = frequency × box volume

2. **Calculate Viscosity and rank SKUs**

3. **Iteratively select SKUs:**
   - Start with highest viscosity SKU
   - Add SKUs while total benefit increases
   - Recalculate volume allocation after each addition

4. **Output optimal SKU list with allocated volumes**

---

## Question 3 (25 points): Slotting Design

### Objective
Assign SKUs to specific shelf positions considering:
- Box dimensions
- Shelf dimensions (1.98m × 0.68m × 0.3m per level)
- Association patterns (co-picked items near each other)

### Implementation Steps

1. **Calculate position requirements per SKU:**
   ```
   Boxes_per_position = floor(shelf_height/box_height) × floor(shelf_depth/box_depth)
   Positions_needed = ceiling(allocated_volume / (boxes_per_position × box_volume))
   ```

2. **Association Analysis (from Main.R):**
   - Calculate co-occurrence pairs from pick transactions
   - Group frequently co-picked items together

3. **Slotting Algorithm:**
   - High-frequency items → middle floors (2, 3, 4) - ergonomic
   - Associated items → same cabinet or adjacent cabinets
   - Consider golden zone (waist-height) for fastest movers

4. **Output:**
   - Cabinet/Floor/Position assignment for each SKU
   - Visualization of FPA layout

---

## Question 4 (35 points): Simulation Model

### **USER WILL DO THIS IN SIMIO**

I will prepare data exports for Simio simulation:

### Data to Export for Simio:
1. **SKU_FPA_Layout.csv** - Position coordinates (X, Y) for each SKU in FPA
2. **Pick_Orders.csv** - Historical pick order data with timestamps
3. **SKU_Inventory_Params.csv** - Min/Max levels, box counts per SKU

### Simio Parameters Reference:
| Parameter | Value |
|-----------|-------|
| Walking speed | 100 m/min (1 min per 100m) |
| Check + pick time | 0.4 min/line + 0.1 min/box |
| Replenishment trigger | When inventory ≤ min |
| min | floor(max/2) |
| max | Total boxes fitting in allocated positions |
| Normal replenishment | 15 min |
| Emergency (stockout) | 120 min |

---

## Bonus Question (30 points): COI Comparison

### Objective
Compare Fluid Model with COI (Cube-Per-Order Index) approach

### COI Formula
```
COI_i = Cube_i / Orders_i = (Volume_per_box × boxes_per_order) / pick_frequency
```

### COI-based Allocation
- Lower COI → closer to I/O point (faster access)
- Allocate space proportional to demand, not based on optimization

### Comparison Analysis
1. Design FPA using COI method
2. Run same simulation
3. Compare:
   - Total picking time
   - Lines per man-hour
   - Space utilization
   - Stockout rates

---

## Data Flow (Fixed)

```
┌─────────────────────────────────────────────────────────────────┐
│                        INPUT FILES                              │
│  shipTrans.txt (57MB) + itemMaster.txt + Activity.txt + Shift.txt│
└────────────────────────────┬────────────────────────────────────┘
                             ↓
┌────────────────────────────────────────────────────────────────┐
│ Freq.R (NEEDS MAJOR FIX)                                       │
│ CURRENT BUG: assumes sku_freq exists but never creates it!     │
│ FIX:                                                           │
│   1. Load shipTrans.txt                                        │
│   2. Filter small parts (H<1.5m, L or W < 0.68m)               │
│   3. Calculate Freq = count of picks per PartNo                │
│   4. Merge with itemMaster for Volume (CubM)                   │
│   5. Calculate Viscosity = Freq / √(Flow)                      │
│      where Flow = Freq × CubM (annual demand volume)           │
│ OUTPUT: DataFreq.csv (PartNo, Volume, Freq, Viscosity)         │
└────────────────────────────┬───────────────────────────────────┘
                             ↓
┌────────────────────────────────────────────────────────────────┐
│ Viscosity.R (MINOR FIXES)                                      │
│ CURRENT: Fluid model formula is CORRECT ✓                      │
│ FIX:                                                           │
│   - Line 70: total_constant = 48.47 → 36.0 (FPA volume)        │
│   - Line 429: backfill_count referenced but never defined      │
│ OUTPUT: cabinet_allocation_detailed.csv                        │
└────────────────────────────┬───────────────────────────────────┘
                             ↓
┌────────────────────────────────────────────────────────────────┐
│ Q3_Slotting.R (NEW - with Association Analysis)                │
│ ASSOCIATION METHODS:                                           │
│   1. Pattern Matching: LH/RH, A/B, L/R in part names           │
│   2. Statistical Correlation: Pearson/Spearman between picks   │
│ OUTPUT: FPA_layout_with_positions.csv                          │
└────────────────────────────────────────────────────────────────┘
```

## Files to Modify/Create

### Output Language: Thai (ภาษาไทย)

### Existing Files to Fix:
1. **Freq.R** - แก้ไขให้โหลด shipTrans.txt และคำนวณ sku_freq + สร้าง DataFreq.csv
2. **Viscosity.R** - แก้ไข total_constant=36.0 และ backfill_count bug
3. **Main.R** - เพิ่ม pattern matching (LH/RH) และ correlation analysis

### New Files to Create:
1. **Q1_LinesPerManHour.R** - วิเคราะห์รายการต่อชั่วโมงแรงงาน (คำถามข้อ 1)
2. **Q3_Slotting.R** - จัดวางชิ้นส่วนด้วย association rules ทั้ง pattern + correlation (คำถามข้อ 3)
3. **SimioData_Export.R** - ส่งออกข้อมูลสำหรับ Simio (สนับสนุนคำถามข้อ 4)
4. **Q5_COI_Comparison.R** - เปรียบเทียบ COI method (คำถามโบนัส)

---

## Execution Order
1. **Q1** - Lines per man-hour (วิเคราะห์แยกจากข้ออื่น)
2. **Q2** - Fluid Model (เลือก SKUs สำหรับ FPA)
3. **Q3** - Slotting (ใช้ผลจาก Q2 + association analysis)
4. **Simio Export** - ส่งออกข้อมูลสำหรับ Simio (ผู้ใช้จะทำ simulation เอง)
5. **Bonus** - COI comparison (วิธีออกแบบทางเลือก)

---

## Key Issues in Existing Code

### Main.R Issues:
- ✓ Filters correctly for small parts
- ✗ Only does simple co-occurrence pairs
- ✗ Missing pattern matching (LH/RH, A/B variants)
- ✗ No statistical correlation analysis

### Freq.R Issues (CRITICAL):
- ✗ Line 3-4: Comment says "Assuming sku_freq is already calculated"
- ✗ Line 7: Uses `sku_freq` but **NEVER CREATES IT**
- ✗ Does NOT load shipTrans.txt
- ✗ Does NOT output DataFreq.csv (which Viscosity.R needs)

### Viscosity.R Issues:
- ✓ Fluid model formula is CORRECT (uses √f_i allocation)
- ✗ Line 70: `total_constant = 48.47` should be **36.0** (FPA volume from question)
- ✗ Line 429: `backfill_count` referenced but never defined
- ✗ Line 2: Needs `DataFreq.csv` which doesn't exist

## Current Code Formula (CORRECT)

**Viscosity.R Lines 80-89:**
```r
# Volume Allocation: v_i* = V × √(f_i) / Σ√(f_j)
sqrt_flows <- sqrt(subset_df$Freq)
fact <- sqrt_flows[i] / sum(sqrt_flows)
assigned_volumes[i] <- total_constant * fact

# Benefit: B_i = s × f_i - Cr × (D_i / v_i*)
benefits[i] <- s_constant * Freq[i] - Cr_constant * (Volume[i] / assigned_volumes[i])
```

This matches Bartholdi & Hackman Fluid Model formula ✓
