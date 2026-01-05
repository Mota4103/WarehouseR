"""
Q4_Comparison_Simulation.py - Compare Single Order Picking vs FPA Picking

Compares:
1. Before FPA: Single order picking with random storage (long walks, search time)
2. After FPA: Optimized FPA picking (short walks, no search time)

Uses TRIANGULAR DISTRIBUTION for stochastic activity times.
Standard times are read from Activity.csv (GIVEN DATA).
Includes INVENTORY MANAGEMENT with stockouts and replenishment.
"""

import simpy
import pandas as pd
import numpy as np
import random
from collections import defaultdict
import threading

print("=" * 70)
print("    COMPARISON: Single Order Picking vs FPA Picking")
print("    (Using Triangular Distribution)")
print("=" * 70)

# =========================
# LOAD DATA (GIVEN)
# =========================
print("\nLoading GIVEN data...")

pick_lines = pd.read_csv("Simio_OrderPickLines.csv")
sku_params = pd.read_csv("Simio_SKU_Params.csv")
activity_times = pd.read_csv("Activity.csv")

print(f"  - Pick lines: {len(pick_lines):,}")
print(f"  - FPA SKUs: {len(sku_params)}")
print(f"  - Activity times: {len(activity_times)} activities")

# =========================
# INVENTORY MANAGEMENT CLASS (GIVEN: MaxPieces, ReorderPoint, InitialPieces)
# =========================
class InventoryManager:
    """Manages inventory levels for FPA SKUs with stockout tracking"""

    def __init__(self, sku_params_df):
        self.inventory = {}
        self.max_pieces = {}
        self.reorder_point = {}
        self.stockouts = defaultdict(int)  # Count of stockouts per SKU
        self.stockout_qty = defaultdict(int)  # Total qty that couldn't be fulfilled
        self.replenishments = defaultdict(int)  # Count of replenishments per SKU
        self.total_picks = 0
        self.successful_picks = 0
        self.failed_picks = 0

        # Initialize inventory from GIVEN data
        for _, row in sku_params_df.iterrows():
            part_no = row['PartNo']
            self.inventory[part_no] = row['InitialPieces']  # Start at InitialPieces (GIVEN)
            self.max_pieces[part_no] = row['MaxPieces']      # Max capacity (GIVEN)
            self.reorder_point[part_no] = row['ReorderPoint'] # Reorder trigger (GIVEN)

    def check_and_pick(self, part_no, qty):
        """
        Attempt to pick qty items. Returns (success, actual_qty_picked)
        If insufficient stock, records stockout.
        """
        self.total_picks += 1

        if part_no not in self.inventory:
            # SKU not in FPA - assume available (Before FPA scenario)
            self.successful_picks += 1
            return True, qty

        current_stock = self.inventory[part_no]

        if current_stock >= qty:
            # Sufficient stock - fulfill pick
            self.inventory[part_no] -= qty
            self.successful_picks += 1
            return True, qty
        elif current_stock > 0:
            # Partial stock - pick what's available, record partial stockout
            picked = current_stock
            self.inventory[part_no] = 0
            self.stockouts[part_no] += 1
            self.stockout_qty[part_no] += (qty - picked)
            self.failed_picks += 1
            return False, picked
        else:
            # No stock - complete stockout
            self.stockouts[part_no] += 1
            self.stockout_qty[part_no] += qty
            self.failed_picks += 1
            return False, 0

    def needs_replenishment(self, part_no):
        """Check if SKU is at or below reorder point"""
        if part_no not in self.inventory:
            return False
        return self.inventory[part_no] <= self.reorder_point.get(part_no, 0)

    def replenish(self, part_no):
        """Replenish SKU to MaxPieces"""
        if part_no in self.inventory:
            old_qty = self.inventory[part_no]
            self.inventory[part_no] = self.max_pieces[part_no]
            self.replenishments[part_no] += 1
            return self.max_pieces[part_no] - old_qty  # Return qty added
        return 0

    def get_summary(self):
        """Return inventory statistics"""
        total_stockouts = sum(self.stockouts.values())
        total_stockout_qty = sum(self.stockout_qty.values())
        total_replenishments = sum(self.replenishments.values())

        stockout_rate = (self.failed_picks / self.total_picks * 100) if self.total_picks > 0 else 0
        fill_rate = (self.successful_picks / self.total_picks * 100) if self.total_picks > 0 else 100

        return {
            'total_picks': self.total_picks,
            'successful_picks': self.successful_picks,
            'failed_picks': self.failed_picks,
            'stockout_events': total_stockouts,
            'stockout_qty': total_stockout_qty,
            'stockout_rate': stockout_rate,
            'fill_rate': fill_rate,
            'replenishments': total_replenishments,
            'skus_with_stockout': len(self.stockouts)
        }

print(f"\nInventory Parameters (GIVEN from Simio_SKU_Params.csv):")
print(f"  - SKUs with inventory: {len(sku_params)}")
print(f"  - Total MaxPieces: {sku_params['MaxPieces'].sum():,}")
print(f"  - Total InitialPieces: {sku_params['InitialPieces'].sum():,}")
print(f"  - Avg ReorderPoint: {sku_params['ReorderPoint'].mean():.0f} pieces")

# =========================
# EXTRACT ACTIVITY TIMES (GIVEN - Triangular Distribution)
# =========================
print("\nActivity Times from Activity.csv (GIVEN - Triangular Distribution):")
print(f"{'Activity':<25} {'Min':<10} {'Mode':<10} {'Max':<10} {'Unit':<15}")
print("-" * 70)

activity_dict = {}
for _, row in activity_times.iterrows():
    activity_dict[row['Activity']] = {
        'min': row['Min_min'],  # Already in minutes
        'mode': row['Mode_min'],
        'max': row['Max_min'],
        'unit': row['Unit']
    }
    print(f"{row['Activity']:<25} {row['Min_min']:<10.3f} {row['Mode_min']:<10.3f} {row['Max_min']:<10.3f} {'min':<15}")

# Extract specific activities for simulation
SCAN_DIST = (activity_dict['Scan']['min'],
             activity_dict['Scan']['mode'],
             activity_dict['Scan']['max'])

GRASP_BOX_DIST = (activity_dict['Grasp_InnerBox']['min'],
                  activity_dict['Grasp_InnerBox']['mode'],
                  activity_dict['Grasp_InnerBox']['max'])

