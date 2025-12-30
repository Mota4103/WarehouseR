library(data.table)

### =========================
###  LOAD & CLEAN DATA
### =========================
shipTrans <- fread("shipTrans.txt", sep = ",", header = TRUE)
itemMaster <- fread("itemMaster.txt", sep = ",", header = TRUE)

# Clean names
setnames(shipTrans, names(shipTrans), gsub("[ .]", "", names(shipTrans)))
setnames(itemMaster, names(itemMaster), gsub("[ .]", "", names(itemMaster)))

### =========================
###  FILTER ITEM DIMENSIONS
### =========================
itemMaster[, ModuleSizeL := as.numeric(ModuleSizeL)]
itemMaster[, ModuleSizeV := as.numeric(ModuleSizeV)]
itemMaster[, ModuleSizeH := as.numeric(ModuleSizeH)]

itemMaster[, L_m := ModuleSizeL / 1000]
itemMaster[, W_m := ModuleSizeV / 1000]
itemMaster[, H_m := ModuleSizeH / 1000]

filtered_SKUs <- itemMaster[H_m < 1.5 & (L_m < 0.68 | W_m < 0.68)]

shipTrans <- shipTrans[PartNo %in% filtered_SKUs$PartNo]
shipTrans <- shipTrans[!is.na(PartNo) & PartNo != ""]

### =========================
###  FIX DATE + TIME PARSING
### =========================
shipTrans[, ShippingDay := as.Date(as.character(ShippingDay), "%Y%m%d")]
shipTrans[, DeliveryTime := sprintf("%04d", as.integer(DeliveryTime))]
shipTrans[, DeliveryTime := paste0(substr(DeliveryTime, 1, 2), ":", substr(DeliveryTime, 3, 4), ":00")]

shipTrans[, DateTime := as.POSIXct(paste(ShippingDay, DeliveryTime), format = "%Y-%m-%d %H:%M:%S")]

### =========================
###  CREATE BASKET KEYS
### =========================
shipTrans[, Date := as.Date(DateTime)]
shipTrans[, DateHour := as.POSIXct(format(DateTime, "%Y-%m-%d %H:00:00"))]
shipTrans[, ExactTime := DateTime]

### =========================
###  GENERIC PAIR FUNCTION
### =========================
make_pairs <- function(dt, key_col) {
  dt[, {
    items <- unique(PartNo)
    if (length(items) >= 2) {
      if (length(items) > 1000) {
        items <- sample(items, 1000)
        warning(paste("Large basket", get(key_col)[1], "sampled to 1000 items"))
      }
      pairs <- t(combn(sort(items), 2))
      data.table(Item1 = pairs[,1], Item2 = pairs[,2])
    }
  }, by = key_col]
}

### =========================
###  DAILY PAIRS
### =========================
pairs_daily <- make_pairs(shipTrans, "Date")
pair_count_daily <- pairs_daily[, .(Frequency = .N), by = .(Item1, Item2)]
setorder(pair_count_daily, -Frequency)
pair_count_daily[, Rank := 1:.N]

### =========================
###  HOURLY PAIRS
### =========================
pairs_hourly <- make_pairs(shipTrans, "DateHour")
pair_count_hourly <- pairs_hourly[, .(Frequency = .N), by = .(Item1, Item2)]
setorder(pair_count_hourly, -Frequency)
pair_count_hourly[, Rank := 1:.N]

### =========================
###  EXACT-TIME PAIRS
### =========================
pairs_exact <- make_pairs(shipTrans, "ExactTime")
pair_count_exact <- pairs_exact[, .(Frequency = .N), by = .(Item1, Item2)]
setorder(pair_count_exact, -Frequency)
pair_count_exact[, Rank := 1:.N]

### =========================
###  OUTPUT
### =========================
cat("\n=== TOP DAILY PAIRS ===\n"); print(pair_count_daily[1:20])
cat("\n=== TOP HOURLY PAIRS ===\n"); print(pair_count_hourly[1:20])
cat("\n=== TOP EXACT-TIME PAIRS ===\n"); print(pair_count_exact[1:20])

fwrite(pair_count_daily,  "SKU_pair_daily.csv")
fwrite(pair_count_hourly, "SKU_pair_hourly.csv")
fwrite(pair_count_exact,  "SKU_pair_exact_time.csv")


