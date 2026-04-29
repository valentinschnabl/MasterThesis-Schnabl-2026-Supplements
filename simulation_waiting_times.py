import pandas as pd
import seaborn as sns
import matplotlib.pyplot as plt
import numpy as np

# Rich output imports
from rich.console import Console
from rich.table import Table
from rich.panel import Panel
from rich import box
from rich.text import Text
import os

console = Console()
OUTPUT_DIR = "result"
os.makedirs(OUTPUT_DIR, exist_ok=True)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PRIMARY_DATA_PATH = os.path.join(BASE_DIR, "sql", "dspace_data.csv")

# ---------------------------------------------------------------------------
# 1. DATA LOADING AND PREPARATION
# ---------------------------------------------------------------------------
try:
    df = pd.read_csv(PRIMARY_DATA_PATH, sep=None, engine='python', header=0,
                     names=['resource_id', 'start_time', 'end_time', 'workflow_stage', 'wait_time_hours'])
    df['workflow_stage'] = df['workflow_stage'].astype(str).str.strip()
    console.print(f"[dim]Data loaded from: {PRIMARY_DATA_PATH}[/dim]")

    # Convert timestamp for monthly trend aggregation
    df['start_time'] = pd.to_datetime(df['start_time'])
    df['month_year'] = df['start_time'].dt.to_period('M').dt.to_timestamp()
except Exception as e:
    console.print(f"[bold red]Error loading data:[/bold red] {e}")
    exit()


def get_stage_order(stages):
    # Keep Resubmission at the end for stable chart order
    return sorted(stages, key=lambda x: (1 if 'Resubmission' in x else 0, x))


global_stage_order = get_stage_order(df['workflow_stage'].unique())

# ---------------------------------------------------------------------------
# 2. VISUALIZATIONS
# ---------------------------------------------------------------------------

# Dashboard 1: distribution and SLA curve
fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(20, 8))

sns.boxplot(
    data=df, x='workflow_stage', y='wait_time_hours',
    hue='workflow_stage',
    order=global_stage_order,
    hue_order=global_stage_order,
    palette="viridis", ax=ax1,
    legend=False,
    showmeans=True, fliersize=1, meanprops={"marker": "o", "markerfacecolor": "white", "markeredgecolor": "black"}
)
ax1.set_yscale("log")
ax1.set_title('Distribution & Outliers (Log Scale)', fontsize=14)
ax1.tick_params(axis='x', rotation=15)

sns.ecdfplot(data=df, x='wait_time_hours', hue='workflow_stage', hue_order=global_stage_order,
             palette="viridis", ax=ax2, linewidth=3)
ax2.set_xscale("log")
ax2.set_title('Cumulative Efficiency (SLA)', fontsize=14)
ax2.grid(True, which="both", ls="-", alpha=0.5)
ax2.axhline(0.5, color='black', linestyle='--', alpha=0.3)
ax2.axhline(0.9, color='red', linestyle='--', alpha=0.3)

plt.suptitle(
    f'DSpace Workflow Analysis 2023–2025 (Publications: {df["resource_id"].nunique():,})', fontsize=18)
plt.tight_layout(rect=[0, 0.03, 1, 0.95])
save_path_1 = os.path.join(OUTPUT_DIR, 'dspace_workflow.png')
plt.savefig(save_path_1, dpi=300)
console.print(f"[dim]Dashboard saved: {save_path_1}[/dim]")

# Dashboard 2: performance trends with linear trend lines
plt.figure(figsize=(15, 8))

# Exclude near-zero bypasses and extreme outliers from trend fitting
trend_df = df[~((df['workflow_stage'] == '2. Library Check') & (df['wait_time_hours'] < 0.02)) &
              (df['wait_time_hours'] <= 200)].copy()

# Use consistent stage ordering in legend and colors
stages = get_stage_order(trend_df['workflow_stage'].unique())
palette = sns.color_palette("tab10", len(stages))