START_STOP_DIST = (activity_dict['Start_Stop']['min'],
                   activity_dict['Start_Stop']['mode'],
                   activity_dict['Start_Stop']['max'])

STACK_DIST = (activity_dict['Stack_InnerBox']['min'],
              activity_dict['Stack_InnerBox']['mode'],
              activity_dict['Stack_InnerBox']['max'])

# Walk speed from Activity.csv (m/min) - use mode value
WALK_SPEED_DIST = (activity_dict['Walk_Speed']['min'],
                   activity_dict['Walk_Speed']['mode'],
                   activity_dict['Walk_Speed']['max'])
WALK_SPEED = activity_dict['Walk_Speed']['mode']  # 90 m/min (mode)

# =========================
# TRIANGULAR DISTRIBUTION HELPER
# =========================
def triangular(min_val, mode_val, max_val):
    """Generate random value from triangular distribution"""
    return random.triangular(min_val, max_val, mode_val)

# =========================
# SIMULATION PARAMETERS
# =========================
# GIVEN parameters
SIM_DURATION = 480  # 8-hour shift (GIVEN: 9 hours - 1 hour break)
NUM_PICKERS = 40  # Workers per shift (GIVEN from Shift.txt)
EFFECTIVE_FRACTION = 8/9  # GIVEN: 9-hour shift with 1-hour break

# Activity times - DIRECTLY from Activity.csv (GIVEN)
SCAN_TIME_DIST = SCAN_DIST
GRASP_BOX_TIME_DIST = GRASP_BOX_DIST
START_STOP_TIME_DIST = START_STOP_DIST
STACK_TIME_DIST = STACK_DIST

# Combined Check & Pick = Grasp + Stack (from given data)
CHECK_PICK_TIME_DIST = (
    GRASP_BOX_DIST[0] + STACK_DIST[0],  # min
    GRASP_BOX_DIST[1] + STACK_DIST[1],  # mode
    GRASP_BOX_DIST[2] + STACK_DIST[2]   # max
)

# Pick per box uses Grasp time
PICK_PER_BOX_TIME_DIST = GRASP_BOX_DIST

print(f"\nDerived Triangular Distributions (from GIVEN data):")
print(f"  - Scan: Tri({SCAN_TIME_DIST[0]:.3f}, {SCAN_TIME_DIST[1]:.3f}, {SCAN_TIME_DIST[2]:.3f}) min")
print(f"  - Grasp Box: Tri({GRASP_BOX_TIME_DIST[0]:.3f}, {GRASP_BOX_TIME_DIST[1]:.3f}, {GRASP_BOX_TIME_DIST[2]:.3f}) min")
print(f"  - Check & Pick: Tri({CHECK_PICK_TIME_DIST[0]:.3f}, {CHECK_PICK_TIME_DIST[1]:.3f}, {CHECK_PICK_TIME_DIST[2]:.3f}) min")
print(f"  - Walk Speed: Tri({WALK_SPEED_DIST[0]:.1f}, {WALK_SPEED_DIST[1]:.1f}, {WALK_SPEED_DIST[2]:.1f}) m/min")

# =========================
# SCENARIO PARAMETERS
# =========================

# ===== BEFORE FPA (Single Order Picking) =====
# Random storage in 5,332 m² warehouse (GIVEN from warehouse data)
# Search time from Q1 analysis: 2.21 min (59% of total time)

BEFORE_FPA = {
    'name': 'Before FPA (Single Order)',
    # Walking distance: random storage in large warehouse
    # ASSUMPTION: Tri(10, 25, 50) m based on 5,332 m² area
    'walk_distance_dist': (10, 25, 50),
    # Search time from Q1 time study (GIVEN): mode = 2.21 min
    # ASSUMPTION: ±variation for triangular
    'search_time_dist': (2.21 * 0.5, 2.21, 2.21 * 1.8),  # ~(1.1, 2.21, 4.0)
    'check_pick_time_dist': CHECK_PICK_TIME_DIST,
    'scan_time_dist': SCAN_TIME_DIST,
}

# ===== AFTER FPA (Optimized Picking) =====
# Consolidated FPA with distance-based slotting
# Short walks, no search time (known locations)

# Cabinet distances from start point (between Cab 3 and 4)
CABINET_DISTANCES = {
    1: 4.95, 2: 2.97, 3: 0.99, 4: 0.99, 5: 2.97, 6: 4.95,
    7: 7.63, 8: 5.65, 9: 3.67, 10: 3.67, 11: 5.65, 12: 7.63,
    13: 10.99, 14: 9.01, 15: 7.03, 16: 7.03, 17: 9.01, 18: 10.99,
    19: 10.31, 20: 8.33, 21: 6.35, 22: 6.35, 23: 8.33, 24: 10.31
}

# FPA walk distance variation: +/- 20% around cabinet distance
AFTER_FPA = {
    'name': 'After FPA (Optimized)',
    'walk_distance_variation': 0.2,  # +/- 20% variation
    'search_time_dist': (0, 0, 0),  # No search - known fixed locations!
    'check_pick_time_dist': CHECK_PICK_TIME_DIST,
    'scan_time_dist': SCAN_TIME_DIST,
}

print("\n" + "-" * 80)
print("GIVEN vs ASSUMPTIONS")
print("-" * 80)

