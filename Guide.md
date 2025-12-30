# คู่มือการใช้งาน - FPA Design for Ford Mock Case

## ภาพรวมโปรเจค

โปรเจคนี้ออกแบบพื้นที่หยิบชิ้นส่วนที่มีความเคลื่อนไหวสูง (Fast Picking Area: FPA) สำหรับคลังชิ้นส่วนยานยนต์

---

## ลำดับการรันไฟล์

```
┌─────────────────────────────────────────────────────────────────┐
│  STEP 1: Freq.R                                                 │
│  สร้าง DataFreq.csv (ข้อมูลความถี่และ Viscosity)                  │
└─────────────────────────┬───────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│  STEP 2: Viscosity.R                                            │
│  ออกแบบ FPA ด้วย Fluid Model (คำถามข้อ 2)                        │
└─────────────────────────┬───────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│  STEP 3-6: สามารถรันขนานกันได้                                   │
│  - Q1_LinesPerManHour.R (คำถามข้อ 1)                            │
│  - Q3_Slotting.R (คำถามข้อ 3) *ต้องรัน Viscosity.R ก่อน          │
│  - SimioData_Export.R (สนับสนุน Q4) *ต้องรัน Q3 ก่อน             │
│  - Q5_COI_Comparison.R (โบนัส)                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## รายละเอียดแต่ละไฟล์

### 1. Freq.R
**วัตถุประสงค์:** คำนวณความถี่การหยิบและ Viscosity สำหรับแต่ละ SKU

**คำสั่งรัน:**
```r
source("Freq.R")
# หรือ
Rscript Freq.R
```

**Input:**
| ไฟล์ | คำอธิบาย |
|------|----------|
| `shipTrans.txt` | ข้อมูลการจัดส่งชิ้นส่วน |
| `itemMaster.txt` | ข้อมูล master ของชิ้นส่วน |

**Output:**
| ไฟล์ | คำอธิบาย | ใช้ทำอะไร |
|------|----------|----------|
| `DataFreq.csv` | PartNo, Volume, Freq, Viscosity | **Input สำหรับ Viscosity.R** |
| `SKU_frequency_analysis.csv` | ข้อมูลละเอียดพร้อม ABC Category | วิเคราะห์เพิ่มเติม |

---

### 2. Viscosity.R (คำถามข้อ 2)
**วัตถุประสงค์:** ออกแบบพื้นที่ FPA ด้วย Fluid Model จัดสรร SKU และ volume

**คำสั่งรัน:**
```r
source(" Viscosity.R")
# หรือ
Rscript " Viscosity.R"
```

**Input:**
| ไฟล์ | คำอธิบาย |
|------|----------|
| `DataFreq.csv` | จาก Freq.R |
| `itemMaster.txt` | ข้อมูลขนาดกล่อง |

**Output:**
| ไฟล์ | คำอธิบาย | ใช้ทำอะไร |
|------|----------|----------|
| `cabinet_allocation_detailed.csv` | การจัดวาง SKU ในแต่ละ Cabinet/Floor | **Input สำหรับ Q3_Slotting.R** |
| `all_120_floors_utilization.csv` | สถิติการใช้พื้นที่แต่ละชั้น | วิเคราะห์ utilization |

**พารามิเตอร์หลัก:**
- FPA Volume (V) = 36.0 m³
- Time saved per pick (s) = 2.0 นาที
- Replenishment time (Cr) = 15.0 นาที

---

### 3. Q1_LinesPerManHour.R (คำถามข้อ 1 - 15 คะแนน)
**วัตถุประสงค์:** วิเคราะห์ Lines per Man-Hour รายวันและรายเดือน เปรียบเทียบกับรูปที่ 7

**คำสั่งรัน:**
```r
source("Q1_LinesPerManHour.R")
```

**Input:**
| ไฟล์ | คำอธิบาย |
|------|----------|
| `shipTrans.txt` | ข้อมูลการจัดส่ง |
| `itemMaster.txt` | ข้อมูล master |
| `Shift.txt` | ข้อมูลกะทำงาน |

**Output:**
| ไฟล์ | คำอธิบาย | ใช้ทำอะไร |
|------|----------|----------|
| `Q1_daily_analysis.csv` | Lines/Man-Hour รายวัน | ตอบคำถามข้อ 1 |
| `Q1_monthly_comparison.csv` | เปรียบเทียบกับรูปที่ 7 | ตอบคำถามข้อ 1 |
| `Q1_daily_lines_per_manhour.png` | กราฟรายวัน | แนบในรายงาน |
| `Q1_monthly_comparison.png` | กราฟเปรียบเทียบรายเดือน | แนบในรายงาน |

---

### 4. Q3_Slotting.R (คำถามข้อ 3 - 25 คะแนน)
**วัตถุประสงค์:** จัดวางชิ้นส่วนใน FPA พร้อม Association Analysis

**คำสั่งรัน:**
```r
source("Q3_Slotting.R")
```

**⚠️ ต้องรัน Viscosity.R ก่อน**

**Input:**
| ไฟล์ | คำอธิบาย |
|------|----------|
| `cabinet_allocation_detailed.csv` | จาก Viscosity.R |
| `shipTrans.txt` | สำหรับ association analysis |
| `itemMaster.txt` | ข้อมูลชื่อชิ้นส่วน |

**Output:**
| ไฟล์ | คำอธิบาย | ใช้ทำอะไร |
|------|----------|----------|
| `Q3_slotting_result.csv` | ตำแหน่ง SKU พร้อมพิกัด X,Y | **Input สำหรับ SimioData_Export.R** |
| `Q3_association_pairs.csv` | คู่ SKU ที่เกี่ยวข้องกัน | วิเคราะห์ association |
| `Q3_fpa_layout.png` | กราฟ layout FPA | แนบในรายงาน |

**Association Methods:**
1. **Pattern Matching** - ค้นหาคู่ LH/RH, A/B variants
2. **Co-occurrence** - SKU ที่ถูกหยิบพร้อมกัน
3. **Statistical Correlation** - Spearman correlation ระหว่างความถี่

---

### 5. SimioData_Export.R (สนับสนุนคำถามข้อ 4)
**วัตถุประสงค์:** ส่งออกข้อมูลสำหรับสร้าง Simulation ใน Simio

**คำสั่งรัน:**
```r
source("SimioData_Export.R")
```

**⚠️ ต้องรัน Q3_Slotting.R ก่อน**

**Input:**
| ไฟล์ | คำอธิบาย |
|------|----------|
| `Q3_slotting_result.csv` | จาก Q3_Slotting.R |
| `shipTrans.txt` | ข้อมูล historical orders |

**Output:**
| ไฟล์ | คำอธิบาย | ใช้ใน Simio |
|------|----------|-------------|
| `Simio_SKU_FPA_Layout.csv` | พิกัด X,Y,Z ของแต่ละ SKU | สร้าง Entity locations |
| `Simio_Pick_Orders.csv` | ข้อมูล pick orders | สร้าง Source arrivals |
| `Simio_SKU_Inventory_Params.csv` | Min/Max ของแต่ละ SKU | ตั้งค่า inventory |
| `Simio_Activity_Times.csv` | เวลามาตรฐานกิจกรรม | ตั้งค่า processing times |
| `Simio_Hourly_Arrival_Distribution.csv` | การกระจายตัว orders | ตั้งค่า arrival rate |

**Simio Parameters:**
| พารามิเตอร์ | ค่า | หน่วย |
|-------------|-----|-------|
| Walking speed | 100 | m/min |
| Check + Pick | 0.4 | min/line |
| Pick per box | 0.1 | min/box |
| Normal replenishment | 15 | min |
| Emergency replenishment | 120 | min |
| Min inventory | floor(Max/2) | boxes |

---

### 6. Q5_COI_Comparison.R (โบนัส - 30 คะแนน)
**วัตถุประสงค์:** เปรียบเทียบ Fluid Model กับ COI Method

**คำสั่งรัน:**
```r
source("Q5_COI_Comparison.R")
```

**Input:**
| ไฟล์ | คำอธิบาย |
|------|----------|
| `shipTrans.txt` | ข้อมูลการจัดส่ง |
| `itemMaster.txt` | ข้อมูล master |

**Output:**
| ไฟล์ | คำอธิบาย | ใช้ทำอะไร |
|------|----------|----------|
| `Q5_FluidModel_SKUs.csv` | SKU ที่เลือกด้วย Fluid Model | เปรียบเทียบ |
| `Q5_COI_SKUs.csv` | SKU ที่เลือกด้วย COI | เปรียบเทียบ |
| `Q5_Comparison_Summary.csv` | ตารางเปรียบเทียบ | ตอบคำถามโบนัส |
| `Q5_volume_allocation_comparison.png` | กราฟเปรียบเทียบ volume | แนบในรายงาน |
| `Q5_freq_vs_coi.png` | กราฟ Freq vs COI | แนบในรายงาน |
| `Q5_benefit_distribution.png` | กราฟการกระจาย benefit | แนบในรายงาน |

---

## Quick Start Guide

### วิธีรันทั้งหมด (ตามลำดับ)

```r
# เปิด R หรือ RStudio ใน folder TermProject3

