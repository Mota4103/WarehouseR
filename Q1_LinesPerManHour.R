###############################################################################
# Q1_LinesPerManHour.R - คำถามข้อ 1 (15 คะแนน)
# วิเคราะห์จำนวนรายการต่อชั่วโมงแรงงาน (Lines per Man-Hour)
# เปรียบเทียบรายวันและรายเดือนกับรูปที่ 7 ใน PDF
###############################################################################

library(data.table)
library(ggplot2)

# ตั้งค่าฟอนต์ภาษาไทยสำหรับ macOS
# ใช้ฟอนต์ Thonburi หรือ Ayuthaya ที่มีมาในระบบ
if (Sys.info()["sysname"] == "Darwin") {
  theme_set(theme_minimal(base_family = "Thonburi"))
} else if (Sys.info()["sysname"] == "Windows") {
  theme_set(theme_minimal(base_family = "TH Sarabun New"))
} else {
  theme_set(theme_minimal())
}

cat("=== คำถามข้อ 1: วิเคราะห์ Lines per Man-Hour ===\n\n")

### =========================
### STEP 1: โหลดข้อมูล
### =========================
cat("กำลังโหลดข้อมูล...\n")
shipTrans <- fread("shipTrans.txt", sep = ",", header = TRUE)
itemMaster <- fread("itemMaster.txt", sep = ",", header = TRUE)
shift_data <- fread("Shift.txt", sep = ",", header = TRUE)

cat("  - shipTrans: ", format(nrow(shipTrans), big.mark=","), " แถว\n", sep="")

### =========================
### STEP 2: ทำความสะอาดข้อมูล
### =========================
setnames(shipTrans, names(shipTrans), gsub("[ .]", "", names(shipTrans)))
setnames(itemMaster, names(itemMaster), gsub("[ .]", "", names(itemMaster)))

# แก้ไขชื่อคอลัมน์ itemMaster
if ("PartNo" %in% names(itemMaster) == FALSE) {
  old_names <- names(itemMaster)[1:9]
  new_names <- c("Skus", "PartNo", "PartName", "BoxType", "UnitLabelQt",
                 "ModuleSizeL", "ModuleSizeV", "ModuleSizeH", "CubM")
  setnames(itemMaster, old_names, new_names)
}

# แปลงข้อมูลเป็นตัวเลข
itemMaster[, ModuleSizeL := as.numeric(gsub(",", "", ModuleSizeL))]
itemMaster[, ModuleSizeV := as.numeric(gsub(",", "", ModuleSizeV))]
itemMaster[, ModuleSizeH := as.numeric(gsub(",", "", ModuleSizeH))]

# แปลงหน่วยเป็นเมตร
itemMaster[, L_m := ModuleSizeL / 1000]
itemMaster[, W_m := ModuleSizeV / 1000]
itemMaster[, H_m := ModuleSizeH / 1000]

### =========================
### STEP 3: กรองเฉพาะชิ้นส่วนขนาดเล็ก
### =========================
cat("กรองเฉพาะชิ้นส่วนขนาดเล็ก (H < 1.5m, L หรือ W < 0.68m)...\n")
filtered_SKUs <- itemMaster[H_m < 1.5 & (L_m < 0.68 | W_m < 0.68)]

shipTrans[, PartNo := gsub("[ ]", "", PartNo)]
filtered_SKUs[, PartNo := gsub("[ ]", "", PartNo)]

shipTrans_small <- shipTrans[PartNo %in% filtered_SKUs$PartNo]
shipTrans_small <- shipTrans_small[!is.na(PartNo) & PartNo != ""]

cat("  - รายการหยิบชิ้นส่วนขนาดเล็ก: ", format(nrow(shipTrans_small), big.mark=","), "\n\n", sep="")

### =========================
### STEP 4: แปลงวันที่
### =========================
shipTrans_small[, ShippingDay := as.Date(as.character(ShippingDay), "%Y%m%d")]
shipTrans_small[, YearMonth := format(ShippingDay, "%Y%m")]