print("\nGIVEN (from data files):")
print(f"  - Workers per shift: {NUM_PICKERS} (Shift.txt)")
print(f"  - Shift duration: 9 hours, Break: 1 hour → Effective: {SIM_DURATION} min")
print(f"  - Effective fraction: {EFFECTIVE_FRACTION:.4f} (8/9)")
print(f"  - Activity times: from Activity.csv (Triangular Distribution)")
print(f"    * Scan: Tri({SCAN_TIME_DIST[0]:.3f}, {SCAN_TIME_DIST[1]:.3f}, {SCAN_TIME_DIST[2]:.3f}) min")
print(f"    * Grasp Box: Tri({GRASP_BOX_TIME_DIST[0]:.3f}, {GRASP_BOX_TIME_DIST[1]:.3f}, {GRASP_BOX_TIME_DIST[2]:.3f}) min")
print(f"    * Stack: Tri({STACK_TIME_DIST[0]:.3f}, {STACK_TIME_DIST[1]:.3f}, {STACK_TIME_DIST[2]:.3f}) min")
print(f"    * Walk Speed: Tri({WALK_SPEED_DIST[0]:.1f}, {WALK_SPEED_DIST[1]:.1f}, {WALK_SPEED_DIST[2]:.1f}) m/min")
print(f"  - Cabinet distances: from Q3 slotting (0.99m - 10.99m)")
print(f"  - Search time (Before): 2.21 min (Q1 time study - 59% of pick time)")
print(f"  - Arrival times: from order data (DeliveryHour, DeliveryMinute)")
print(f"  - Inventory parameters: from Simio_SKU_Params.csv")
print(f"    * MaxPieces: Maximum inventory per SKU")
print(f"    * ReorderPoint: Trigger for replenishment (MaxPieces/2)")
print(f"    * InitialPieces: Starting inventory (= MaxPieces)")

print("\nASSUMPTIONS:")
print(f"  - Walk distance (Before FPA): Tri(10, 25, 50) m (random in 5,332 m²)")
print(f"  - Search time (After FPA): 0 min (fixed known locations)")
print(f"  - Queue discipline: FIFO")
print(f"  - Replenishment check interval: 30 min")
print(f"  - Replenishment time: Stack time × 5")

print("\n" + "-" * 80)
print("SCENARIO PARAMETERS (Triangular Distribution: min, mode, max)")
print("-" * 80)
print(f"\n{'Parameter':<30} {'Before FPA':<25} {'After FPA':<25} {'Source':<15}")
print("-" * 95)

# Format triangular params
def fmt_tri(dist):
    return f"({dist[0]:.3f}, {dist[1]:.3f}, {dist[2]:.3f})"

print(f"{'Walk Distance (m)':<30} {fmt_tri(BEFORE_FPA['walk_distance_dist']):<25} {'Cabinet ±20%':<25} {'ASSUMPTION':<15}")
print(f"{'Search Time (min)':<30} {fmt_tri(BEFORE_FPA['search_time_dist']):<25} {'0 (None!)':<25} {'Q1/ASSUMPTION':<15}")
print(f"{'Grasp + Stack (min)':<30} {fmt_tri(CHECK_PICK_TIME_DIST):<25} {fmt_tri(CHECK_PICK_TIME_DIST):<25} {'Activity.csv':<15}")
print(f"{'Scan Time (min)':<30} {fmt_tri(SCAN_TIME_DIST):<25} {fmt_tri(SCAN_TIME_DIST):<25} {'Activity.csv':<15}")
print(f"{'Walk Speed (m/min)':<30} {fmt_tri(WALK_SPEED_DIST):<25} {fmt_tri(WALK_SPEED_DIST):<25} {'Activity.csv':<15}")

# Calculate expected (mode) total time per pick
before_walk_mode = BEFORE_FPA['walk_distance_dist'][1]
before_search_mode = BEFORE_FPA['search_time_dist'][1]
walk_speed_mode = WALK_SPEED_DIST[1]  # 90 m/min from Activity.csv

before_total = (2 * before_walk_mode / walk_speed_mode +
                before_search_mode +
                CHECK_PICK_TIME_DIST[1] +
                SCAN_TIME_DIST[1])

avg_cabinet_dist = np.mean(list(CABINET_DISTANCES.values()))
after_total = (2 * avg_cabinet_dist / walk_speed_mode +
               0 +  # No search time
               CHECK_PICK_TIME_DIST[1] +
               SCAN_TIME_DIST[1])

print("-" * 80)
print(f"{'Expected Time/Pick (mode)':<30} {before_total:<25.2f} {after_total:<25.2f}")
print(f"{'Expected Improvement':<30} {'':<25} {(1 - after_total/before_total)*100:.1f}% faster")

# =========================
# PREPARE PICK DATA
# =========================
print("\nPreparing pick data...")

# Merge with SKU params for cabinet info
pick_data = pick_lines.merge(
    sku_params[['PartNo', 'CabinetNo', 'MaxPieces', 'ReorderPoint']],
    on='PartNo', how='left'
)

# Get cabinet distance for FPA
pick_data['CabinetDistance'] = pick_data['Cabinet'].map(CABINET_DISTANCES).fillna(5.7)

# Sample a day's picks
sample_day = pick_data[pick_data['ShippingDay'] == 20110901].copy()
if len(sample_day) < 100:
    sample_day = pick_data.sample(min(3000, len(pick_data)), random_state=42)

print(f"  - Sample picks: {len(sample_day)}")

# =========================
# PRE-GENERATE RANDOM TIMES (for consistency across different picker counts)
# =========================
print("\nPre-generating random service times for consistency...")
random.seed(42)

# Pre-generate all random values for each pick (indexed by row position)
sample_day = sample_day.reset_index(drop=True)

# Before FPA random times
sample_day['rand_walk_dist_before'] = [triangular(BEFORE_FPA['walk_distance_dist'][0],
                                                   BEFORE_FPA['walk_distance_dist'][1],
                                                   BEFORE_FPA['walk_distance_dist'][2])
                                        for _ in range(len(sample_day))]
sample_day['rand_walk_speed_before'] = [triangular(WALK_SPEED_DIST[0], WALK_SPEED_DIST[1], WALK_SPEED_DIST[2])
                                         for _ in range(len(sample_day))]
sample_day['rand_search_before'] = [triangular(BEFORE_FPA['search_time_dist'][0],
                                                BEFORE_FPA['search_time_dist'][1],
                                                BEFORE_FPA['search_time_dist'][2])
                                     for _ in range(len(sample_day))]
sample_day['rand_check_pick'] = [triangular(CHECK_PICK_TIME_DIST[0], CHECK_PICK_TIME_DIST[1], CHECK_PICK_TIME_DIST[2])
                                  for _ in range(len(sample_day))]
sample_day['rand_grasp_box'] = [triangular(GRASP_BOX_TIME_DIST[0], GRASP_BOX_TIME_DIST[1], GRASP_BOX_TIME_DIST[2])
                                 for _ in range(len(sample_day))]
sample_day['rand_scan'] = [triangular(SCAN_TIME_DIST[0], SCAN_TIME_DIST[1], SCAN_TIME_DIST[2])
                            for _ in range(len(sample_day))]

