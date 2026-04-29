# Supplementary Materials: Multi-Model BI for Institutional Reporting

Author: Valentin Schnabl  
Institution: TU Wien  
Advisor: Ao. Univ. Prof. Dipl.-Ing. Dr.techn. Stefan Biffl
Thesis Title: Multi-Model Business Intelligence Exploration for Monitoring and Improving Institutional Reporting 
Year: 2026

## Overview
This repository contains supplementary material for a master's thesis on institutional workflow performance in ReposiTUm (DSpace), including:

1. SQL-based extraction and workflow reconstruction logic
2. Python simulations of workflow effort scenarios
3. Data-driven waiting-time analysis and visual dashboards
4. Prompt transparency documentation for AI-assisted writing support

## Repository Structure

### Data
- `sql/dspace_data.csv`: Extracted workflow dataset used by `simulation_waiting_times.py`.

### Python Scripts
- `simulation.py`: Monte Carlo simulation (10,000 trials) comparing four workflow variants:
	- AS-IS Baseline
	- Procedural Streamlining
	- Expert Operations
	- Maximum Automation
- `simulation_waiting_times.py`: Empirical waiting-time analysis and dashboard generation from `sql/dspace_data.csv`.

### SQL
- `sql/rejection_frequency_per_step.sql`: Quantifies rejection frequencies by workflow step.
- `sql/waiting_times.sql`: Builds/queries workflow bottleneck timings from provenance events.

### Documentation
- `Promt_Log.md`: Prompt log used for transparency of generative AI support.
- `README.md`: Project summary and usage instructions.

### Output Artifacts
Generated files are written to `result/`:

- `result/simulation_results.pdf`
- `result/labor_composition_stacked_bar.pdf`
- `result/dspace_workflow.png`
- `result/workflow_trends.png`
- `result/rejection_cost.png`

## Requirements
Python 3.10+ is recommended.

Install dependencies:

```bash
pip install numpy pandas matplotlib seaborn rich
```

## Usage

Run Monte Carlo scenario simulation:

```bash
python simulation.py
```

Run waiting-time dashboard analysis:

```bash
python simulation_waiting_times.py
```

Both scripts save charts/PDF outputs into `result/`.


## Disclaimer
All core analytical content and thesis conclusions are the author's original work. AI-related artifacts are included for reproducibility and transparency.
