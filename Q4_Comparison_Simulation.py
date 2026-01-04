"""
Q4_Comparison_Simulation.py - Compare Single Order Picking vs FPA Picking

Compares:
1. Before FPA: Single order picking with random storage (long walks, search time)
2. After FPA: Optimized FPA picking (short walks, no search time)

Uses TRIANGULAR DISTRIBUTION for stochastic activity times.
"""

import simpy
import pandas as pd
import numpy as np
import random
from collections import defaultdict

print("=" * 70)
print("    COMPARISON: Single Order Picking vs FPA Picking")
print("    (Using Triangular Distribution)")
print("=" * 70)

# =========================
# LOAD DATA
# =========================
print("\nLoading data...")

pick_lines = pd.read_csv("Simio_OrderPickLines.csv")
sku_params = pd.read_csv("Simio_SKU_Params.csv")

print(f"  - Pick lines: {len(pick_lines):,}")
print(f"  - FPA SKUs: {len(sku_params)}")

# =========================
# TRIANGULAR DISTRIBUTION HELPER
# =========================
def triangular(min_val, mode_val, max_val):
    """Generate random value from triangular distribution"""
    return random.triangular(min_val, max_val, mode_val)

# =========================
# SIMULATION PARAMETERS (with Triangular Distribution)
# =========================
# Format: (min, mode, max)

# Common parameters
WALK_SPEED = 100  # meters per minute (fixed)
SIM_DURATION = 480  # 8-hour shift
NUM_PICKERS = 40  # Workers per shift (effective = 40 * 8/9 = 35.56)

# Activity times with triangular distribution (min, mode, max) in minutes
CHECK_PICK_TIME_DIST = (0.3, 0.4, 0.6)  # Check location and pick
PICK_PER_BOX_TIME_DIST = (0.08, 0.1, 0.15)  # Per box time
SCAN_TIME_DIST = (0.05, 0.083, 0.12)  # Barcode scanning

# ===== BEFORE FPA (Single Order Picking) =====
# Random storage in 5,332 m² warehouse
# Long walks + search time dominates (59% of total time)