# After FPA random times (walk distance based on cabinet)
sample_day['rand_walk_speed_after'] = [triangular(WALK_SPEED_DIST[0], WALK_SPEED_DIST[1], WALK_SPEED_DIST[2])
                                        for _ in range(len(sample_day))]
variation = AFTER_FPA['walk_distance_variation']
sample_day['rand_walk_dist_after'] = [triangular(row['CabinetDistance'] * (1-variation),
                                                  row['CabinetDistance'],
                                                  row['CabinetDistance'] * (1+variation))
                                       for _, row in sample_day.iterrows()]

print(f"  - Pre-generated random times for {len(sample_day)} picks")

# Calculate EXPECTED service times from pre-generated data (consistent across all picker counts)
sample_day['service_time_before'] = (
    2 * sample_day['rand_walk_dist_before'] / sample_day['rand_walk_speed_before'] +  # Walk time
    sample_day['rand_search_before'] +  # Search time
    sample_day['rand_check_pick'] +  # Check & pick
    sample_day['rand_grasp_box'] * np.ceil(sample_day['ScanQty'] / 10) +  # Box time
    sample_day['rand_scan']  # Scan time
)

sample_day['service_time_after'] = (
    2 * sample_day['rand_walk_dist_after'] / sample_day['rand_walk_speed_after'] +  # Walk time
    0 +  # NO search time for FPA!
    sample_day['rand_check_pick'] +  # Check & pick
    sample_day['rand_grasp_box'] * np.ceil(sample_day['ScanQty'] / 10) +  # Box time
    sample_day['rand_scan']  # Scan time
)

# These are the TRUE average service times (consistent values)
TRUE_AVG_SERVICE_BEFORE = sample_day['service_time_before'].mean()
TRUE_AVG_SERVICE_AFTER = sample_day['service_time_after'].mean()

print(f"\nExpected Service Times (from pre-generated data - CONSISTENT):")
print(f"  - Before FPA: {TRUE_AVG_SERVICE_BEFORE:.3f} min/pick")
print(f"  - After FPA:  {TRUE_AVG_SERVICE_AFTER:.3f} min/pick")
print(f"  - Improvement: {(1 - TRUE_AVG_SERVICE_AFTER/TRUE_AVG_SERVICE_BEFORE)*100:.1f}% faster")

# =========================
# STATISTICS CLASS
# =========================
class Statistics:
    def __init__(self):
        self.picks_completed = 0
        self.picks_attempted = 0
        self.stockouts = 0
        self.total_wait_time = 0
        self.total_service_time = 0
        self.wait_times = []
        self.flow_times = []
        self.service_times = []
        self.queue_lengths = []
        self.utilization_samples = []
        self.inventory_summary = None
        self.stock_wait_times = []  # Time spent waiting for replenishment

# =========================
# SIMULATION PROCESSES
# =========================

def pick_order_before_fpa(env, name, pickers, row, stats):
    """Before FPA: Single order picking with search time (TRIANGULAR DISTRIBUTION from Activity.csv)
       Uses PRE-GENERATED random times for consistency across picker counts.
    """
    arrival_time = env.now

    # Use PRE-GENERATED random times from dataframe (for consistency)
    walk_distance = row['rand_walk_dist_before']
    walk_speed = row['rand_walk_speed_before']
    walk_time = 2 * walk_distance / walk_speed  # Round trip

    search_time = row['rand_search_before']

    # Pick times - use pre-generated values
    check_pick_time = row['rand_check_pick']
    box_time = row['rand_grasp_box']
    scan_time = row['rand_scan']

    pick_time = check_pick_time + box_time * np.ceil(row['ScanQty'] / 10) + scan_time

    total_service = walk_time + search_time + pick_time

    with pickers.request() as request:
        yield request
        wait_time = env.now - arrival_time
        stats.wait_times.append(wait_time)

        # Perform all activities
        yield env.timeout(total_service)
        stats.service_times.append(total_service)

        # Record completion
        flow_time = env.now - arrival_time
        stats.flow_times.append(flow_time)
        stats.picks_completed += 1


def pick_order_after_fpa(env, name, pickers, row, stats, inventory_mgr=None):
    """After FPA: Optimized picking with no search time (TRIANGULAR DISTRIBUTION from Activity.csv)
       Now includes inventory management with stockout tracking.
       If stockout occurs, picker WAITS for replenishment.
       Uses PRE-GENERATED random times for consistency across picker counts.
    """
    arrival_time = env.now
    stats.picks_attempted += 1

    # Check inventory availability (GIVEN: MaxPieces, ReorderPoint)
    part_no = row['PartNo']
    qty_requested = row['ScanQty']

    if inventory_mgr:
        # Keep trying until inventory is available (wait for replenishment)
        wait_for_stock_start = env.now
        had_stockout = False

        while True:
            success, qty_picked = inventory_mgr.check_and_pick(part_no, qty_requested)
            if success:
                break  # Got the stock, proceed with pick
            else:
                # Stockout - wait for replenishment (only count once per pick)
                if not had_stockout:
                    stats.stockouts += 1
                    had_stockout = True
                # Wait a short time then check again (replenishment will refill)
                yield env.timeout(1)  # Check every 1 minute

                # Safety: if waited too long (beyond simulation), break
                if env.now >= SIM_DURATION:
                    return

        # Record wait time for stock (only if had to wait)
        stock_wait_time = env.now - wait_for_stock_start
        if stock_wait_time > 0:
            stats.stock_wait_times.append(stock_wait_time)

    # Use PRE-GENERATED random times from dataframe (for consistency)
    walk_distance = row['rand_walk_dist_after']
    walk_speed = row['rand_walk_speed_after']
    walk_time = 2 * walk_distance / walk_speed  # Round trip

    # No search time for FPA!
    search_time = 0

    # Pick times - use pre-generated values
    check_pick_time = row['rand_check_pick']
    box_time = row['rand_grasp_box']
    scan_time = row['rand_scan']

    pick_time = check_pick_time + box_time * np.ceil(qty_requested / 10) + scan_time

    total_service = walk_time + search_time + pick_time

    with pickers.request() as request:
        yield request
        wait_time = env.now - arrival_time
        stats.wait_times.append(wait_time)

        # Perform all activities
        yield env.timeout(total_service)
        stats.service_times.append(total_service)

        # Record completion
        flow_time = env.now - arrival_time
        stats.flow_times.append(flow_time)
        stats.picks_completed += 1


