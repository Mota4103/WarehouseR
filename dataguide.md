# คู่มือการวิเคราะห์ FPA (Fast Picking Area) - Ford Mock Case

## สารบัญ
1. [ภาพรวมโครงการ](#1-ภาพรวมโครงการ)
   - 1.1 [วัตถุประสงค์](#11-วัตถุประสงค์)
   - 1.2 [ข้อจำกัดทางกายภาพ](#12-ข้อจำกัดทางกายภาพ)
   - 1.3 [Cabinet Layout](#13-cabinet-layout-4-แถว--2-คอลัมน์--3-ตู้)
   - 1.4 [พารามิเตอร์ Fluid Model](#14-พารามิเตอร์-fluid-model)
   - 1.5 [ขนาดทางเดิน (Aisle Dimensions)](#15-ขนาดทางเดิน-aisle-dimensions-และพารามิเตอร์การเดิน)
   - 1.6 [จุดเริ่มต้นการหยิบ (Start Position 3-4)](#16-จุดเริ่มต้นการหยิบ-start-position)
   - 1.7 [กลยุทธ์การจัดวาง (Slotting Strategy)](#17-กลยุทธ์การจัดวาง-slotting-strategy-ตามจุดเริ่มต้น-3-4)
2. [ข้อมูลนำเข้า (Input Data)](#2-ข้อมูลนำเข้า-input-data)
3. [คำถามข้อ 1: Lines Per Man-Hour](#3-คำถามข้อ-1-lines-per-man-hour)
4. [คำถามข้อ 2: Fluid Model FPA Design](#4-คำถามข้อ-2-fluid-model-fpa-design)
5. [คำถามข้อ 3: Slotting Design](#5-คำถามข้อ-3-slotting-design)
6. [คำถามข้อ 4: Simio Simulation](#6-คำถามข้อ-4-simio-simulation)
7. [คำถามโบนัส: COI Comparison](#7-คำถามโบนัส-coi-comparison)
8. [ความสัมพันธ์ระหว่างไฟล์](#8-ความสัมพันธ์ระหว่างไฟล์)

---

## 1. ภาพรวมโครงการ

### 1.1 วัตถุประสงค์
ออกแบบพื้นที่หยิบสินค้าเร็ว (FPA) สำหรับชิ้นส่วนยานยนต์ขนาดเล็กโดยใช้ Fluid Model

### 1.2 ข้อจำกัดทางกายภาพ
| พารามิเตอร์ | ค่า | หน่วย |
|------------|-----|-------|
| จำนวนตู้ (Cabinets) | 24 | ตู้ |
| จำนวนชั้นต่อตู้ (Floors) | 5 | ชั้น |
| ตำแหน่งทั้งหมด | 120 | ตำแหน่ง |
| ขนาดตำแหน่ง | 1.98 × 0.68 × 0.30 | เมตร |
| ปริมาตรต่อตำแหน่ง | 0.4039 | m³ |
| ปริมาตร FPA รวม (Cabinet Volume) | 48.47 | m³ |
| ความกว้าง FPA รวม | 237.6 | m |
| ปริมาตร FPA สำหรับ Fluid Model (V) | 36.0 | m³ |

### 1.3 Cabinet Layout (4 แถว × 2 คอลัมน์ × 3 ตู้)

**ผังการจัดวางตู้:**
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
 Row 1: [1] [2] [3]    |      [4] [5] [6]    <- Bottom (start)
```

**กฎการพิจารณาว่าตู้อยู่ติดกัน (Adjacency):**
- ✅ ตู้ในแถวเดียวกัน, คอลัมน์เดียวกัน, ตำแหน่งติดกัน (เช่น 1↔2, 2↔3, 7↔8)
- ❌ ตู้ที่อยู่หลังชนหลัง (Row 2-3) **ไม่ถือว่าอยู่ติดกัน** เพราะเดินผ่านไม่ได้
- ❌ ตู้คนละคอลัมน์ **ไม่ถือว่าอยู่ติดกัน** เพราะมีทางเดิน (aisle) คั่น

**ตัวอย่าง Adjacency:**
| ตู้ | ตู้ที่อยู่ติดกัน |
|-----|-----------------|
| 1 | 2 |
| 2 | 1, 3 |
| 3 | 2 |
| 7 | 8 |
| 13 | 14 |
| 8 | 7, 9 |
| 9 | 8 (ไม่ใช่ 10, คนละคอลัมน์) |
| 15 | 14 (ไม่ใช่ 9, หลังชนหลัง) |

### 1.4 พารามิเตอร์ Fluid Model
| พารามิเตอร์ | สัญลักษณ์ | ค่า | ความหมาย |
|------------|----------|-----|----------|
| เวลาประหยัดต่อการหยิบ | s | 2.0 นาที/line | เวลาที่ประหยัดได้เมื่อหยิบจาก FPA แทน reserve |
| เวลาเติมสินค้า | Cr | 15.0 นาที/trip | เวลาในการเติมสินค้าเข้า FPA |
| ปริมาตร FPA | V | 36.0 m³ | พื้นที่จัดเก็บทั้งหมด |

### 1.5 ขนาดทางเดิน (Aisle Dimensions) และพารามิเตอร์การเดิน

#### ขนาดทางเดินจาก PDF Figure 10:
| พารามิเตอร์ | ค่า | หน่วย | คำอธิบาย |
|------------|-----|-------|----------|
| ความกว้างตู้ (Cabinet Width) | 1.98 | m | ความกว้างของตู้แต่ละตู้ |
| ความลึกตำแหน่ง (Position Depth) | 0.68 | m | ความลึกของชั้นจัดเก็บ |
| ความสูงชั้น (Floor Height) | 0.30 | m | ความสูงของแต่ละชั้น (5 ชั้น = 1.50m) |
| ความยาว Aisle ต่อฝั่ง | 5.94 | m | 3 ตู้ × 1.98m = 5.94m |
| ความยาว Aisle รวม | 11.88 | m | 6 ตู้ต่อแถว × 1.98m |
| ความกว้าง Aisle | ~2.0 | m | ระยะทางเดินระหว่างแถว |

#### พารามิเตอร์การเดิน (Walking Parameters):
| Activity | เวลา | หน่วย | ความเร็ว |
|----------|------|-------|----------|
| Walking | 1.0 | min/100m | 1.67 m/sec |
| Check_and_Pick | 0.4 | min/line | - |
| Pick_per_Box | 0.1 | min/box | - |
| Replenishment_Normal | 15.0 | min/trip | - |
| Replenishment_Emergency | 120.0 | min/trip | - |

**การคำนวณความเร็วเดิน:**
```
Walking Speed = 100m / 1 min = 100 m/min = 1.67 m/sec
```

### 1.6 จุดเริ่มต้นการหยิบ (Start Position)

#### ตำแหน่งเริ่มต้น: ระหว่างตู้ 3 และ 4 (กึ่งกลาง Aisle 1)

**ผังแสดงจุดเริ่มต้น:**
```
           Column 1           |    Column 2
         (X: negative)        |    (X: positive)
                              |
  Row 4:  [19][20][21]        |    [22][23][24]     <- Aisle 2 top
          ~~~~~~~~ AISLE 2 ~~~~~~~~
  Row 3:  [13][14][15]        |    [16][17][18]     ↑ back-to-back
  Row 2:  [7] [8] [9]         |    [10][11][12]     ↓ with Row 3
          ~~~~~~~~ AISLE 1 ~~~~~~~~
  Row 1:  [1] [2] [3]    ★    |    ★   [4] [5] [6]  <- Start Position (3↔4)
                         START POSITION
```

**เหตุผลในการเลือกจุดเริ่มต้นที่ 3-4:**
- อยู่กึ่งกลางของ Aisle 1 ทำให้ระยะทางเฉลี่ยไปทุกตู้สั้นที่สุด
- ใกล้กับ Golden Zone (ตู้ 3, 4 ชั้น 3)
- ลดเวลาเดินเฉลี่ย ~50% เมื่อเทียบกับจุดเริ่มต้นที่มุม

#### ระยะทางจากจุดเริ่มต้น (Distance from Start Position 3-4):

| ตู้ (Cabinet) | แถว (Row) | คอลัมน์ | ระยะทาง X (m) | ระยะทาง Y (m) | ระยะทางรวม (m) | เวลาเดิน (sec) |
|---------------|-----------|---------|---------------|---------------|----------------|----------------|
| 3 | 1 | 1 | 0.99 | 0.68 | **1.20** | 0.72 |
| 4 | 1 | 2 | 0.99 | 0.68 | **1.20** | 0.72 |
| 2 | 1 | 1 | 2.97 | 0.68 | **3.05** | 1.83 |
| 5 | 1 | 2 | 2.97 | 0.68 | **3.05** | 1.83 |
| 1 | 1 | 1 | 4.95 | 0.68 | **4.99** | 2.99 |
| 6 | 1 | 2 | 4.95 | 0.68 | **4.99** | 2.99 |
| 8 | 2 | 1 | 0.99 | 2.86 | **3.03** | 1.82 |
| 10 | 2 | 2 | 0.99 | 2.86 | **3.03** | 1.82 |
| 9 | 2 | 1 | 2.97 | 2.86 | **4.12** | 2.47 |
| 11 | 2 | 2 | 2.97 | 2.86 | **4.12** | 2.47 |
| 7 | 2 | 1 | 4.95 | 2.86 | **5.72** | 3.43 |
| 12 | 2 | 2 | 4.95 | 2.86 | **5.72** | 3.43 |

**หมายเหตุ:** Y distance สำหรับ Row 2 = 0.68m (depth) + 2.0m (aisle) + 0.68m/2 = 2.86m

### 1.7 กลยุทธ์การจัดวาง (Slotting Strategy) ตามจุดเริ่มต้น 3-4

#### Priority Zones:

| Zone | ชื่อ | ตู้ | ชั้น | ระยะทาง | เหมาะสำหรับ |
|------|------|-----|------|---------|-------------|
| **A** | Golden Zone | 3, 4 | 3 | ~1.2m | SKU ที่มี Frequency สูงสุด (Top 10) |
| **B** | Prime Zone | 3, 4 | 2, 4 | ~1.2m | SKU Rank 11-20 |
| **C** | Good Zone | 2, 5 | 3 | ~3.0m | SKU Rank 21-40 |
| **D** | Standard Zone | 2, 5, 8, 10 | 2, 4 | ~3.0m | SKU Rank 41-80 |
| **E** | Far Zone | 1, 6, 7, 9, 11, 12 | All | 5-10m | SKU ความถี่ต่ำ |

#### การจัดวาง SKU ตาม Frequency (แนะนำ):

| Frequency Rank | PartNo | Frequency/year | Cabinet แนะนำ | Floor | Zone |
|----------------|--------|----------------|---------------|-------|------|
| 1 | D65133047B | 9,894 | **3** | 3 | A |
| 2 | DR6134011B | 8,662 | **4** | 3 | A |
| 3 | D65239060H | 7,874 | **3** | 2 | B |
| 4 | D651437A0D | 6,330 | **4** | 2 | B |
| 5 | DN2439070 | 5,656 | **3** | 4 | B |
| 6 | D37437790A | 5,540 | **4** | 4 | B |
| 7 | DN3237790 | 4,676 | **2** | 3 | C |
| 8 | DN3266120B | 4,526 | **5** | 3 | C |
| 9 | ZJ2113390 | 4,436 | **2** | 4 | C |
| 10 | D65357540B02 | 3,746 | **5** | 4 | C |

#### ผลประโยชน์ที่คาดว่าจะได้รับ:

| Metric | ก่อนปรับ | หลังปรับ (Start 3-4) | ปรับปรุง |
|--------|----------|----------------------|----------|
| ระยะทางเดินเฉลี่ย | ~10m | ~4-5m | **-50%** |
| เวลาเดินเฉลี่ย | ~6 sec | ~3 sec | **-50%** |
| เวลาประหยัดต่อปี | - | ~4,000 min | - |

---

## 2. ข้อมูลนำเข้า (Input Data)

### 2.1 shipTrans.txt - ข้อมูลการจัดส่ง
| คอลัมน์ | ประเภท | ตัวอย่าง | คำอธิบาย |
|--------|--------|---------|----------|
| ShippingDay | Integer | 20110901 | วันที่จัดส่ง (YYYYMMDD) |
| yyyymm | Integer | 201109 | เดือนปี |
| DeliveryDay | Integer | 20110901 | วันที่ส่งมอบ |
| ReceivingLocation | String | "ASSY-1" | สถานที่รับสินค้า |
| DeliveryTime | Integer | 830 | เวลาส่งมอบ (HHMM) |
| DeliveryNo# | Integer | 12345 | เลขที่ใบส่งของ |
| SupplierCode | String | "SUP001" | รหัสผู้จัดส่ง |
| Part No | String | "D65133047B" | รหัสชิ้นส่วน |
| BoxType | String | "A" | ประเภทกล่อง |
| OrderQty | Integer | 10 | จำนวนสั่ง |
| ScanQty | Integer | 10 | จำนวนสแกน |

**การใช้งาน:**
- นับจำนวน pick lines ต่อวัน (Q1)
- คำนวณความถี่การหยิบแต่ละ SKU (Q2)
- วิเคราะห์ co-occurrence สำหรับ association (Q3)

### 2.2 itemMaster.txt - ข้อมูลชิ้นส่วน
| คอลัมน์ | ประเภท | ตัวอย่าง | คำอธิบาย |
|--------|--------|---------|----------|
| Skus | Integer | 1 | ลำดับ SKU |
| Part No | String | "D65133047B" | รหัสชิ้นส่วน |
| Part name | String | "BRACKET" | ชื่อชิ้นส่วน |
| Box type | String | "A" | ประเภทกล่อง |
| UnitLabel Qt | Integer | 1 | จำนวนต่อกล่อง |
| ModuleSizeL | Float | 200 | ความยาว (mm) |
| ModuleSizeV | Float | 150 | ความกว้าง (mm) |
| ModuleSizeH | Float | 100 | ความสูง (mm) |
| Cub M | Float | 0.01 | ปริมาตรต่อกล่อง (m³) |

**เกณฑ์กรองชิ้นส่วนขนาดเล็ก:**
```
H < 1.5m AND (L < 0.68m OR W < 0.68m)
```

---

## 3. คำถามข้อ 1: Lines Per Man-Hour

### 3.1 วิธีการคำนวณ

**สูตรหลัก:**
```
Lines per Man-Hour = Total Pick Lines / Total Man-Hours

โดยที่:
- Total Pick Lines = จำนวนแถวใน shipTrans ที่เป็นชิ้นส่วนขนาดเล็ก
- Total Man-Hours = จำนวนคนงาน × ชั่วโมงทำงานจริง (หักพัก)
                  = 80 คน × 8 ชั่วโมง = 640 man-hours/วัน
```

### 3.1.1 การคำนวณ Man-Hours

**โครงสร้างกะทำงาน (จาก Shift.txt):**
| กะ | เวลา | ชั่วโมง | พัก |
|----|------|--------|-----|
| กลางวัน (Regular) | 08:00-17:00 | 9 ชม. | 1 ชม. |
| กลางวัน (OT) | 17:00-19:00 | 2 ชม. | - |
| กลางคืน | 23:00-08:00 | 9 ชม. | 1 ชม. |

**หมายเหตุเรื่องพัก:**
- ทุกกะมี 1 ชม. สำหรับพักเที่ยงและพักส่วนตัว
- พนักงานจัดเวลาพักเองได้ภายใน 1 ชม.
- **หัวหน้างาน (Supervisor) จะทำงานแทนระหว่างพัก**
- ดังนั้น ไม่กระทบประสิทธิภาพโดยรวม

**การคำนวณ Man-Hours จากโครงสร้างกะ:**
```
จาก Shift.txt มี 2 กะ:
- Morning: 08:00-17:00 = 9 ชม.
- Evening: 23:00-08:00 = 9 ชม.

จากการวิเคราะห์ DeliveryTime ใน shipTrans:
- Morning shift: ~50% ของ picks (293,784 lines)
- Evening shift: ~50% ของ picks (290,166 lines)
= แบ่งเท่าๆ กัน ดังนั้น workers แบ่ง 2 กะเท่ากัน

การคำนวณ:
- 80 workers รวม / 2 กะ = 40 workers ต่อกะ
- แต่ละกะ: 9 ชม. - 1 ชม. พัก = 8 ชม. effective
- Man-hours ต่อกะ = 40 × 8 = 320 ชม.
- รวม 2 กะ = 320 × 2 = 640 ชม./วัน
```

**สรุป:**
| พารามิเตอร์ | ค่า |
|------------|-----|
| จำนวนพนักงานรวม | 80 คน |
| จำนวนกะ | 2 (Morning + Evening) |
| พนักงานต่อกะ | 40 คน |
| Shift hours | 9 ชม. |
| Break hours | 1 ชม. |
| Effective hours/คน/กะ | 8 ชม. |
| Man-hours ต่อกะ | 320 ชม. |
| **Man-hours/day รวม** | **640 ชม.** |

**ขั้นตอนการคำนวณ:**

1. **กรองชิ้นส่วนขนาดเล็ก** จาก itemMaster
2. **นับ pick lines ต่อวัน** จาก shipTrans
3. **กรองวันทำงาน** (TotalLines >= 500)
4. **คำนวณ Lines/Man-Hour** = TotalLines / 640
5. **รวมเป็นรายเดือน** เพื่อเปรียบเทียบกับ Figure 7

### 3.2 ไฟล์ผลลัพธ์

#### Q1_daily_analysis.csv
| คอลัมน์ | ประเภท | คำอธิบาย |
|--------|--------|----------|
| ShippingDay | Date | วันที่ |
| TotalLines | Integer | จำนวน pick lines ทั้งหมด |
| TotalQty | Integer | จำนวนชิ้นส่วนทั้งหมด |
| ManHours | Float | ชั่วโมงแรงงาน (184) |
| LinesPerManHour | Float | รายการต่อชั่วโมงแรงงาน |
| IsWorkingDay | Logical | เป็นวันทำงานหรือไม่ |
| WeekDay | String | วันในสัปดาห์ |
| Month | String | เดือน (YYYYMM) |

**การใช้งาน:** วิเคราะห์ประสิทธิภาพรายวัน และตรวจสอบว่าตรงกับข้อมูลอ้างอิงหรือไม่

#### Q1_monthly_comparison.csv
| คอลัมน์ | ประเภท | คำอธิบาย |
|--------|--------|----------|
| Month | String | เดือน (เช่น "Sep 11") |
| AvgLinesPerManHour | Float | เฉลี่ย lines/man-hour |
| TotalWorkingDays | Integer | จำนวนวันทำงาน |
| TotalLines | Integer | รายการทั้งหมด |

### 3.3 กราฟผลลัพธ์

| ไฟล์ | คำอธิบาย |
|-----|----------|
| `Q1_daily_lines_per_manhour.png` | กราฟ Lines/Man-Hour รายวัน พร้อมเส้นค่าเฉลี่ย |
| `Q1_monthly_comparison.png` | เปรียบเทียบรายเดือนกับ Figure 7 |
| `Q1_monthly_total_lines.png` | จำนวน pick lines รวมรายเดือน |
| `Q1_total_lines_per_day.png` | จำนวน pick lines รายวัน |

---

## 4. คำถามข้อ 2: Fluid Model FPA Design

### 4.1 แนวคิด Fluid Model (Bartholdi & Hackman)

Fluid Model มองว่าสินค้าไหลเหมือนของเหลว:
- **Flow (D_i)** = ปริมาตรความต้องการต่อปี = Frequency × Box Volume
- **Viscosity (η_i)** = ความหนืด = ความต้องการพื้นที่ต่อหน่วย flow

### 4.2 สูตรการคำนวณ

#### ขั้นที่ 1: คำนวณ Flow และ Viscosity

```
D_i = TotalQty_i × CubM_i

โดยที่:
- D_i = Annual demand volume (m³/year) = Flow
- TotalQty_i = Total boxes picked per year (sum of ScanQty)
- CubM_i = Volume per box (m³)

**สำคัญ:** Flow ต้องใช้ TotalQty (จำนวนกล่องทั้งหมด) ไม่ใช่ Freq (จำนวนครั้งที่หยิบ)
เพราะแต่ละครั้งที่หยิบอาจหยิบหลายกล่อง

η_i = f_i / √(D_i) = picks / √(flow)

โดยที่:
- η_i = Viscosity
- f_i = Frequency (จำนวนครั้งที่หยิบ)
- D_i = Flow (ปริมาตรรวมต่อปี)
- ยิ่ง η สูง = SKU มีความถี่สูงเมื่อเทียบกับปริมาตร = ควรอยู่ใน FPA
```

**ตัวอย่างการคำนวณ:**
```
SKU: D65133047B
- f_i = 9,894 picks/year (จำนวนครั้งที่หยิบ)
- TotalQty = 197,878 boxes/year (จำนวนกล่องทั้งหมด)
- CubM = 0.01 m³/box
- D_i = 197,878 × 0.01 = 1,978.78 m³/year (Flow)
- η_i = 9,894 / √1978.78 = 9,894 / 44.48 = 222.42
```

#### ขั้นที่ 2: จัดสรรปริมาตร (Volume Allocation)

```
v_i* = V × √(D_i) / Σ√(D_j)

โดยที่:
- v_i* = Allocated volume for SKU i (m³)
- V = Total FPA volume = 36.0 m³
- D_i = Annual demand volume for SKU i
- Σ√(D_j) = Sum of √D for all selected SKUs
```

**ตัวอย่างการคำนวณ:**
```
สมมติเลือก 3 SKUs:
- SKU A: D_A = 100, √D_A = 10
- SKU B: D_B = 25, √D_B = 5
- SKU C: D_C = 4, √D_C = 2

Σ√D = 10 + 5 + 2 = 17

Volume allocation:
- v_A* = 36 × 10/17 = 21.18 m³
- v_B* = 36 × 5/17 = 10.59 m³
- v_C* = 36 × 2/17 = 4.24 m³
```

#### ขั้นที่ 3: คำนวณ Benefit

```
B_i = s × f_i - Cr × (D_i / v_i*)

โดยที่:
- B_i = Net benefit for SKU i (minutes/year)
- s = Time saved per pick = 2.0 min/line
- f_i = Annual frequency
- Cr = Replenishment time = 15.0 min/trip
- D_i / v_i* = Replenishment trips per year

แยกส่วน:
- Saving = s × f_i = เวลาที่ประหยัดจากการหยิบ
- Cost = Cr × (D_i / v_i*) = เวลาที่เสียไปในการเติมสินค้า
```

**ตัวอย่างการคำนวณ:**
```
SKU: D65133047B
- f_i = 9,894 picks/year
- D_i = 98.94 m³/year
- v_i* = 0.677 m³ (allocated)

Saving = 2.0 × 9,894 = 19,788 min/year
Replenish trips = 98.94 / 0.677 = 146.2 trips/year
Cost = 15.0 × 146.2 = 2,193 min/year

B_i = 19,788 - 2,193 = 17,595 min/year
```

#### ขั้นที่ 4: หาจำนวน SKU ที่เหมาะสม (Iterative Selection)

```
Algorithm:
1. เรียง SKUs ตาม Viscosity (สูงสุดก่อน)
2. เริ่มจาก n = 1 SKU
3. สำหรับแต่ละ n:
   a. คำนวณ Volume Allocation ใหม่สำหรับ n SKUs
   b. คำนวณ Total Benefit = Σ B_i
4. เพิ่ม n ไปเรื่อยๆ จนกว่า Total Benefit จะไม่เพิ่มขึ้น
5. n* ที่ให้ Maximum Total Benefit คือคำตอบ
```

**กราฟแสดงการหาจุดเหมาะสม:**

`Q2_benefit_vs_skus.png` - กราฟนี้แสดง:
- แกน X = จำนวน SKUs ที่เลือก
- แกน Y = Total Benefit (นาที/ปี)
- จุดสูงสุด = **154 SKUs** ให้ Benefit สูงสุด (หลังกรองช่วงน้ำท่วมและวันอาทิตย์)

### 4.3 ไฟล์ผลลัพธ์

#### Q2_FPA_Optimal_SKUs.csv (ไฟล์หลัก)
| คอลัมน์ | ประเภท | สูตร/ที่มา | คำอธิบาย |
|--------|--------|-----------|----------|
| Rank | Integer | เรียงตาม Viscosity | ลำดับความสำคัญ |
| PartNo | String | จาก shipTrans | รหัสชิ้นส่วน |
| Frequency | Integer | นับจาก shipTrans | ความถี่การหยิบต่อปี |
| DemandVolume_m3 | Float | Freq × CubM | D_i = ปริมาตรความต้องการ (m³/year) |
| Viscosity | Float | Freq / √(DemandVolume) | η_i = ความหนืด |
| AllocatedVolume_m3 | Float | V × √(D_i) / Σ√(D_j) | v_i* = ปริมาตรที่จัดสรร (m³) |
| Benefit | Float | s×f - Cr×(D/v*) | B_i = ผลประโยชน์สุทธิ (min/year) |
| ReplenishTrips | Float | D_i / v_i* | จำนวนรอบเติมสินค้าต่อปี |

**การใช้งาน:**
- ใช้เป็น Input สำหรับ Q3 (Slotting)
- ใช้เปรียบเทียบกับ COI ใน Q5

#### Q2_Benefit_Analysis.csv
| คอลัมน์ | ประเภท | คำอธิบาย |
|--------|--------|----------|
| n | Integer | จำนวน SKUs ที่เลือก |
| TotalBenefit | Float | ผลประโยชน์รวม (min/year) |
| MarginalBenefit | Float | ผลประโยชน์ส่วนเพิ่ม |

**การใช้งาน:** วิเคราะห์ว่าควรเลือก SKU กี่ตัว

#### Q2_Summary.csv
| Parameter | Value |
|-----------|-------|
| FPA Volume (m³) | 36 |
| Time Saved per Pick (min) | 2 |
| Replenishment Time (min) | 15 |
| Optimal Number of SKUs | 154 |
| Total SKUs Available | 721 |
| Percentage Selected | 21.4% |
| Maximum Total Benefit (min/year) | 274,590 |
| Benefit in Hours/Year | 4,577 |
| Total Pick Frequency (lines/year) | 192,104 |
| Total Demand Volume (m³/year) | 3,591 |

**หมายเหตุ: การกรองข้อมูล**
- DataFreq.csv ได้กรองข้อมูลช่วงน้ำท่วม (ต.ค.-พ.ย. 2554) ออกแล้ว - 37,501 แถว
- DataFreq.csv ได้กรองวันอาทิตย์ออกแล้ว - 2,978 แถว
- ข้อมูลหลังกรอง: 544,362 แถว → 721 SKUs ที่มีข้อมูลครบ

### 4.4 กราฟผลลัพธ์

| ไฟล์ | คำอธิบาย |
|-----|----------|
| `Q2_benefit_vs_skus.png` | Total Benefit vs จำนวน SKUs (หาจุดสูงสุด) |
| `Q2_marginal_benefit.png` | Marginal Benefit (เมื่อเข้าใกล้ 0 = หยุดเพิ่ม SKU) |
| `Q2_volume_allocation.png` | ปริมาตรที่จัดสรรให้แต่ละ SKU (Top 50) |

---

## 5. คำถามข้อ 3: Slotting Design

### 5.1 แนวคิด Multi-SKU per Position

**หลักการสำคัญ:** แต่ละตำแหน่ง (1.98m × 0.68m × 0.30m) สามารถวาง SKU ได้หลายตัว โดยแบ่งพื้นที่ตามความกว้าง (Width) ที่แต่ละ SKU ต้องการ

#### หลักการ Slotting
1. **Golden Zone** - ชั้นกลาง (2, 3, 4) สำหรับ SKU ที่มี Viscosity สูง
2. **Ergonomic Score** - ชั้น 3 = 100, ชั้น 2,4 = 90, ชั้น 1,5 = 60
3. **Association** - วางชิ้นส่วนที่หยิบพร้อมกันให้อยู่ใกล้กัน
4. **Multi-SKU** - แบ่งความกว้าง 1.98m ให้หลาย SKU ตามปริมาตรที่จัดสรร

### 5.2 การคำนวณความกว้างที่ต้องการ (Width Calculation)

#### ขั้นที่ 1: คำนวณจำนวนกล่องที่ใส่ได้ใน 1 คอลัมน์

```
BoxesInDepth = floor(Position_Depth / Box_Depth)
             = floor(0.68m / BoxDepth_m)

BoxesInHeight = floor(Position_Height / Box_Height)
              = floor(0.30m / BoxHeight_m)

BoxesPerColumn = BoxesInDepth × BoxesInHeight
```

**ตัวอย่าง:**
```
SKU: D65133047B
- BoxDepth = 0.15m, BoxHeight = 0.10m
- BoxesInDepth = floor(0.68 / 0.15) = 4 กล่อง
- BoxesInHeight = floor(0.30 / 0.10) = 3 กล่อง
- BoxesPerColumn = 4 × 3 = 12 กล่อง/คอลัมน์
```

#### ขั้นที่ 2: คำนวณจำนวนกล่องที่ต้องการ

```
TotalBoxesNeeded = ceiling(AllocatedVolume_m3 / CubM_per_box)

โดยที่:
- AllocatedVolume_m3 = ปริมาตรที่ได้รับจาก Q2 Fluid Model
- CubM_per_box = ปริมาตรต่อกล่อง
```

**ตัวอย่าง:**
```
SKU: D65133047B
- AllocatedVolume = 0.677 m³
- CubM = 0.01 m³/กล่อง
- TotalBoxesNeeded = ceiling(0.677 / 0.01) = 68 กล่อง
```

#### ขั้นที่ 3: คำนวณจำนวนคอลัมน์และความกว้าง

```
ColumnsNeeded = ceiling(TotalBoxesNeeded / BoxesPerColumn)

WidthNeeded_m = ColumnsNeeded × BoxWidth_m
```

**ตัวอย่าง:**
```
SKU: D65133047B
- TotalBoxesNeeded = 68 กล่อง
- BoxesPerColumn = 12 กล่อง
- ColumnsNeeded = ceiling(68 / 12) = 6 คอลัมน์
- BoxWidth = 0.33m
- WidthNeeded = 6 × 0.33 = 1.98m (ใช้เต็มตำแหน่ง)
```

### 5.3 อัลกอริทึม Bin Packing (First Fit Decreasing)

**หลักการสำคัญ: ใช้ Frequency สำหรับ Floor Assignment**

| เกณฑ์ | ใช้สำหรับ | เหตุผล |
|------|----------|--------|
| **Viscosity** | Q2: เลือก SKU เข้า FPA | พิจารณาทั้งความถี่และปริมาตร |
| **Frequency** | Q3: จัดวางตาม Floor | ยิ่งหยิบบ่อย ยิ่งต้องอยู่ตำแหน่งสะดวก |

**เหตุผลที่ใช้ Frequency:**
- ถ้า SKU ถูกหยิบ 10,000 ครั้ง/ปี → พนักงานก้ม/เอื้อม 10,000 ครั้ง
- ถ้า SKU ถูกหยิบ 1,000 ครั้ง/ปี → พนักงานก้ม/เอื้อม 1,000 ครั้ง
- SKU ที่หยิบบ่อยกว่าควรอยู่ระดับเอว (Floor 3) เพื่อลดความเมื่อยล้า

```
Algorithm:
1. เรียง SKUs ตาม FREQUENCY (สูงสุดก่อน) ← ไม่ใช่ Viscosity
2. วิเคราะห์ Association Pairs ก่อน Slotting
3. กำหนด Floor Priority: 3 → 2 → 4 → 1 → 5
4. สำหรับแต่ละ SKU:
   a. ถ้ามี Associated Items ที่วางแล้ว → พยายามวางใกล้กัน
   b. ถ้าไม่มี → ใช้ Floor Priority ปกติ
   c. คำนวณ WidthNeeded
   d. วนลูป Floor ตาม Priority
   e. วนลูป Cabinet 1-24
   f. ถ้า RemainingWidth >= WidthNeeded:
      - กำหนดตำแหน่ง (Cabinet, Floor)
      - บันทึก SubPosStart และ SubPosEnd
      - อัพเดท RemainingWidth
      - หยุดค้นหา
5. ทำซ้ำจนหมดทุก SKU
```

**ตัวอย่างการ Pack:**
```
Position C01F3 (Cabinet 1, Floor 3):
ความกว้างทั้งหมด = 1.98m

SKU 1 (D65133047B): WidthNeeded = 1.98m
  → SubPos: 0.00 - 1.98m (ใช้เต็มตำแหน่ง)
  → RemainingWidth = 0.00m

Position C02F3:
SKU 2 (C23750EJ0): WidthNeeded = 1.98m
  → SubPos: 0.00 - 1.98m

...

Position C07F3:
SKU 7 (GJ2168885B02): WidthNeeded = 1.38m
  → SubPos: 0.00 - 1.38m
  → RemainingWidth = 0.60m

SKU ถัดไปที่ Width <= 0.60m จะใส่ตำแหน่งเดียวกัน:
SKU X: WidthNeeded = 0.54m
  → SubPos: 1.38 - 1.92m
  → RemainingWidth = 0.06m
```

### 5.4 Association Analysis

#### วิธีที่ 1: Pattern Matching (LH/RH, A/B)
```
ค้นหาคู่ชิ้นส่วน:
- LH ↔ RH (Left/Right variants)
- A ↔ B (Size variants)
- L ↔ R (Position variants)

คะแนน: 100 คะแนน/คู่
```

#### วิธีที่ 2: Co-occurrence Analysis
```
นับจำนวนครั้งที่หยิบพร้อมกัน:
- สร้าง Basket = (ShippingDay, DeliveryTime, DeliveryNo#)
- นับคู่ที่อยู่ใน Basket เดียวกัน
- Normalize: CoocScore = (Count / MaxCount) × 50

คะแนน: 0-50 คะแนน
```

#### วิธีที่ 3: Correlation Analysis
```
คำนวณ Spearman Correlation:
- สร้าง Daily Frequency Matrix
- คำนวณ correlation ระหว่างทุกคู่ SKU
- เลือกคู่ที่ correlation > 0.5

คะแนน: Correlation × 50 (0-50 คะแนน)
```

#### รวม Association Score
```
TotalScore = PatternScore + CoocScore + CorScore
           = 0-100 + 0-50 + 0-50
           = 0-200 คะแนน

ถ้า TotalScore >= 40 → ควรวางใกล้กัน
```

### 5.5 ไฟล์ผลลัพธ์

#### Q3_slotting_result.csv (ไฟล์หลัก)
| คอลัมน์ | ประเภท | สูตร/ที่มา | คำอธิบาย |
|--------|--------|-----------|----------|
| ViscosityRank | Integer | เรียงตาม Viscosity | ลำดับความสำคัญ (1 = สูงสุด) |
| PartNo | String | จาก Q2 | รหัสชิ้นส่วน |
| PartName | String | จาก itemMaster | ชื่อชิ้นส่วน |
| Frequency | Integer | จาก Q2 | ความถี่การหยิบต่อปี |
| DemandVolume_m3 | Float | Freq × CubM | ปริมาตรความต้องการ (m³/year) |
| Viscosity | Float | Freq / √(DemandVolume) | ค่า Viscosity |
| AllocatedVolume_m3 | Float | จาก Q2 | ปริมาตรที่จัดสรร (m³) |
| Benefit | Float | จาก Q2 | Benefit (min/year) |
| BoxWidth_m | Float | จาก itemMaster | ความกว้างกล่อง (m) |
| BoxDepth_m | Float | จาก itemMaster | ความลึกกล่อง (m) |
| BoxHeight_m | Float | จาก itemMaster | ความสูงกล่อง (m) |
| TotalBoxesNeeded | Integer | AllocVol / CubM | จำนวนกล่องที่ต้องเก็บ |
| WidthNeeded_m | Float | ColumnsNeeded × BoxWidth | ความกว้างที่ต้องการ (m) |
| Cabinet | Integer | Bin Packing | หมายเลขตู้ (1-24) |
| Floor | Integer | Bin Packing | หมายเลขชั้น (1-5) |
| PositionID | String | "C" + Cabinet + "F" + Floor | รหัสตำแหน่ง (เช่น "C01F3") |
| **SubPosStart_m** | Float | Bin Packing | จุดเริ่มต้นใน Sub-position (m) |
| **SubPosEnd_m** | Float | Start + WidthNeeded | จุดสิ้นสุดใน Sub-position (m) |
| X | Float | (Cab-1)×2.5 + (Start+End)/2 | พิกัด X สำหรับ visualization |
| Y | Float | Floor × 0.4 | พิกัด Y สำหรับ visualization |
| ErgonomicScore | Integer | ตาม Floor | คะแนนความสะดวก (60-100) |
| AssociatedWith | String | Association Analysis | รายการ SKU ที่เกี่ยวข้อง (คั่นด้วย ,) |

**ตัวอย่างข้อมูล:**
```
ViscosityRank, PartNo,     Freq, WidthNeeded_m, Cabinet, Floor, SubPosStart_m, SubPosEnd_m
1,            D65133047B, 9894, 1.98,          1,       3,     0.00,          1.98
2,            C23750EJ0,  3742, 1.98,          2,       3,     0.00,          1.98
7,            GJ2168885B, 2126, 1.38,          7,       3,     0.00,          1.38
20,           SKU_SMALL,  500,  0.54,          7,       3,     1.38,          1.92
```

**การใช้งาน:**
- ใช้สร้าง FPA Layout ใน Simio (พิกัด X, Y)
- SubPosStart/End ระบุตำแหน่งที่แน่นอนภายใน Position
- ดูว่า SKU ใดอยู่ตำแหน่งเดียวกัน (PositionID เดียวกัน)

#### Q3_position_utilization.csv (ใหม่)
| คอลัมน์ | ประเภท | คำอธิบาย |
|--------|--------|----------|
| Cabinet | Integer | หมายเลขตู้ (1-24) |
| Floor | Integer | หมายเลขชั้น (1-5) |
| SKUsInPosition | Integer | จำนวน SKUs ในตำแหน่งนี้ |
| TotalFrequency | Integer | ผลรวมความถี่ของ SKUs ทั้งหมด |
| TotalWidth_m | Float | ความกว้างที่ใช้รวม (m) |
| WidthUsed_pct | Float | เปอร์เซ็นต์การใช้ความกว้าง |

**ตัวอย่างข้อมูล:**
```
Cabinet, Floor, SKUsInPosition, TotalWidth_m, WidthUsed_pct
1,       3,     1,              1.98,         100.0
7,       3,     2,              1.92,         97.0
15,      2,     3,              1.86,         93.9
```

#### Q3_association_pairs.csv
| คอลัมน์ | ประเภท | คำอธิบาย |
|--------|--------|----------|
| Item1 | String | SKU แรก |
| Item2 | String | SKU ที่สอง |
| PatternScore | Float | คะแนนจาก Pattern Matching (0-100) |
| CoocScore | Float | คะแนนจาก Co-occurrence (0-50) |
| TotalScore | Float | คะแนนรวม |

### 5.6 สถิติการจัดวาง (ตัวอย่างผลลัพธ์)

**กระบวนการเลือก SKU (ใช้ Cabinet Volume 48.47 m³):**
```
Step 1: Benefit Peak Analysis (Fluid Model)
- SKUs at benefit peak: 185 SKUs
- Maximum benefit (fluid): 307,878 min/year

Step 2: Apply Physical Constraints (ceil for boxes + cap to 1 position)
- SKUs after filtering: 184 SKUs
- Total width used: 236.65 / 237.6 m (99.6%)

Step 3: Bin Packing into Positions
- SKUs actually placed: 135 SKUs
- Remaining 49 SKUs couldn't fit due to fragmentation
```

**Position Utilization:**
```
- Positions with 1 SKU:  105 (88%)
- Positions with 2 SKUs: 15 (12%)
- Positions with 3+ SKUs: 0 (0%)
- Average SKUs per position: 1.12
- Average width utilization: 84.9%
```

**Floor Summary (Frequency-based assignment):**
```
Floor | SKUs | Positions | Total Frequency | Avg Viscosity | หมายเหตุ
------|------|-----------|-----------------|---------------|----------
  3   |  24  |    24     |     74,633      |      470      | GOLDEN ZONE - สูงสุด!
  2   |  25  |    24     |     41,859      |      388      | Good
  4   |  31  |    24     |     30,469      |      346      | Good
  1   |  26  |    24     |     26,067      |      326      | Lower
  5   |  29  |    24     |     22,797      |      305      | Upper

สังเกต: Floor 3 มี Total Frequency สูงสุด (74,633 picks/year)
       = พนักงานหยิบจาก Golden Zone บ่อยที่สุด = ลดการก้ม/เอื้อม
```

### 5.7 กราฟผลลัพธ์

| ไฟล์ | คำอธิบาย |
|-----|----------|
| `Q3_fpa_layout.png` | Layout ของ FPA แสดง SKU แต่ละตัว (ความกว้างตามสัดส่วน) |
| `Q3_position_utilization.png` | Heatmap แสดงจำนวน SKUs ต่อตำแหน่ง |
| `Q3_floor_distribution.png` | จำนวน SKU ต่อชั้น พร้อม SKUs/position |
| `Q3_floor_1_detail.png` | รายละเอียดชั้น 1 - แสดง SKU แต่ละตัว |
| `Q3_floor_2_detail.png` | รายละเอียดชั้น 2 - แสดง SKU แต่ละตัว |
| `Q3_floor_3_detail.png` | รายละเอียดชั้น 3 (Golden Zone) - แสดง SKU แต่ละตัว |
| `Q3_floor_4_detail.png` | รายละเอียดชั้น 4 - แสดง SKU แต่ละตัว |
| `Q3_floor_5_detail.png` | รายละเอียดชั้น 5 - แสดง SKU แต่ละตัว |

---

## 6. คำถามข้อ 4: Simio Simulation

### 6.1 ข้อมูลที่ต้องส่งออกสำหรับ Simio

#### Simio_SKU_FPA_Layout.csv
| คอลัมน์ | ประเภท | คำอธิบาย | การใช้ใน Simio |
|--------|--------|----------|----------------|
| PartNo | String | รหัสชิ้นส่วน | ใช้อ้างอิง SKU |
| PartName | String | ชื่อชิ้นส่วน | แสดงผล |
| CabinetNo | Integer | หมายเลขตู้ | กำหนด Entity Location |
| FloorNo | Integer | หมายเลขชั้น | กำหนดความสูง |
| PositionID | String | รหัสตำแหน่ง | Node ID |
| X_m | Float | พิกัด X (เมตร) | X Coordinate |
| Y_m | Float | พิกัด Y (เมตร) | Y Coordinate |
| Z_m | Float | พิกัด Z (เมตร) | Z Coordinate |
| Frequency | Integer | ความถี่ | ใช้วิเคราะห์ |
| DistanceFromIO | Float | ระยะจากจุด I/O | คำนวณเวลาเดิน |

#### Simio_Pick_Orders.csv
| คอลัมน์ | ประเภท | คำอธิบาย | การใช้ใน Simio |
|--------|--------|----------|----------------|
| OrderID | String | รหัส Order | Entity ID |
| ShippingDay | Date | วันที่ | Arrival Date |
| DeliveryTime | String | เวลา | Arrival Time |
| DeliveryHour | Integer | ชั่วโมง | Time Distribution |
| PartNo | String | รหัสชิ้นส่วน | Destination |
| BoxType | String | ประเภทกล่อง | Entity Type |
| ScanQty | Integer | จำนวน | Quantity |

#### Simio_SKU_Inventory_Params.csv
| คอลัมน์ | ประเภท | คำอธิบาย | การใช้ใน Simio |
|--------|--------|----------|----------------|
| PartNo | String | รหัสชิ้นส่วน | Reference |
| MaxBoxes | Integer | จำนวนกล่องสูงสุด | Max Inventory |
| MinBoxes | Integer | จำนวนกล่องต่ำสุด | Reorder Point |
| ReorderPoint | Integer | จุดสั่งเติม | Trigger Level |
| SafetyStock | Integer | Safety Stock | Buffer |
| DailyAvgPicks | Float | เฉลี่ยต่อวัน | Demand Rate |

#### Simio_Activity_Times.csv
| Activity | Time_min | Unit | การใช้ใน Simio |
|----------|----------|------|----------------|
| Walking | 1.0 | min/100m | Transfer Time |
| Check_and_Pick | 0.4 | min/line | Processing Time |
| Pick_per_Box | 0.1 | min/box | Additional Time |
| Replenishment_Normal | 15.0 | min/trip | Replenish Server |
| Replenishment_Emergency | 120.0 | min/trip | Emergency Delay |

### 6.2 Logic สำหรับ Simio

```
Picker Process:
1. รับ Pick Order จาก Queue
2. เดินไปตำแหน่ง SKU (Distance × 0.01 min/m)
3. Check & Pick (0.4 min + 0.1 min × boxes)
4. ถ้า Inventory <= Min → Trigger Replenishment
5. กลับไป Queue

Replenishment Process:
1. ถ้า Inventory <= Min:
   - Normal: 15 min delay
   - Replenish to Max
2. ถ้า Inventory = 0 (Stockout):
   - Emergency: 120 min delay
   - Open container
```

---

## 7. คำถามโบนัส: COI Comparison

### 7.1 วิธี COI (Cube-Per-Order Index)

```
COI_i = D_i / f_i = Volume per pick

โดยที่:
- D_i = Annual demand volume (m³/year)
- f_i = Annual frequency (picks/year)
- COI ต่ำ = SKU ควรอยู่ใกล้จุด I/O (เข้าถึงง่าย)
```

### 7.2 ความแตกต่างระหว่าง Fluid Model และ COI

| เกณฑ์ | Fluid Model | COI |
|------|-------------|-----|
| การเรียงลำดับ | Viscosity (f/√D) | COI (D/f) |
| การจัดสรรปริมาตร | v* = V×√D/Σ√D (Optimal) | v = V×D/ΣD (Proportional) |
| พิจารณา Replenishment | ใช่ | ไม่ |
| ปรับ Trade-off | ใช่ (s vs Cr) | ไม่ |

### 7.3 ไฟล์ผลลัพธ์

#### Q5_Comparison_Summary.csv
| Method | SKUs_Selected | Total_Benefit_min | Total_Benefit_hrs | Improvement_pct |
|--------|---------------|-------------------|-------------------|-----------------|
| Fluid Model | 159 | 294,593.50 | 4,909.89 | - |
| COI | 159 | 109,908.00 | 1,831.80 | 168.04 |

#### Q5_COI_SKUs.csv
| คอลัมน์ | ประเภท | คำอธิบาย |
|--------|--------|----------|
| PartNo | String | รหัสชิ้นส่วน |
| Freq | Integer | ความถี่ |
| Volume | Float | ปริมาตรความต้องการ |
| COI | Float | Cube-Per-Order Index |
| AllocatedVolume_COI | Float | ปริมาตรที่จัดสรร (COI method) |
| Benefit_COI | Float | Benefit (min/year) |

### 7.4 กราฟผลลัพธ์

| ไฟล์ | คำอธิบาย |
|-----|----------|
| `Q5_benefit_distribution.png` | การกระจายตัวของ Benefit ทั้งสองวิธี |
| `Q5_volume_allocation_comparison.png` | เปรียบเทียบการจัดสรรปริมาตร |
| `Q5_freq_vs_coi.png` | ความสัมพันธ์ Frequency vs COI |

### 7.5 สรุปผล

```
Fluid Model ดีกว่า COI 168%

เหตุผล:
1. Fluid Model เลือก SKU ตาม Viscosity (f/√D) ซึ่งพิจารณาทั้งความถี่และปริมาตร
2. Fluid Model จัดสรรปริมาตรแบบ Optimal (√D) ไม่ใช่ Proportional (D)
3. Fluid Model พิจารณา Trade-off ระหว่าง Saving และ Replenishment Cost

Overlap Analysis:
- SKU ที่ทั้งสองวิธีเลือก: 80 SKU (50.3%)
- SKU ที่ต่างกัน: 79 SKU
```

---

## 8. ความสัมพันธ์ระหว่างไฟล์

### 8.1 Flow Chart

```
                    ┌──────────────────┐
                    │   INPUT DATA     │
                    │  shipTrans.txt   │
                    │  itemMaster.txt  │
                    └────────┬─────────┘
                             │
          ┌──────────────────┼──────────────────┐
          │                  │                  │
          ▼                  ▼                  ▼
   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
   │    Freq.R    │  │     Q1       │  │     Q5       │
   │  DataFreq.csv│  │  Analysis    │  │    COI       │
   └──────┬───────┘  └──────────────┘  └──────────────┘
          │
          ▼
   ┌──────────────┐
   │     Q2       │
   │ Fluid Model  │
   │ 154 SKUs     │
   │ (V=36 m³)    │
   └──────┬───────┘
          │
          ▼
   ┌──────────────┐
   │     Q3       │
   │  Slotting    │
   │ 185→135 SKUs │
   │ (V=48.47 m³) │
   │ 120 Positions│
   └──────┬───────┘
          │
          ▼
   ┌──────────────┐
   │    Simio     │
   │   Export     │
   └──────────────┘
```

### 8.2 ลำดับการรัน Script

```bash
# 1. คำนวณ Frequency และ Viscosity
Rscript Freq.R

# 2. ออกแบบ FPA ด้วย Fluid Model (หา Optimal SKUs)
Rscript Q2_FluidModel.R

# 3. จัดวาง SKUs ลงตำแหน่ง
Rscript Q3_Slotting.R

# 4. วิเคราะห์ Lines per Man-Hour (แยกอิสระ)
Rscript Q1_LinesPerManHour.R

# 5. ส่งออกข้อมูลสำหรับ Simio
Rscript SimioData_Export.R

# 6. เปรียบเทียบกับ COI (โบนัส)
Rscript Q5_COI_Comparison.R
```

### 8.3 สรุปไฟล์ทั้งหมด

| คำถาม | Script | Output หลัก | Output เสริม |
|-------|--------|-------------|--------------|
| - | Freq.R | DataFreq.csv | SKU_frequency_analysis.csv |
| Q1 | Q1_LinesPerManHour.R | Q1_daily_analysis.csv | Q1_monthly_comparison.csv, 4 PNG |
| Q2 | Q2_FluidModel.R | Q2_FPA_Optimal_SKUs.csv | Q2_Benefit_Analysis.csv, 3 PNG |
| Q3 | Q3_Slotting.R | Q3_slotting_result.csv (135 SKUs) | Q3_position_utilization.csv, Q3_association_pairs.csv, 8 PNG |
| Q4 | Q4_Simio_Tables.R | 4 Simio_*.csv | - |
| Q5 | Q5_COI_Comparison.R | Q5_Comparison_Summary.csv | Q5_COI_SKUs.csv, 3 PNG |

---

## หมายเหตุ

### ผลลัพธ์หลัก Q1: Lines Per Man-Hour
- **ค่าเฉลี่ย: 2.19 lines/man-hour** (ไม่รวมช่วงน้ำท่วม)
- **จำนวนกะ:** 2 (Morning ~50% picks + Evening ~50% picks)
- **พนักงานต่อกะ:** 40 คน (80 รวม / 2 กะ)
- **Effective hours/คน/กะ:** 8 ชม. (9 ชม. shift - 1 ชม. break)
- **Man-hours ต่อกะ:** 320 ชม. (40 คน × 8 ชม.)
- **Man-hours/day รวม:** 640 ชม. (320 × 2 กะ)

### ผลลัพธ์หลัก Q2: Fluid Model
- **Q2 เลือก 154 SKUs** จาก 721 SKUs (21.4%)
- **พารามิเตอร์:** V=36 m³, s=2.0 min/pick, Cr=15.0 min/trip
- **Maximum Benefit: 274,590 นาที/ปี** (4,577 ชั่วโมง/ปี)
- **Total Pick Frequency: 192,104 lines/year**
- **Total Demand Volume: 3,591 m³/year**
- **สูตร Flow ที่ถูกต้อง:** D_i = TotalQty × (CubM / UnitLabelQt) = ปริมาตรต่อชิ้น × จำนวนชิ้น

### การกรองข้อมูล (Freq.R)
- **กรองช่วงน้ำท่วม:** ต.ค.-พ.ย. 2554 (201110, 201111) - 37,501 แถว
- **กรองวันอาทิตย์:** 2,978 แถว
- **ข้อมูลหลังกรอง:** 544,362 แถว (จาก 584,841 แถว)
- **เหตุผล:** ข้อมูลช่วงน้ำท่วมเป็นสภาวะผิดปกติ ไม่ควรใช้ในการออกแบบ FPA

### Q3 Slotting (Multi-SKU per Position, Frequency-based)
- **ใช้ Cabinet Volume 48.47 m³** (ไม่ใช่ 36 m³) สำหรับ benefit calculation
- **185 SKUs ที่ benefit peak** → 184 SKUs หลัง physical constraints → **135 SKUs จัดลงใน FPA จริง**
- **Golden Zone (Floor 3) สำหรับ SKU ที่มี Frequency สูงสุด** (74,633 picks/year)
- **ใช้ Frequency (ไม่ใช่ Viscosity) สำหรับ floor assignment** เพื่อลดการก้ม/เอื้อม
- **Physical constraints:** ceil() สำหรับ boxes, cap to 1 position width per SKU
- **Total width used: 236.65 / 237.6 m** (99.6% capacity)

### ข้อสังเกตสำคัญเกี่ยวกับสูตร Flow
- **Flow = TotalQty × (CubM / UnitLabelQt)** (ถูกต้อง - ปริมาตรต่อชิ้น × จำนวนชิ้น)
- **CubM** = ปริมาตรต่อกล่อง (box volume)
- **UnitLabelQt** = จำนวนชิ้นต่อกล่อง (pieces per box)
- **TotalQty** = จำนวนชิ้นทั้งหมดที่หยิบ (total pieces picked)

### ข้อควรระวัง
1. ต้องรัน Freq.R ก่อน Q2
2. ต้องรัน Q2 ก่อน Q3
3. Q1 และ Q5 รันแยกอิสระได้
4. Simio Export ต้องรันหลัง Q3
5. **ข้อมูลช่วงน้ำท่วม (ต.ค.-พ.ย. 2554) ถูกกรองออกแล้ว** - อย่านำไปเปรียบเทียบกับ PDF ที่รวมช่วงน้ำท่วม
