###############################################################################
# Freq.R - คำนวณความถี่และ Viscosity สำหรับ Fluid Model
# แก้ไขให้โหลดข้อมูลจาก shipTrans.txt และสร้าง DataFreq.csv
###############################################################################

library(data.table)

cat("=== เริ่มต้นการวิเคราะห์ความถี่ ===\n\n")

### =========================
### STEP 1: โหลดข้อมูล
### =========================
cat("กำลังโหลดข้อมูล...\n")
shipTrans <- fread("shipTrans.txt", sep = ",", header = TRUE)
itemMaster <- fread("itemMaster.txt", sep = ",", header = TRUE)

cat("  - shipTrans: ", format(nrow(shipTrans), big.mark=","), " แถว\n", sep="")
cat("  - itemMaster: ", format(nrow(itemMaster), big.mark=","), " รายการ\n\n", sep="")

### =========================
### STEP 2: ทำความสะอาดชื่อคอลัมน์
### =========================
setnames(shipTrans, names(shipTrans), gsub("[ .]", "", names(shipTrans)))
setnames(itemMaster, names(itemMaster), gsub("[ .]", "", names(itemMaster)))

# แก้ไขชื่อคอลัมน์ itemMaster
if ("PartNo" %in% names(itemMaster) == FALSE) {
  # ถ้าคอลัมน์ชื่อไม่ตรง ให้ตั้งชื่อใหม่
  old_names <- names(itemMaster)[1:9]
  new_names <- c("Skus", "PartNo", "PartName", "BoxType", "UnitLabelQt",
                 "ModuleSizeL", "ModuleSizeV", "ModuleSizeH", "CubM")
  setnames(itemMaster, old_names, new_names)
}

### =========================
### STEP 3: แปลงข้อมูลเป็นตัวเลข
### =========================
itemMaster[, ModuleSizeL := as.numeric(gsub(",", "", ModuleSizeL))]
itemMaster[, ModuleSizeV := as.numeric(gsub(",", "", ModuleSizeV))]
itemMaster[, ModuleSizeH := as.numeric(gsub(",", "", ModuleSizeH))]
itemMaster[, CubM := as.numeric(gsub(",", "", CubM))]

# แปลงหน่วยเป็นเมตร
itemMaster[, L_m := ModuleSizeL / 1000]
itemMaster[, W_m := ModuleSizeV / 1000]
itemMaster[, H_m := ModuleSizeH / 1000]

### =========================
### STEP 4: กรองเฉพาะชิ้นส่วนขนาดเล็ก
### ตามเงื่อนไข: H < 1.5m และ (L < 0.68m หรือ W < 0.68m)
### =========================
cat("กรองชิ้นส่วนขนาดเล็ก...\n")
filtered_SKUs <- itemMaster[H_m < 1.5 & (L_m < 0.68 | W_m < 0.68)]
cat("  - ชิ้นส่วนขนาดเล็กที่ผ่านเกณฑ์: ", nrow(filtered_SKUs), " รายการ\n\n", sep="")

### =========================
### STEP 5: กรอง shipTrans เฉพาะชิ้นส่วนขนาดเล็ก
### =========================
shipTrans[, PartNo := gsub("[ ]", "", PartNo)]
filtered_SKUs[, PartNo := gsub("[ ]", "", PartNo)]

shipTrans_small <- shipTrans[PartNo %in% filtered_SKUs$PartNo]
shipTrans_small <- shipTrans_small[!is.na(PartNo) & PartNo != ""]

cat("กรองข้อมูลการจัดส่ง...\n")
cat("  - รายการจัดส่งทั้งหมด: ", format(nrow(shipTrans), big.mark=","), "\n", sep="")
cat("  - รายการจัดส่งชิ้นส่วนขนาดเล็ก: ", format(nrow(shipTrans_small), big.mark=","), "\n\n", sep="")

### =========================
### STEP 6: คำนวณความถี่ต่อ SKU
### =========================
cat("คำนวณความถี่การหยิบ...\n")

# นับจำนวนครั้งที่หยิบแต่ละ PartNo (แต่ละแถวคือ 1 line)
sku_freq <- shipTrans_small[, .(
  Freq = .N,
  TotalQty = sum(ScanQty, na.rm = TRUE)
), by = PartNo]