def order_generator(env, pickers, pick_data, stats, scenario='after', inventory_mgr=None):
    """Generate pick orders based on ACTUAL arrival times from order data"""

    # Sort by actual arrival time
    pick_data_sorted = pick_data.sort_values(['DeliveryHour', 'DeliveryMinute']).reset_index(drop=True)

    # Get the start time (first order's arrival)
    first_hour = pick_data_sorted['DeliveryHour'].iloc[0]
    first_minute = pick_data_sorted['DeliveryMinute'].iloc[0]
    start_time_min = first_hour * 60 + first_minute

    prev_arrival = 0

    for idx, row in pick_data_sorted.iterrows():
        # Calculate actual arrival time in minutes from start of simulation
        arrival_hour = row['DeliveryHour']
        arrival_minute = row['DeliveryMinute']
        arrival_time_min = (arrival_hour * 60 + arrival_minute) - start_time_min

        # Ensure arrival time is within simulation duration
        if arrival_time_min >= SIM_DURATION:
            break

        # Wait until this order's actual arrival time
        wait_until = max(0, arrival_time_min - prev_arrival)
        if wait_until > 0:
            yield env.timeout(wait_until)
        prev_arrival = arrival_time_min

        # Create pick order process
        if scenario == 'before':
            env.process(pick_order_before_fpa(env, f"Pick_{idx}", pickers, row, stats))
        else:
            env.process(pick_order_after_fpa(env, f"Pick_{idx}", pickers, row, stats, inventory_mgr))


def replenishment_process(env, inventory_mgr, replenish_time_dist, stats):
    """
    Replenishment process that checks SKUs and replenishes when at ReorderPoint.
    Runs periodically during simulation.
    GIVEN: ReorderPoint triggers replenishment to MaxPieces
    """
    check_interval = 30  # Check every 30 minutes

    while True:
        yield env.timeout(check_interval)

        # Check all SKUs for replenishment needs
        for part_no in list(inventory_mgr.inventory.keys()):
            if inventory_mgr.needs_replenishment(part_no):
                # Replenish to MaxPieces (GIVEN)
                qty_added = inventory_mgr.replenish(part_no)
                # Replenishment takes time (triangular distribution)
                replenish_time = triangular(replenish_time_dist[0], replenish_time_dist[1], replenish_time_dist[2])
                yield env.timeout(replenish_time)


def monitor(env, pickers, stats, interval=10):
    """Monitor resource utilization"""
    while True:
        stats.queue_lengths.append(len(pickers.queue))
        stats.utilization_samples.append(pickers.count / pickers.capacity)
        yield env.timeout(interval)


def run_simulation(scenario_params, pick_data, n_pickers, scenario='after', sku_params_df=None):
    """Run simulation for a scenario with optional inventory management"""
    stats = Statistics()
    random.seed(42)
    env = simpy.Environment()
    pickers = simpy.Resource(env, capacity=n_pickers)

    # Create inventory manager for After FPA scenario (tracks stockouts)
    inventory_mgr = None
    if scenario == 'after' and sku_params_df is not None:
        inventory_mgr = InventoryManager(sku_params_df)
        # Replenishment time: use Stack_InnerBox time × 5 as estimate (ASSUMPTION)
        replenish_time_dist = (STACK_TIME_DIST[0] * 5, STACK_TIME_DIST[1] * 5, STACK_TIME_DIST[2] * 5)
        env.process(replenishment_process(env, inventory_mgr, replenish_time_dist, stats))

    env.process(order_generator(env, pickers, pick_data, stats, scenario, inventory_mgr))
    env.process(monitor(env, pickers, stats))
    env.run(until=SIM_DURATION)

    # Store inventory summary
    if inventory_mgr:
        stats.inventory_summary = inventory_mgr.get_summary()

    hours = SIM_DURATION / 60
    effective_pickers = n_pickers * (8/9)  # Account for break time

    # Calculate metrics
    avg_service_simulated = np.mean(stats.service_times) if stats.service_times else 1
    total_service_time = sum(stats.service_times) if stats.service_times else 0

    # Use TRUE (pre-calculated) average service time for theoretical metrics
    # This ensures consistency across different picker counts
    if scenario == 'before':
        true_avg_service = TRUE_AVG_SERVICE_BEFORE
    else:
        true_avg_service = TRUE_AVG_SERVICE_AFTER

    # ACTUAL LPMH = Picks completed / (Effective pickers × Hours)
    # This measures productivity per worker
    actual_lpmh = stats.picks_completed / (effective_pickers * hours)

    # UTILIZATION = Total busy time / Total available time
    # Total busy time = sum of all service times (work done)
    # Total available time = Number of pickers × Simulation duration
    # Note: Each pick uses ONE picker for its service time
    utilization_calculated = (total_service_time / (n_pickers * SIM_DURATION)) * 100

    # THROUGHPUT = Picks per hour (system-level)
    throughput = stats.picks_completed / hours

    # THEORETICAL CAPACITY = Max picks if all pickers work at 100%
    # = (Pickers × Duration) / TRUE Avg Service Time (consistent!)
    theoretical_capacity = (n_pickers * SIM_DURATION) / true_avg_service

    # THEORETICAL LPMH at 100% utilization = 60 / TRUE Avg Service Time
    # This is a process metric (same regardless of picker count - NOW CONSISTENT!)
    theoretical_lpmh = 60 / true_avg_service

    # Inventory metrics
    inv_summary = stats.inventory_summary or {}

    # Stock wait time (time waiting for replenishment)
    avg_stock_wait = np.mean(stats.stock_wait_times) if stats.stock_wait_times else 0
    total_stock_wait = sum(stats.stock_wait_times) if stats.stock_wait_times else 0

    return {
        'Scenario': scenario_params['name'],
        'Pickers': n_pickers,
        'EffectivePickers': effective_pickers,
        'Picks': stats.picks_completed,
        'PicksAttempted': stats.picks_attempted,
        'Stockouts': stats.stockouts,
        'LPMH': actual_lpmh,
        'Throughput': throughput,
        'TheoreticalLPMH': theoretical_lpmh,
        'TheoreticalCapacity': theoretical_capacity,
        'AvgWait': np.mean(stats.wait_times) if stats.wait_times else 0,
        'AvgFlow': np.mean(stats.flow_times) if stats.flow_times else 0,
        'AvgService': true_avg_service,  # Use TRUE avg service (consistent!)
        'AvgServiceSimulated': avg_service_simulated,  # Simulated value (may vary)
        'TotalServiceTime': total_service_time,
        'Utilization': utilization_calculated,
        'UtilizationMonitor': np.mean(stats.utilization_samples) * 100 if stats.utilization_samples else 0,
        # Inventory metrics
        'FillRate': inv_summary.get('fill_rate', 100),
        'StockoutRate': inv_summary.get('stockout_rate', 0),
        'StockoutEvents': inv_summary.get('stockout_events', 0),
        'StockoutQty': inv_summary.get('stockout_qty', 0),
        'Replenishments': inv_summary.get('replenishments', 0),
        # Wait for stock metrics
        'AvgStockWait': avg_stock_wait,
        'TotalStockWait': total_stock_wait,
        'StockWaitCount': len(stats.stock_wait_times)
    }