sns.lineplot(data=trend_df, x='month_year', y='wait_time_hours', hue='workflow_stage',
             hue_order=stages, palette=palette, estimator='median', errorbar=None, linewidth=2, alpha=0.3)

slowdown_results = []

for i, stage in enumerate(stages):
    stage_data = trend_df[trend_df['workflow_stage'] == stage].groupby(
        'month_year')['wait_time_hours'].median().reset_index()

    if not stage_data.empty:
        stage_data['month_ordinal'] = stage_data['month_year'].apply(
            lambda x: x.toordinal())
        slope, intercept = np.polyfit(
            stage_data['month_ordinal'], stage_data['wait_time_hours'], 1)

        x_range = np.array([stage_data['month_ordinal'].min(),
                           stage_data['month_ordinal'].max()])
        y_trend = slope * x_range + intercept

        plt.plot(pd.to_datetime([pd.Timestamp.fromordinal(int(x)) for x in x_range]),
                 y_trend, color=palette[i], linestyle='--', linewidth=3, label=f'Trend: {stage}')

        annual_change_hours = slope * 365
        start_val = y_trend[0]
        annual_growth_rate = (annual_change_hours /
                              start_val) * 100 if start_val > 0 else 0
        slowdown_results.append(
            {'Stage': stage, 'Annual % Change': annual_growth_rate})

plt.title('Performance Trends: Median Wait Time & Annual Trends (Visual Outliers Capped at 200h)', fontsize=16)
plt.ylabel('Median Hours')
plt.grid(True, which="both", ls="-", alpha=0.3)
plt.legend(title='Stage & Trends', bbox_to_anchor=(1.05, 1), loc='upper left')
plt.tight_layout()
save_path_2 = os.path.join(OUTPUT_DIR, 'workflow_trends.png')
plt.savefig(save_path_2)
console.print(f"[dim]Trends chart saved: {save_path_2}[/dim]")

# Dashboard 3: lifecycle cost by rejection path
rejected_ids = df[df['workflow_stage'].str.contains(
    'Resubmission')]['resource_id'].unique()

df['path_type'] = df['resource_id'].apply(
    lambda x: 'Rejected at least once' if x in rejected_ids else 'Straight to Archive')

lifecycle_costs = df.groupby(['resource_id', 'path_type'])[
    'wait_time_hours'].sum().reset_index()
plt.figure(figsize=(10, 6))
sns.barplot(
    data=lifecycle_costs,
    x='path_type',
    y='wait_time_hours',
    hue='path_type',
    palette={'Rejected at least once': '#e74c3c',
             'Straight to Archive': '#2ecc71'},
    errorbar=('ci', 95),
    legend=False
)
plt.title('The Penalty of a Mistake: Total lifecycle hours per item', fontsize=16)
plt.ylabel('Total Hours in System')
save_path_3 = os.path.join(OUTPUT_DIR, 'rejection_cost.png')
plt.savefig(save_path_3)
console.print(f"[dim]Rejection analysis saved: {save_path_3}[/dim]")


# ---------------------------------------------------------------------------
# 3. TEXT SUMMARY
# ---------------------------------------------------------------------------
console.print()
console.print(Panel.fit(
    f"[bold white]DSPACE WORKFLOW PERFORMANCE SUMMARY (2023 - 2025)[/bold white]\n"
    f"[dim]TOTAL UNIQUE PUBLICATIONS: {df['resource_id'].nunique():,}[/dim]",
    border_style="bright_white",
    padding=(0, 2),
))
console.print()

# 1. Workflow stage statistics table
stats = df.groupby('workflow_stage')['wait_time_hours'].agg(
    ['median', 'mean', 'count', 'max']).reset_index()

# Convert to categorical to preserve stage order in output
stats['workflow_stage'] = pd.Categorical(
    stats['workflow_stage'], categories=global_stage_order, ordered=True)
stats = stats.sort_values('workflow_stage')

