# FPA Design for Ford Mock Case - Documentation Index

## Overview
This project designs a Fast Picking Area (FPA) for small automotive parts warehouse using Fluid Model optimization.

---

## Documentation Files

| File | Purpose | When to Use |
|------|---------|-------------|
| **README.md** | This file - documentation index | Start here |
| **Guide.md** | Quick reference for running R scripts | When running code |
| **dataguide.md** | Detailed data dictionary & algorithms | Understanding formulas |
| **plan.md** | Project plan & implementation steps | Project planning |

---

## File Descriptions

### 1. Guide.md (คู่มือการใช้งาน)
**Purpose:** Quick reference guide for running R scripts

**Contents:**
- Execution order flowchart
- Input/Output for each R script
- Quick start commands
- Troubleshooting common errors

**Use when:** You need to run the R scripts and want to know the correct order and dependencies.

---

### 2. dataguide.md (คู่มือข้อมูลและอัลกอริทึม)
**Purpose:** Comprehensive data dictionary and algorithm documentation

**Contents:**
- Physical constraints (cabinet layout, dimensions)
- **Cabinet Layout: 4 rows × 2 columns × 3 cabinets**
- Adjacency rules (back-to-back NOT adjacent)
- Fluid Model formulas with examples
- Slotting algorithm (Association → Frequency → Prefix)
- Output file column descriptions
- Simio export parameters

**Use when:** You need to understand:
- How formulas work (Viscosity, Volume Allocation, Benefit)
- What each column in output files means
- The physical cabinet layout and adjacency rules

---

### 3. plan.md (แผนการดำเนินงาน)
**Purpose:** Project implementation plan

**Location:** `~/.claude/plans/lucky-booping-duckling.md`

**Contents:**
- Question-by-question breakdown (Q1-Q5 + Bonus)
- Implementation steps for each question
- Cabinet layout diagram
- Expected results and outputs

**Use when:** You want to understand the overall project structure and approach.

---

## Quick Reference

### Cabinet Layout (4×2×3)
```
         Column 1              Column 2
        ___________    |      ___________
 Row 4: [19][20][21]   |      [22][23][24]
        ~~~~~~~ AISLE ~|~ AISLE ~~~~~~~
 Row 3: [13][14][15]   |      [16][17][18]
        ___________    |      ___________    <- BACK-TO-BACK
 Row 2: [7] [8] [9]    |      [10][11][12]
        ~~~~~~~ AISLE ~|~ AISLE ~~~~~~~
 Row 1: [1] [2] [3]    |      [4] [5] [6]
```

### Script Execution Order
```
Freq.R → Q2_FluidModel.R → Q3_Slotting.R → SimioData_Export.R
              ↓
      Q1_LinesPerManHour.R (independent)
      Q5_COI_Comparison.R (independent)
```

### Key Outputs by Question
| Question | Points | Main Output |
|----------|--------|-------------|
| Q1 | 15 | `Q1_monthly_comparison.csv` |
| Q2 | 20 | `Q2_FPA_Optimal_SKUs.csv` |
| Q3 | 25 | `Q3_slotting_result.csv` |
| Q4 | 35 | `Simio_*.csv` (for Simio simulation) |
| Bonus | 30 | `Q5_Comparison_Summary.csv` |

---

## Language Note
- Documentation is primarily in **Thai (ภาษาไทย)**
- Code comments are in English
- This README is bilingual for accessibility