# =========================
# RUN COMPARISON
# =========================
print("\n" + "=" * 70)
print("RUNNING SIMULATIONS")
print("=" * 70)

# Run both scenarios with 40 pickers
print("\nRunning Before FPA simulation...")
before_result = run_simulation(BEFORE_FPA, sample_day, NUM_PICKERS, 'before', sku_params)
print(f"  Completed: {before_result['Picks']} picks, LPMH = {before_result['LPMH']:.2f}")

print("\nRunning After FPA simulation (with inventory tracking)...")
after_result = run_simulation(AFTER_FPA, sample_day, NUM_PICKERS, 'after', sku_params)
print(f"  Completed: {after_result['Picks']} picks, LPMH = {after_result['LPMH']:.2f}")
print(f"  Stockouts: {after_result['Stockouts']}, Fill Rate: {after_result['FillRate']:.1f}%")

# =========================
# COMPARISON RESULTS
# =========================
print("\n" + "=" * 70)
print("COMPARISON RESULTS (40 Pickers)")
print("=" * 70)

service_improvement = (1 - after_result['AvgService'] / before_result['AvgService']) * 100
theoretical_improvement = ((after_result['TheoreticalLPMH'] / before_result['TheoreticalLPMH']) - 1) * 100

print(f"\n{'Metric':<35} {'Before FPA':<18} {'After FPA':<18} {'Change':<15}")
print("-" * 90)
print(f"{'Avg Service Time (min)':<35} {before_result['AvgService']:<18.2f} {after_result['AvgService']:<18.2f} {service_improvement:.1f}% faster")
print(f"{'Total Service Time (min)':<35} {before_result['TotalServiceTime']:<18.1f} {after_result['TotalServiceTime']:<18.1f} {service_improvement:.1f}% less")
print(f"{'Utilization (%)':<35} {before_result['Utilization']:<18.1f} {after_result['Utilization']:<18.1f} {after_result['Utilization']-before_result['Utilization']:.1f}%")
print(f"{'Actual LPMH':<35} {before_result['LPMH']:<18.2f} {after_result['LPMH']:<18.2f} {'(same picks)':<15}")
print(f"{'Throughput (picks/hour)':<35} {before_result['Throughput']:<18.1f} {after_result['Throughput']:<18.1f} {'(demand-limited)':<15}")

print("\n" + "-" * 90)
print("INVENTORY METRICS (After FPA with MaxPieces, ReorderPoint from GIVEN data):")
print("-" * 90)
print(f"{'Fill Rate (%)':<35} {'N/A':<18} {after_result['FillRate']:<18.1f} {'(picks fulfilled)':<15}")
print(f"{'Stockout Events':<35} {'N/A':<18} {after_result['Stockouts']:<18} {'(had to wait)':<15}")
print(f"{'Avg Wait for Stock (min)':<35} {'N/A':<18} {after_result['AvgStockWait']:<18.2f} {'(wait time)':<15}")
print(f"{'Total Wait for Stock (min)':<35} {'N/A':<18} {after_result['TotalStockWait']:<18.1f} {'(total delay)':<15}")
print(f"{'Replenishments':<35} {'N/A':<18} {after_result['Replenishments']:<18} {'(at ReorderPt)':<15}")

print("\n" + "-" * 90)
print("CAPACITY METRICS (what COULD be achieved at 100% utilization):")
print("-" * 90)
print(f"{'Theoretical LPMH (100% util.)':<35} {before_result['TheoreticalLPMH']:<18.2f} {after_result['TheoreticalLPMH']:<18.2f} {theoretical_improvement:+.1f}%")
print(f"{'Max Capacity/Day (picks)':<35} {before_result['TheoreticalCapacity']:<18.0f} {after_result['TheoreticalCapacity']:<18.0f} {theoretical_improvement:+.1f}%")

print("\n" + "-" * 90)
print("METRIC CALCULATIONS:")
print("-" * 90)
print(f"""
  Utilization = Total Service Time / (Pickers × Simulation Duration)
              = {before_result['TotalServiceTime']:.1f} / ({NUM_PICKERS} × {SIM_DURATION})
              = {before_result['TotalServiceTime']:.1f} / {NUM_PICKERS * SIM_DURATION}
              = {before_result['Utilization']:.1f}% (Before FPA)

  Theoretical LPMH = 60 min / Avg Service Time
                   = 60 / {after_result['AvgService']:.2f}
                   = {after_result['TheoreticalLPMH']:.2f} picks/picker/hour (After FPA)

  Actual LPMH = Picks Completed / (Effective Pickers × Hours)
              = {after_result['Picks']} / ({after_result['EffectivePickers']:.2f} × {SIM_DURATION/60:.0f})
              = {after_result['LPMH']:.2f} (After FPA)
""")

# =========================
# SENSITIVITY ANALYSIS
# =========================
print("\n" + "=" * 70)
print("SENSITIVITY ANALYSIS: Number of Pickers")
print("=" * 70)

picker_counts = [20, 30, 40, 50, 60]
comparison_results = []

print(f"\n{'Pickers':<10} {'Before Util%':<14} {'After Util%':<14} {'Stockouts':<12} {'Avg Wait(min)':<14} {'Capacity Gain':<15}")
print("-" * 95)