table = Table(
    box=box.ROUNDED,
    show_header=True,
    header_style="bold white",
    border_style="bright_black",
    padding=(0, 1),
    title="[bold]Workflow Stage Statistics (All Raw Data)[/bold]",
    title_style="white",
)

table.add_column("Workflow Stage", style="cyan", min_width=25)
table.add_column("Median (h)", justify="right", min_width=12)
table.add_column("Mean (h)", justify="right", min_width=12)
table.add_column("Max Outlier (h)", justify="right", min_width=18)
table.add_column("Total Count", justify="right", min_width=15)

for _, row in stats.iterrows():
    table.add_row(
        str(row['workflow_stage']),
        f"{row['median']:.2f}",
        f"{row['mean']:.2f}",
        f"{row['max']:.2f}",
        f"{int(row['count']):,}"
    )

console.print(table)
console.print()

# 2. Annual trends table
trend_table = Table(
    box=box.ROUNDED,
    show_header=True,
    header_style="bold white",
    border_style="bright_black",
    padding=(0, 1),
    title="[bold]Annual Trends (Compound Growth/Decline)[/bold]",
    title_style="white",
)

trend_table.add_column("Stage", style="bold", min_width=25)
trend_table.add_column("Annual % Change", justify="right", min_width=18)
trend_table.add_column("Direction", justify="center", min_width=15)

for res in slowdown_results:
    rate = res['Annual % Change']
    direction_color = "red" if rate > 0 else "green"
    direction_text = "SLOWER" if rate > 0 else "FASTER"

    trend_table.add_row(
        Text(res['Stage'], style="dim"),
        Text(f"{abs(rate):.1f}%", style=direction_color),
        Text(direction_text, style=f"bold {direction_color}")
    )

console.print(trend_table)
console.print()

# 3. Aggregate bottleneck and rejection cost panel
bottleneck = df.groupby('workflow_stage')['wait_time_hours'].sum().idxmax()
total_wasted = df.groupby('workflow_stage')['wait_time_hours'].sum().max()

avg_cost = lifecycle_costs.groupby('path_type')['wait_time_hours'].mean()

cost_rejected = avg_cost.get('Rejected at least once', 0)
cost_straight = avg_cost.get('Straight to Archive', 0)
cost_diff = (cost_rejected - cost_straight) if cost_rejected > 0 else 0.0

rej_pct = (len(rejected_ids) / df['resource_id'].nunique()
           ) * 100 if df['resource_id'].nunique() > 0 else 0

insights_text = (
    f"[yellow]MOST TOTAL TIME SPENT IN:[/yellow] [bold]{bottleneck}[/bold]\n"
    f"Aggregate wait time: [bold]{total_wasted:,.2f}[/bold] business hours.\n\n"
    f"[red]HIDDEN COST OF REWORK:[/red] [bold]+{cost_diff:,.2f}[/bold] hours per item\n"
    f"Items requiring Author Revision: [bold]{len(rejected_ids):,}[/bold] ({rej_pct:.1f}%)"
)

console.print(Panel(
    insights_text,
    title="[bold white]Lifecycle Bottlenecks & Penalty[/bold white]",
    border_style="bright_black",
    padding=(1, 2),
))
console.print()

# 4. Data integrity panel
lib_step = df[df['workflow_stage'] == '2. Library Check']
skipped_lib = lib_step[lib_step['wait_time_hours'] < 0.02]
skip_rate = (len(skipped_lib) / len(lib_step)) * \
    100 if len(lib_step) > 0 else 0

wellness_text = (
    f"Total items reaching Library Validation : [bold]{len(lib_step):,}[/bold]\n"
    f"Items skipped/zero-time (< 1.2m)        : [bold cyan]{len(skipped_lib):,}[/bold cyan] [dim]({skip_rate:.1f}%)[/dim]"
)

console.print(Panel.fit(
    wellness_text,
    title="[bold white]DATA INTEGRITY: LIBRARY BYPASS: LIBRARY STEP[/bold white]",
    border_style="cyan",
    padding=(0, 2),
))
console.print()