### =========================
### STEP 5: พารามิเตอร์แรงงาน
### =========================
# จากเอกสาร: พนักงานหยิบชิ้นส่วนขนาดเล็ก 80 คน
num_workers <- 80

# Morning Shift: 08:00-17:00 (9 ชม.) + OT 17:00-19:00 (2 ชม.) = 11 ชม.
# สมมติทำงานเฉพาะ Regular Hours = 9 ชม./วัน
hours_per_day <- 9

# ชั่วโมงแรงงานต่อวัน
man_hours_per_day <- num_workers * hours_per_day

cat("พารามิเตอร์แรงงาน:\n")
cat("  - จำนวนพนักงานหยิบชิ้นส่วนขนาดเล็ก: ", num_workers, " คน\n", sep="")
cat("  - ชั่วโมงทำงานต่อวัน: ", hours_per_day, " ชม.\n", sep="")
cat("  - Man-hours ต่อวัน: ", man_hours_per_day, " ชม.\n\n", sep="")

### =========================
### STEP 6: วิเคราะห์รายวัน
### =========================
cat("คำนวณ Lines per Man-Hour รายวัน...\n")

# นับจำนวน lines (รายการหยิบ) ต่อวัน
# แต่ละแถวใน shipTrans คือ 1 line
daily_lines <- shipTrans_small[, .(
  TotalLines = .N,
  UniqueSKUs = uniqueN(PartNo),
  TotalQty = sum(ScanQty, na.rm = TRUE)
), by = ShippingDay]

# เพิ่มวันในสัปดาห์
daily_lines[, DayOfWeek := weekdays(ShippingDay)]
daily_lines[, IsWeekend := DayOfWeek %in% c("Saturday", "Sunday")]

# กำหนดว่าเป็นวันทำงานปกติหรือไม่ (ต้องมี TotalLines >= 500)
# วันที่มีรายการน้อยมากอาจเป็นวันหยุดหรือเหตุพิเศษ
daily_lines[, IsWorkingDay := TotalLines >= 500]

# คำนวณ Man-Hours เฉพาะวันทำงาน
daily_lines[, ManHours := ifelse(IsWorkingDay, man_hours_per_day, 0)]
daily_lines[, LinesPerManHour := ifelse(ManHours > 0, TotalLines / ManHours, NA)]

# เพิ่มข้อมูลเดือน
daily_lines[, YearMonth := format(ShippingDay, "%Y%m")]
daily_lines[, MonthLabel := format(ShippingDay, "%b %y")]

setorder(daily_lines, ShippingDay)

# แยกวันทำงานและวันหยุด
working_days <- daily_lines[IsWorkingDay == TRUE]
non_working_days <- daily_lines[IsWorkingDay == FALSE]

cat("  - จำนวนวันที่มีข้อมูล: ", nrow(daily_lines), " วัน\n", sep="")
cat("  - จำนวนวันทำงานปกติ (Lines >= 500): ", nrow(working_days), " วัน\n", sep="")
cat("  - จำนวนวันหยุด/กิจกรรมน้อย: ", nrow(non_working_days), " วัน\n", sep="")
cat("  - Lines per Man-Hour เฉลี่ย (เฉพาะวันทำงาน): ",
    round(mean(working_days$LinesPerManHour, na.rm = TRUE), 2), "\n\n", sep="")

### =========================
### STEP 7: วิเคราะห์รายเดือน
### =========================
cat("คำนวณ Lines per Man-Hour รายเดือน...\n")

# ใช้เฉพาะวันทำงาน (IsWorkingDay == TRUE)
monthly_lines <- working_days[, .(
  WorkingDays = .N,
  TotalLines = sum(TotalLines),
  TotalManHours = sum(ManHours),
  AvgDailyLines = mean(TotalLines)
), by = YearMonth]

monthly_lines[, LinesPerManHour := TotalLines / TotalManHours]