for n_pickers in picker_counts:
    before = run_simulation(BEFORE_FPA, sample_day, n_pickers, 'before', sku_params)
    after = run_simulation(AFTER_FPA, sample_day, n_pickers, 'after', sku_params)

    capacity_gain = ((after['TheoreticalCapacity'] / before['TheoreticalCapacity']) - 1) * 100
    service_diff = (1 - after['AvgService'] / before['AvgService']) * 100

    print(f"{n_pickers:<10} {before['Utilization']:<14.1f} {after['Utilization']:<14.1f} {after['Stockouts']:<12} {after['AvgStockWait']:<14.2f} +{capacity_gain:.0f}%")

    comparison_results.append({
        'Pickers': n_pickers,
        'EffectivePickers': n_pickers * (8/9),
        'Before_Utilization': before['Utilization'],
        'After_Utilization': after['Utilization'],
        'Before_LPMH': before['LPMH'],
        'After_LPMH': after['LPMH'],
        'Before_AvgService': before['AvgService'],
        'After_AvgService': after['AvgService'],
        'Before_Capacity': before['TheoreticalCapacity'],
        'After_Capacity': after['TheoreticalCapacity'],
        'Before_TheoreticalLPMH': before['TheoreticalLPMH'],
        'After_TheoreticalLPMH': after['TheoreticalLPMH'],
        'ServiceTime_Reduction_Pct': service_diff,
        'Capacity_Gain_Pct': capacity_gain,
        # Inventory metrics (After FPA only)
        'After_FillRate': after['FillRate'],
        'After_Stockouts': after['Stockouts'],
        'After_AvgStockWait': after['AvgStockWait'],
        'After_TotalStockWait': after['TotalStockWait'],
        'After_Replenishments': after['Replenishments']
    })

print("\nNote: Utilization = Total Service Time / (Pickers × Duration)")
print("      LPMH = Picks / (Effective Pickers × Hours)")
print("      Capacity Gain = how much MORE picks can be handled with FPA")
print("      Fill Rate = % of picks successfully fulfilled (GIVEN inventory)")
print("      Stockouts = picks that couldn't be fulfilled due to insufficient stock")

# Save results
results_df = pd.DataFrame(comparison_results)
results_df.to_csv("Q4_comparison_results.csv", index=False)
print(f"\n  Saved: Q4_comparison_results.csv")

# =========================
# VISUALIZATION
# =========================
print("\nCreating visualizations...")

try:
    import matplotlib.pyplot as plt

    # 1. Utilization Comparison Chart
    fig, ax = plt.subplots(figsize=(12, 6))

    x = np.arange(len(picker_counts))
    width = 0.35

    bars1 = ax.bar(x - width/2, results_df['Before_Utilization'], width,
                   label='Before FPA (Single Order)', color='coral', edgecolor='darkred')
    bars2 = ax.bar(x + width/2, results_df['After_Utilization'], width,
                   label='After FPA (Optimized)', color='steelblue', edgecolor='darkblue')

    ax.set_xlabel('Number of Pickers', fontsize=12)
    ax.set_ylabel('Utilization (%)', fontsize=12)
    ax.set_title('Picker Utilization: Before vs After FPA\n(Lower utilization with FPA = same work done faster)', fontsize=14)
    ax.set_xticks(x)
    ax.set_xticklabels(picker_counts)
    ax.legend()
    ax.grid(axis='y', alpha=0.3)

    # Add value labels on bars
    for bar in bars1:
        height = bar.get_height()
        ax.annotate(f'{height:.1f}%',
                   xy=(bar.get_x() + bar.get_width() / 2, height),
                   xytext=(0, 3), textcoords="offset points",
                   ha='center', va='bottom', fontsize=9)

    for bar in bars2:
        height = bar.get_height()
        ax.annotate(f'{height:.1f}%',
                   xy=(bar.get_x() + bar.get_width() / 2, height),
                   xytext=(0, 3), textcoords="offset points",
                   ha='center', va='bottom', fontsize=9)

    plt.tight_layout()
    plt.savefig('Q4_comparison_utilization.png', dpi=150)
    plt.close()
    print("  - Saved: Q4_comparison_utilization.png")

    # 2. Service Time Comparison
    fig, ax = plt.subplots(figsize=(10, 6))

    bars1 = ax.bar(x - width/2, results_df['Before_AvgService'], width,
                   label='Before FPA', color='coral', edgecolor='darkred')
    bars2 = ax.bar(x + width/2, results_df['After_AvgService'], width,
                   label='After FPA', color='steelblue', edgecolor='darkblue')

    ax.set_xlabel('Number of Pickers', fontsize=12)
    ax.set_ylabel('Average Service Time (minutes)', fontsize=12)
    ax.set_title('Service Time Comparison: Time per Pick', fontsize=14)
    ax.set_xticks(x)
    ax.set_xticklabels(picker_counts)
    ax.legend()
    ax.grid(axis='y', alpha=0.3)

    plt.tight_layout()
    plt.savefig('Q4_comparison_service.png', dpi=150)
    plt.close()
    print("  - Saved: Q4_comparison_service.png")

    # 3. Time Breakdown Pie Charts (using MODE values from triangular distribution)
    fig, axes = plt.subplots(1, 2, figsize=(14, 6))

    # Before FPA breakdown (mode values)
    before_walk_mode = BEFORE_FPA['walk_distance_dist'][1]  # mode = 25m
    before_search_mode = BEFORE_FPA['search_time_dist'][1]  # mode = 2.21 min
    before_walk_time = 2 * before_walk_mode / WALK_SPEED
    before_times = [before_walk_time, before_search_mode,
                    CHECK_PICK_TIME_DIST[1], SCAN_TIME_DIST[1] + PICK_PER_BOX_TIME_DIST[1]]
    before_labels = ['Walking\n{:.2f} min'.format(before_walk_time),
                     'Search\n{:.2f} min'.format(before_search_mode),
                     'Check & Pick\n{:.2f} min'.format(CHECK_PICK_TIME_DIST[1]),
                     'Scan + Box\n{:.2f} min'.format(SCAN_TIME_DIST[1] + PICK_PER_BOX_TIME_DIST[1])]
    colors_before = ['#ff9999', '#ff6666', '#ff3333', '#cc0000']

    axes[0].pie(before_times, labels=before_labels, colors=colors_before,
                autopct='%1.0f%%', startangle=90)
    axes[0].set_title('Before FPA: Time Breakdown per Pick (Mode Values)\n(Total: {:.2f} min)'.format(sum(before_times)),
                      fontsize=12)

    # After FPA breakdown (mode values)
    after_walk_time = 2 * avg_cabinet_dist / WALK_SPEED
    after_times_filtered = [after_walk_time, CHECK_PICK_TIME_DIST[1],
                            SCAN_TIME_DIST[1] + PICK_PER_BOX_TIME_DIST[1]]
    after_labels_filtered = ['Walking\n{:.2f} min'.format(after_walk_time),
                             'Check & Pick\n{:.2f} min'.format(CHECK_PICK_TIME_DIST[1]),
                             'Scan + Box\n{:.2f} min'.format(SCAN_TIME_DIST[1] + PICK_PER_BOX_TIME_DIST[1])]
    colors_after_filtered = ['#99ccff', '#3366ff', '#0033cc']

    axes[1].pie(after_times_filtered, labels=after_labels_filtered,
                colors=colors_after_filtered,
                autopct='%1.0f%%', startangle=90)
    axes[1].set_title('After FPA: Time Breakdown per Pick (Mode Values)\n(Total: {:.2f} min, No Search!)'.format(
        sum(after_times_filtered)), fontsize=12)

    plt.tight_layout()
    plt.savefig('Q4_comparison_breakdown.png', dpi=150)
    plt.close()
    print("  - Saved: Q4_comparison_breakdown.png")

    # 4. Capacity Comparison Chart
    fig, ax = plt.subplots(figsize=(12, 6))

    x = np.arange(len(picker_counts))
    width = 0.35

    bars1 = ax.bar(x - width/2, results_df['Before_Capacity'], width,
                   label='Before FPA', color='coral', edgecolor='darkred')
    bars2 = ax.bar(x + width/2, results_df['After_Capacity'], width,
                   label='After FPA', color='steelblue', edgecolor='darkblue')

    ax.set_xlabel('Number of Pickers', fontsize=12)
    ax.set_ylabel('Maximum Capacity (picks/day)', fontsize=12)
    ax.set_title('Theoretical Maximum Capacity: Before vs After FPA\n(How many picks COULD be handled at 100% utilization)', fontsize=14)
    ax.set_xticks(x)
    ax.set_xticklabels(picker_counts)
    ax.legend()
    ax.grid(axis='y', alpha=0.3)

    # Add capacity gain labels
    for i, (b1, b2) in enumerate(zip(bars1, bars2)):
        gain = (results_df['After_Capacity'].iloc[i] / results_df['Before_Capacity'].iloc[i] - 1) * 100
        mid_x = (b1.get_x() + b2.get_x() + b2.get_width()) / 2
        max_height = max(b1.get_height(), b2.get_height())
        ax.annotate(f'+{gain:.0f}%',
                   xy=(mid_x, max_height),
                   xytext=(0, 10), textcoords="offset points",
                   ha='center', va='bottom', fontsize=10, fontweight='bold', color='green')

    plt.tight_layout()
    plt.savefig('Q4_comparison_capacity.png', dpi=150)
    plt.close()
    print("  - Saved: Q4_comparison_capacity.png")