cat("  - จำนวน SKU ที่มีการหยิบ: ", nrow(sku_freq), " รายการ\n\n", sep="")

### =========================
### STEP 7: รวมข้อมูลขนาดกล่องจาก itemMaster
### =========================
cat("รวมข้อมูลขนาดกล่อง...\n")

# หลัง gsub ชื่อคอลัมน์จะเป็น: Partname, Boxtype (ตัวเล็ก)
sku_freq <- merge(
  sku_freq,
  filtered_SKUs[, .(PartNo, Partname, Boxtype, CubM, ModuleSizeL, ModuleSizeV, ModuleSizeH)],
  by = "PartNo",
  all.x = TRUE
)

# Rename to standard names
setnames(sku_freq, "Partname", "PartName", skip_absent = TRUE)
setnames(sku_freq, "Boxtype", "BoxType", skip_absent = TRUE)

# กรองออก SKU ที่ไม่มีข้อมูลปริมาตร
sku_freq <- sku_freq[!is.na(CubM) & CubM > 0]
cat("  - SKU ที่มีข้อมูลปริมาตรครบ: ", nrow(sku_freq), " รายการ\n\n", sep="")

### =========================
### STEP 8: คำนวณปริมาตรรวมและ Viscosity
### =========================
cat("คำนวณ Viscosity...\n")

# Volume = ปริมาตรรวมที่ต้องจัดส่งต่อปี = Freq × CubM (Flow/Demand)
sku_freq[, Volume := Freq * CubM]

# Viscosity = Freq / √(Volume) ตาม Fluid Model (Bartholdi & Hackman)
# η_i = f_i / √(D_i) = picks / √(flow)
sku_freq[, Viscosity := Freq / sqrt(Volume)]

# เรียงตาม Viscosity จากมากไปน้อย
setorder(sku_freq, -Viscosity)
sku_freq[, Rank := 1:.N]

### =========================
### STEP 9: จัดประเภท ABC
### =========================
total_skus <- nrow(sku_freq)
high_cut <- ceiling(0.10 * total_skus)   # top 10% SKUs
med_cut  <- ceiling(0.35 * total_skus)   # top 35% = 10% + 25%

sku_freq[, Category := fifelse(Rank <= high_cut, "High",
                               fifelse(Rank <= med_cut, "Medium", "Low"))]

### =========================
### STEP 10: แสดงผลและบันทึก
### =========================
cat("\n=== สรุปผลการวิเคราะห์ ===\n\n")

cat("Top 20 SKUs ตาม Viscosity:\n")
print(sku_freq[1:20, .(Rank, PartNo, Freq, Volume, Viscosity, Category)])

cat("\nจำนวน SKU แต่ละประเภท:\n")
print(sku_freq[, .N, by = Category])

cat("\nสถิติสรุป:\n")
cat("  - ความถี่รวม: ", format(sum(sku_freq$Freq), big.mark=","), " รายการ\n", sep="")
cat("  - ปริมาตรรวม: ", round(sum(sku_freq$Volume), 2), " m³\n", sep="")
cat("  - Viscosity รวม: ", format(sum(sku_freq$Viscosity), big.mark=",", scientific=FALSE), "\n", sep="")

### =========================
### STEP 11: สร้าง DataFreq.csv สำหรับ Viscosity.R
### =========================
cat("\nสร้างไฟล์ DataFreq.csv...\n")

# เลือกเฉพาะคอลัมน์ที่ Viscosity.R ต้องการ
DataFreq <- sku_freq[, .(PartNo, Volume, Freq, Viscosity)]
fwrite(DataFreq, "DataFreq.csv")

cat("  - บันทึกไฟล์: DataFreq.csv (", nrow(DataFreq), " แถว)\n", sep="")

### =========================
### STEP 12: บันทึกไฟล์รายละเอียดเพิ่มเติม
### =========================
fwrite(sku_freq, "SKU_frequency_analysis.csv")
cat("  - บันทึกไฟล์: SKU_frequency_analysis.csv\n")

cat("\n=== เสร็จสิ้น ===\n")