# แปลงชื่อเดือนเป็นภาษาไทย
month_thai <- c(
  "201109" = "ก.ย. 54", "201110" = "ต.ค. 54", "201111" = "พ.ย. 54",
  "201112" = "ธ.ค. 54", "201201" = "ม.ค. 55", "201202" = "ก.พ. 55",
  "201203" = "มี.ค. 55", "201204" = "เม.ย. 55", "201205" = "พ.ค. 55",
  "201206" = "มิ.ย. 55", "201207" = "ก.ค. 55", "201208" = "ส.ค. 55"
)
monthly_lines[, MonthThai := month_thai[YearMonth]]

setorder(monthly_lines, YearMonth)

### =========================
### STEP 8: เปรียบเทียบกับรูปที่ 7
### =========================
cat("\n=== เปรียบเทียบกับรูปที่ 7 ===\n\n")

# ค่าจากรูปที่ 7 ในเอกสาร
figure7_values <- data.table(
  YearMonth = c("201109", "201110", "201111", "201112", "201201", "201202",
                "201203", "201204", "201205", "201206", "201207", "201208"),
  MonthThai = c("ก.ย. 54", "ต.ค. 54", "พ.ย. 54", "ธ.ค. 54", "ม.ค. 55", "ก.พ. 55",
                "มี.ค. 55", "เม.ย. 55", "พ.ค. 55", "มิ.ย. 55", "ก.ค. 55", "ส.ค. 55"),
  Figure7_Value = c(7.51, 1.89, 2.90, 6.75, 8.24, 7.45, 8.73, 8.01, 7.48, 8.08, 7.95, 7.41)
)

# รวมข้อมูล
comparison <- merge(monthly_lines, figure7_values, by = "YearMonth", all = TRUE)
comparison[, Difference := LinesPerManHour - Figure7_Value]
comparison[, DiffPercent := (Difference / Figure7_Value) * 100]

cat("ตารางเปรียบเทียบ Lines per Man-Hour รายเดือน:\n\n")
print(comparison[, .(MonthThai.x, LinesPerManHour = round(LinesPerManHour, 2),
                     Figure7 = Figure7_Value,
                     Diff = round(Difference, 2),
                     DiffPct = paste0(round(DiffPercent, 1), "%"))])

### =========================
### STEP 9: คำนวณค่าเฉลี่ย (ไม่รวมเดือนน้ำท่วม)
### =========================
cat("\n=== สถิติสรุป ===\n\n")

# เดือนน้ำท่วม: ต.ค. - พ.ย. 2554
flood_months <- c("201110", "201111")
normal_months <- monthly_lines[!YearMonth %in% flood_months]

avg_all <- mean(monthly_lines$LinesPerManHour, na.rm = TRUE)
avg_normal <- mean(normal_months$LinesPerManHour, na.rm = TRUE)

cat("ค่าเฉลี่ย Lines per Man-Hour:\n")
cat("  - รวมทุกเดือน: ", round(avg_all, 2), "\n", sep="")
cat("  - ไม่รวมเดือนน้ำท่วม (ต.ค.-พ.ย. 54): ", round(avg_normal, 2), "\n", sep="")
cat("  - ค่าอ้างอิงจากเอกสาร: 7.76\n\n")

### =========================
### STEP 10: สร้างกราฟ
### =========================
cat("สร้างกราฟ...\n")

# Theme for graphs (English labels)
clean_theme <- theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

# English month labels
month_eng <- c(
  "201109" = "Sep 11", "201110" = "Oct 11", "201111" = "Nov 11",
  "201112" = "Dec 11", "201201" = "Jan 12", "201202" = "Feb 12",
  "201203" = "Mar 12", "201204" = "Apr 12", "201205" = "May 12",
  "201206" = "Jun 12", "201207" = "Jul 12", "201208" = "Aug 12"
)

# Graph 1: Daily Lines per Man-Hour (working days only)
p_daily <- ggplot(working_days, aes(x = ShippingDay, y = LinesPerManHour)) +
  geom_line(color = "steelblue", linewidth = 0.5) +
  geom_point(color = "steelblue", size = 1) +
  geom_hline(yintercept = avg_normal, linetype = "dashed", color = "red") +
  labs(
    title = "Daily Lines per Man-Hour (Small Parts)",
    subtitle = paste0("Average = ", round(avg_normal, 2), " lines/man-hour (excluding flood months)"),
    x = "Date",
    y = "Lines per Man-Hour"
  ) +
  clean_theme