BEFORE_FPA = {
    'name': 'Before FPA (Single Order)',
    # Walking distance triangular (one-way): min=10m, mode=25m, max=50m
    'walk_distance_dist': (10, 25, 50),
    # Search time triangular: min=1.0, mode=2.21, max=4.0 min
    'search_time_dist': (1.0, 2.21, 4.0),
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

print("\n" + "-" * 70)
print("SCENARIO PARAMETERS (Triangular Distribution: min, mode, max)")
print("-" * 70)
print(f"\n{'Parameter':<30} {'Before FPA':<25} {'After FPA':<25}")
print("-" * 80)

# Format triangular params
def fmt_tri(dist):
    return f"({dist[0]:.2f}, {dist[1]:.2f}, {dist[2]:.2f})"

print(f"{'Walk Distance (m)':<30} {fmt_tri(BEFORE_FPA['walk_distance_dist']):<25} {'Cabinet-based +/-20%':<25}")
print(f"{'Search Time (min)':<30} {fmt_tri(BEFORE_FPA['search_time_dist']):<25} {'(0, 0, 0) - None!':<25}")
print(f"{'Check & Pick Time (min)':<30} {fmt_tri(CHECK_PICK_TIME_DIST):<25} {fmt_tri(CHECK_PICK_TIME_DIST):<25}")
print(f"{'Scan Time (min)':<30} {fmt_tri(SCAN_TIME_DIST):<25} {fmt_tri(SCAN_TIME_DIST):<25}")

# Calculate expected (mode) total time per pick
before_walk_mode = BEFORE_FPA['walk_distance_dist'][1]
before_search_mode = BEFORE_FPA['search_time_dist'][1]
before_total = (2 * before_walk_mode / WALK_SPEED +
                before_search_mode +
                CHECK_PICK_TIME_DIST[1] +
                SCAN_TIME_DIST[1])

avg_cabinet_dist = np.mean(list(CABINET_DISTANCES.values()))
after_total = (2 * avg_cabinet_dist / WALK_SPEED +
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
# STATISTICS CLASS
# =========================
class Statistics:
    def __init__(self):
        self.picks_completed = 0
        self.total_wait_time = 0
        self.total_service_time = 0
        self.wait_times = []
        self.flow_times = []
        self.service_times = []
        self.queue_lengths = []
        self.utilization_samples = []

# =========================
# SIMULATION PROCESSES
# =========================

def pick_order_before_fpa(env, name, pickers, row, stats):
    """Before FPA: Single order picking with search time (TRIANGULAR DISTRIBUTION)"""
    arrival_time = env.now

    # Generate times from TRIANGULAR distributions
    walk_dist = BEFORE_FPA['walk_distance_dist']
    walk_distance = triangular(walk_dist[0], walk_dist[1], walk_dist[2])
    walk_time = 2 * walk_distance / WALK_SPEED  # Round trip

    search_dist = BEFORE_FPA['search_time_dist']
    search_time = triangular(search_dist[0], search_dist[1], search_dist[2])

    check_pick_time = triangular(CHECK_PICK_TIME_DIST[0], CHECK_PICK_TIME_DIST[1], CHECK_PICK_TIME_DIST[2])
    box_time = triangular(PICK_PER_BOX_TIME_DIST[0], PICK_PER_BOX_TIME_DIST[1], PICK_PER_BOX_TIME_DIST[2])
    scan_time = triangular(SCAN_TIME_DIST[0], SCAN_TIME_DIST[1], SCAN_TIME_DIST[2])

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


def pick_order_after_fpa(env, name, pickers, row, stats):
    """After FPA: Optimized picking with no search time (TRIANGULAR DISTRIBUTION)"""
    arrival_time = env.now

    # Calculate walk time with triangular variation around cabinet distance
    cabinet_distance = row['CabinetDistance']
    variation = AFTER_FPA['walk_distance_variation']
    walk_distance = triangular(
        cabinet_distance * (1 - variation),  # min
        cabinet_distance,                      # mode
        cabinet_distance * (1 + variation)   # max
    )
    walk_time = 2 * walk_distance / WALK_SPEED  # Round trip

    # No search time for FPA!
    search_time = 0

    # Generate pick times from triangular distributions
    check_pick_time = triangular(CHECK_PICK_TIME_DIST[0], CHECK_PICK_TIME_DIST[1], CHECK_PICK_TIME_DIST[2])
    box_time = triangular(PICK_PER_BOX_TIME_DIST[0], PICK_PER_BOX_TIME_DIST[1], PICK_PER_BOX_TIME_DIST[2])
    scan_time = triangular(SCAN_TIME_DIST[0], SCAN_TIME_DIST[1], SCAN_TIME_DIST[2])

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


def order_generator(env, pickers, pick_data, stats, scenario='after'):
    """Generate pick orders based on data"""
    avg_interarrival = SIM_DURATION / len(pick_data)

    for idx, row in pick_data.iterrows():
        if scenario == 'before':
            env.process(pick_order_before_fpa(env, f"Pick_{idx}", pickers, row, stats))
        else:
            env.process(pick_order_after_fpa(env, f"Pick_{idx}", pickers, row, stats))

        yield env.timeout(random.expovariate(1 / avg_interarrival))


def monitor(env, pickers, stats, interval=10):
    """Monitor resource utilization"""
    while True:
        stats.queue_lengths.append(len(pickers.queue))
        stats.utilization_samples.append(pickers.count / pickers.capacity)
        yield env.timeout(interval)


def run_simulation(scenario_params, pick_data, n_pickers, scenario='after'):
    """Run simulation for a scenario"""
    stats = Statistics()
    random.seed(42)
    env = simpy.Environment()
    pickers = simpy.Resource(env, capacity=n_pickers)

    env.process(order_generator(env, pickers, pick_data, stats, scenario))
    env.process(monitor(env, pickers, stats))
    env.run(until=SIM_DURATION)

    hours = SIM_DURATION / 60
    effective_pickers = n_pickers * (8/9)  # Account for break time

    # Calculate metrics
    avg_service = np.mean(stats.service_times) if stats.service_times else 1
    total_service_time = sum(stats.service_times) if stats.service_times else 0

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
    # = (Pickers × Duration) / Avg Service Time
    theoretical_capacity = (n_pickers * SIM_DURATION) / avg_service

    # THEORETICAL LPMH at 100% utilization = 60 / Avg Service Time
    # This is a process metric (same regardless of picker count)
    theoretical_lpmh = 60 / avg_service

    return {
        'Scenario': scenario_params['name'],
        'Pickers': n_pickers,
        'EffectivePickers': effective_pickers,
        'Picks': stats.picks_completed,
        'LPMH': actual_lpmh,
        'Throughput': throughput,
        'TheoreticalLPMH': theoretical_lpmh,
        'TheoreticalCapacity': theoretical_capacity,
        'AvgWait': np.mean(stats.wait_times) if stats.wait_times else 0,
        'AvgFlow': np.mean(stats.flow_times) if stats.flow_times else 0,
        'AvgService': avg_service,
        'TotalServiceTime': total_service_time,
        'Utilization': utilization_calculated,
        'UtilizationMonitor': np.mean(stats.utilization_samples) * 100 if stats.utilization_samples else 0
    }

# =========================
# RUN COMPARISON
# =========================
print("\n" + "=" * 70)
print("RUNNING SIMULATIONS")
print("=" * 70)

# Run both scenarios with 40 pickers
print("\nRunning Before FPA simulation...")
before_result = run_simulation(BEFORE_FPA, sample_day, NUM_PICKERS, 'before')
print(f"  Completed: {before_result['Picks']} picks, LPMH = {before_result['LPMH']:.2f}")

print("\nRunning After FPA simulation...")
after_result = run_simulation(AFTER_FPA, sample_day, NUM_PICKERS, 'after')
print(f"  Completed: {after_result['Picks']} picks, LPMH = {after_result['LPMH']:.2f}")

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

print(f"\n{'Pickers':<10} {'Before Util%':<14} {'After Util%':<14} {'Before LPMH':<14} {'After LPMH':<14} {'Capacity Gain':<15}")
print("-" * 85)

for n_pickers in picker_counts:
    before = run_simulation(BEFORE_FPA, sample_day, n_pickers, 'before')
    after = run_simulation(AFTER_FPA, sample_day, n_pickers, 'after')

    capacity_gain = ((after['TheoreticalCapacity'] / before['TheoreticalCapacity']) - 1) * 100
    service_diff = (1 - after['AvgService'] / before['AvgService']) * 100

    print(f"{n_pickers:<10} {before['Utilization']:<14.1f} {after['Utilization']:<14.1f} {before['LPMH']:<14.2f} {after['LPMH']:<14.2f} +{capacity_gain:.0f}%")

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
        'Capacity_Gain_Pct': capacity_gain
    })

print("\nNote: Utilization = Total Service Time / (Pickers × Duration)")
print("      LPMH = Picks / (Effective Pickers × Hours)")
print("      Capacity Gain = how much MORE picks can be handled with FPA")

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