except ImportError:
    print("  - matplotlib not available, skipping plots")

# =========================
# SUMMARY
# =========================
print("\n" + "=" * 70)
print("SUMMARY: FPA IMPLEMENTATION BENEFITS")
print("=" * 70)

service_reduction = results_df['ServiceTime_Reduction_Pct'].mean()
capacity_gain = results_df['Capacity_Gain_Pct'].mean()

before_walk_mode = BEFORE_FPA['walk_distance_dist'][1]
before_search_mode = BEFORE_FPA['search_time_dist'][1]

before_avg_service = results_df['Before_AvgService'].mean()
after_avg_service = results_df['After_AvgService'].mean()
before_theoretical_lpmh = results_df['Before_TheoreticalLPMH'].mean()
after_theoretical_lpmh = results_df['After_TheoreticalLPMH'].mean()

print(f"""
KEY FINDINGS (Triangular Distribution Simulation):

1. SERVICE TIME IMPROVEMENT
   - Before FPA: {before_avg_service:.2f} min/pick
   - After FPA:  {after_avg_service:.2f} min/pick
   - Reduction:  {service_reduction:.0f}%

2. CAPACITY IMPROVEMENT
   - Theoretical LPMH (Before): {before_theoretical_lpmh:.2f} picks/picker/hour
   - Theoretical LPMH (After):  {after_theoretical_lpmh:.2f} picks/picker/hour
   - Capacity Gain: +{capacity_gain:.0f}%

3. UTILIZATION IMPACT
   - Same workload requires {service_reduction:.0f}% less total work time
   - Utilization drops from ~{results_df['Before_Utilization'].mean():.1f}% to ~{results_df['After_Utilization'].mean():.1f}%

4. ROOT CAUSE ADDRESSED
   - Before: Search time = {before_search_mode:.2f} min (69% of pick time)
   - After:  Search time = 0 (eliminated with fixed locations)

5. TRIANGULAR DISTRIBUTION PARAMETERS
   - Walk Distance (Before): Tri({BEFORE_FPA['walk_distance_dist'][0]}, {BEFORE_FPA['walk_distance_dist'][1]}, {BEFORE_FPA['walk_distance_dist'][2]}) m
   - Search Time (Before):   Tri({BEFORE_FPA['search_time_dist'][0]}, {BEFORE_FPA['search_time_dist'][1]}, {BEFORE_FPA['search_time_dist'][2]}) min
   - Walk Distance (After):  Cabinet distance +/- 20%
   - Search Time (After):    0 min

METRIC FORMULAS:
   Utilization = Total Service Time / (Pickers × Duration)
   Theoretical LPMH = 60 / Avg Service Time  [picks/picker/hour at 100% util]
   Actual LPMH = Picks Completed / (Effective Pickers × Hours)
   Capacity = (Pickers × Duration) / Avg Service Time
""")

print("=" * 70)
print("Simulation Complete")
print("=" * 70)