ggsave("Q1_daily_lines_per_manhour.png", p_daily, width = 12, height = 6, dpi = 150)

# Graph 2: Total Lines Per Day (for presentation)
p_total_lines <- ggplot(daily_lines, aes(x = ShippingDay, y = TotalLines)) +
  geom_bar(stat = "identity", fill = ifelse(daily_lines$IsWorkingDay, "steelblue", "gray70")) +
  geom_hline(yintercept = mean(working_days$TotalLines), linetype = "dashed", color = "red") +
  labs(
    title = "Daily Pick Lines",
    subtitle = paste0("Average = ", format(round(mean(working_days$TotalLines)), big.mark=","),
                      " lines/day (working days only)"),
    x = "Date",
    y = "Total Lines"
  ) +
  clean_theme

ggsave("Q1_total_lines_per_day.png", p_total_lines, width = 12, height = 6, dpi = 150)

# Graph 3: Monthly comparison with Figure 7
comparison[, MonthEng := month_eng[YearMonth]]
comparison_long <- melt(comparison[, .(YearMonth, MonthEng,
                                        Calculated = LinesPerManHour,
                                        Figure7 = Figure7_Value)],
                        id.vars = c("YearMonth", "MonthEng"),
                        variable.name = "Source", value.name = "Value")

comparison_long[, MonthEng := factor(MonthEng, levels = month_eng)]

p_monthly <- ggplot(comparison_long, aes(x = MonthEng, y = Value, fill = Source)) +
  geom_bar(stat = "identity", position = "dodge") +
  geom_text(aes(label = round(Value, 2)), position = position_dodge(width = 0.9),
            vjust = -0.5, size = 3) +
  scale_fill_manual(values = c("Calculated" = "steelblue", "Figure7" = "coral"),
                    labels = c("Calculated from Data", "Figure 7 (Reference)")) +
  labs(
    title = "Monthly Lines per Man-Hour Comparison",
    subtitle = "Calculated vs Figure 7 Reference",
    x = "Month",
    y = "Lines per Man-Hour",
    fill = "Source"
  ) +
  clean_theme +
  theme(legend.position = "bottom")

ggsave("Q1_monthly_comparison.png", p_monthly, width = 10, height = 6, dpi = 150)

# Graph 4: Monthly Total Lines
monthly_total <- daily_lines[, .(
  WorkingDays = sum(IsWorkingDay),
  TotalLines = sum(TotalLines),
  NonWorkingDays = sum(!IsWorkingDay)
), by = YearMonth]
monthly_total[, MonthEng := month_eng[YearMonth]]
monthly_total[, MonthEng := factor(MonthEng, levels = month_eng)]

p_monthly_lines <- ggplot(monthly_total, aes(x = MonthEng, y = TotalLines)) +
  geom_bar(stat = "identity", fill = "steelblue") +
  geom_text(aes(label = format(TotalLines, big.mark=",")), vjust = -0.5, size = 3) +
  labs(
    title = "Monthly Total Pick Lines",
    subtitle = "Small Parts Only",
    x = "Month",
    y = "Total Lines"
  ) +
  clean_theme

ggsave("Q1_monthly_total_lines.png", p_monthly_lines, width = 10, height = 6, dpi = 150)

cat("  - บันทึกไฟล์: Q1_daily_lines_per_manhour.png\n")
cat("  - บันทึกไฟล์: Q1_total_lines_per_day.png\n")
cat("  - บันทึกไฟล์: Q1_monthly_comparison.png\n")
cat("  - บันทึกไฟล์: Q1_monthly_total_lines.png\n")

### =========================
### STEP 11: บันทึกผล
### =========================
fwrite(daily_lines, "Q1_daily_analysis.csv")
fwrite(comparison, "Q1_monthly_comparison.csv")

cat("  - บันทึกไฟล์: Q1_daily_analysis.csv\n")
cat("  - บันทึกไฟล์: Q1_monthly_comparison.csv\n")

cat("\n=== เสร็จสิ้นคำถามข้อ 1 ===\n")