# Step 1: สร้าง DataFreq.csv
source("Freq.R")

# Step 2: ออกแบบ FPA (คำถามข้อ 2)
source(" Viscosity.R")

# Step 3: วิเคราะห์ Lines/Man-Hour (คำถามข้อ 1)
source("Q1_LinesPerManHour.R")

# Step 4: จัดวาง Slotting (คำถามข้อ 3)
source("Q3_Slotting.R")

# Step 5: Export สำหรับ Simio (คำถามข้อ 4)
source("SimioData_Export.R")

# Step 6: เปรียบเทียบ COI (โบนัส)
source("Q5_COI_Comparison.R")
```

---

## สรุปไฟล์ Output ตามคำถาม

| คำถาม | คะแนน | ไฟล์ Output หลัก |
|-------|-------|------------------|
| Q1 | 15 | `Q1_monthly_comparison.csv`, กราฟ PNG |
| Q2 | 20 | `cabinet_allocation_detailed.csv` |
| Q3 | 25 | `Q3_slotting_result.csv`, `Q3_association_pairs.csv` |
| Q4 | 35 | `Simio_*.csv` (5 ไฟล์) → **ใช้ใน Simio** |
| Bonus | 30 | `Q5_Comparison_Summary.csv`, กราฟ PNG |

---

## Troubleshooting

### Error: ไม่พบไฟล์ DataFreq.csv
```
→ รัน Freq.R ก่อน
```

### Error: ไม่พบไฟล์ cabinet_allocation_detailed.csv
```
→ รัน Freq.R แล้วตามด้วย Viscosity.R
```

### Error: ไม่พบไฟล์ Q3_slotting_result.csv
```
→ รัน Q3_Slotting.R ก่อนรัน SimioData_Export.R
```

### Warning: package 'ggplot2' not found
```r
install.packages("ggplot2")
install.packages("data.table")
```

---

## ผู้จัดทำ
สร้างโดย Claude Code สำหรับ Term Project 3
