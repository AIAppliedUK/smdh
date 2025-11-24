# Streamlit Dashboard Pages - Complete Implementation

## Overview

This document provides complete, production-ready implementations for all 8 SMDH analytics dashboard pages. Each page leverages the Snowflake views and utilities defined in the [STREAMLIT_DASHBOARD_GUIDE.md](STREAMLIT_DASHBOARD_GUIDE.md).

## Project Structure Reference

```
streamlit_app/
├── Home.py                          # Already implemented in guide
├── pages/
│   ├── 01_Fleet_Utilization.py     # ✅ Implemented below
│   ├── 02_Machine_Timeline.py      # ✅ Implemented below
│   ├── 03_Production_Events.py     # ✅ Implemented below
│   ├── 04_Energy_Cost.py           # ✅ Implemented below
│   ├── 05_Anomalies.py             # ✅ Implemented below
│   ├── 06_Machine_Health.py        # ✅ Implemented below
│   ├── 07_Environmental.py         # ✅ Implemented below
│   └── 08_OEE_Benchmarking.py      # ✅ Implemented below
├── utils/
│   ├── snowflake_connector.py      # Already implemented
│   └── chart_builders.py           # Already implemented
└── .streamlit/
    └── secrets.toml                # Already defined
```

---

## 1. Fleet Utilization & Idle Losses

**File**: `pages/01_Fleet_Utilization.py`

```python
import streamlit as st
import pandas as pd
import plotly.graph_objects as go
from datetime import datetime, timedelta
import sys
sys.path.append('..')
from utils.snowflake_connector import SnowflakeConnection
from utils.chart_builders import create_stacked_bar_utilization, COLORS

# Page configuration
st.set_page_config(
    page_title="Fleet Utilization & Idle Losses",
    page_icon="📊",
    layout="wide"
)

# Initialize Snowflake connection
sf_conn = SnowflakeConnection()

# Header
st.title("📊 Fleet Utilization & Idle Losses")
st.markdown("Monitor fleet-wide machine states, identify idle losses, and track energy waste.")

# Sidebar filters
st.sidebar.header("Filters")

# Date range selector
default_start = datetime.now() - timedelta(days=7)
default_end = datetime.now()

start_date = st.sidebar.date_input("Start Date", default_start)
end_date = st.sidebar.date_input("End Date", default_end)

# Tenant selector (for multi-tenant deployments)
tenants_query = "SELECT DISTINCT tenant_id, tenant_name FROM mart.dim_tenant ORDER BY tenant_name"
tenants_df = sf_conn.execute_query(tenants_query)
selected_tenant = st.sidebar.selectbox(
    "Tenant",
    options=tenants_df['TENANT_NAME'].tolist(),
    index=0
)
tenant_id = tenants_df[tenants_df['TENANT_NAME'] == selected_tenant]['TENANT_ID'].values[0]

# Location filter
locations_query = f"""
    SELECT DISTINCT location
    FROM mart.dim_machine
    WHERE tenant_id = '{tenant_id}'
    ORDER BY location
"""
locations_df = sf_conn.execute_query(locations_query)
selected_locations = st.sidebar.multiselect(
    "Locations",
    options=locations_df['LOCATION'].tolist(),
    default=locations_df['LOCATION'].tolist()
)

# Machine type filter
machine_types_query = f"""
    SELECT DISTINCT machine_type
    FROM mart.dim_machine
    WHERE tenant_id = '{tenant_id}'
    ORDER BY machine_type
"""
types_df = sf_conn.execute_query(machine_types_query)
selected_types = st.sidebar.multiselect(
    "Machine Types",
    options=types_df['MACHINE_TYPE'].tolist(),
    default=types_df['MACHINE_TYPE'].tolist()
)

# Refresh button
if st.sidebar.button("Refresh Data", type="primary"):
    st.cache_data.clear()
    st.rerun()

# Main data query
@st.cache_data(ttl=300)
def get_fleet_utilization(tenant_id, start, end, locations, types):
    """Fetch fleet utilization data from Snowflake view."""
    locations_list = "','".join(locations)
    types_list = "','".join(types)

    query = f"""
    SELECT
        machine_name,
        location,
        machine_type,
        total_hours,
        off_hours,
        idle_hours,
        working_hours,
        off_percentage,
        idle_percentage,
        working_percentage,
        idle_energy_kwh,
        idle_cost_gbp,
        total_energy_kwh,
        total_cost_gbp
    FROM mart.v_fleet_utilization
    WHERE tenant_id = '{tenant_id}'
        AND date_key BETWEEN '{start}' AND '{end}'
        AND location IN ('{locations_list}')
        AND machine_type IN ('{types_list}')
    ORDER BY idle_cost_gbp DESC
    """
    return sf_conn.execute_query(query)

# Fetch data
try:
    df = get_fleet_utilization(
        tenant_id,
        start_date.strftime('%Y-%m-%d'),
        end_date.strftime('%Y-%m-%d'),
        selected_locations,
        selected_types
    )

    if df.empty:
        st.warning("No data found for the selected filters.")
        st.stop()

    # Summary KPIs
    st.subheader("Fleet Summary")
    col1, col2, col3, col4 = st.columns(4)

    with col1:
        total_machines = len(df)
        st.metric("Total Machines", total_machines)

    with col2:
        avg_utilization = df['WORKING_PERCENTAGE'].mean()
        st.metric("Avg Utilization", f"{avg_utilization:.1f}%")

    with col3:
        total_idle_cost = df['IDLE_COST_GBP'].sum()
        st.metric("Total Idle Cost", f"£{total_idle_cost:,.2f}", delta=f"-{total_idle_cost*0.15:.0f} potential savings")

    with col4:
        total_idle_energy = df['IDLE_ENERGY_KWH'].sum()
        st.metric("Idle Energy Waste", f"{total_idle_energy:,.1f} kWh")

    # Utilization breakdown chart
    st.subheader("Machine Utilization Breakdown")
    fig_utilization = create_stacked_bar_utilization(df)
    st.plotly_chart(fig_utilization, use_container_width=True)

    # Idle losses ranking
    st.subheader("Top Idle Losses (by Cost)")
    col1, col2 = st.columns(2)

    with col1:
        # Top 10 machines by idle cost
        top_idle = df.nlargest(10, 'IDLE_COST_GBP')[['MACHINE_NAME', 'IDLE_COST_GBP', 'IDLE_ENERGY_KWH', 'IDLE_PERCENTAGE']]

        fig_idle_cost = go.Figure()
        fig_idle_cost.add_trace(go.Bar(
            y=top_idle['MACHINE_NAME'],
            x=top_idle['IDLE_COST_GBP'],
            orientation='h',
            marker_color=COLORS['idle'],
            text=top_idle['IDLE_COST_GBP'].apply(lambda x: f"£{x:,.2f}"),
            textposition='auto'
        ))
        fig_idle_cost.update_layout(
            title="Top 10 Machines by Idle Cost",
            xaxis_title="Idle Cost (£)",
            yaxis_title="Machine",
            height=400
        )
        st.plotly_chart(fig_idle_cost, use_container_width=True)

    with col2:
        # Scatter: Idle % vs Idle Cost
        fig_scatter = go.Figure()
        fig_scatter.add_trace(go.Scatter(
            x=df['IDLE_PERCENTAGE'],
            y=df['IDLE_COST_GBP'],
            mode='markers',
            marker=dict(
                size=df['TOTAL_ENERGY_KWH'] / 100,  # Size by energy consumption
                color=df['IDLE_ENERGY_KWH'],
                colorscale='Reds',
                showscale=True,
                colorbar=dict(title="Idle Energy<br>(kWh)")
            ),
            text=df['MACHINE_NAME'],
            hovertemplate='<b>%{text}</b><br>Idle: %{x:.1f}%<br>Cost: £%{y:,.2f}<extra></extra>'
        ))
        fig_scatter.update_layout(
            title="Idle Percentage vs Cost Impact",
            xaxis_title="Idle Percentage (%)",
            yaxis_title="Idle Cost (£)",
            height=400
        )
        st.plotly_chart(fig_scatter, use_container_width=True)

    # Detailed data table
    st.subheader("Detailed Machine Data")

    # Format dataframe for display
    display_df = df.copy()
    display_df['IDLE_COST_GBP'] = display_df['IDLE_COST_GBP'].apply(lambda x: f"£{x:,.2f}")
    display_df['TOTAL_COST_GBP'] = display_df['TOTAL_COST_GBP'].apply(lambda x: f"£{x:,.2f}")
    display_df['IDLE_ENERGY_KWH'] = display_df['IDLE_ENERGY_KWH'].apply(lambda x: f"{x:,.1f}")
    display_df['TOTAL_ENERGY_KWH'] = display_df['TOTAL_ENERGY_KWH'].apply(lambda x: f"{x:,.1f}")
    display_df['OFF_PERCENTAGE'] = display_df['OFF_PERCENTAGE'].apply(lambda x: f"{x:.1f}%")
    display_df['IDLE_PERCENTAGE'] = display_df['IDLE_PERCENTAGE'].apply(lambda x: f"{x:.1f}%")
    display_df['WORKING_PERCENTAGE'] = display_df['WORKING_PERCENTAGE'].apply(lambda x: f"{x:.1f}%")

    st.dataframe(
        display_df,
        use_container_width=True,
        hide_index=True,
        column_config={
            "MACHINE_NAME": st.column_config.TextColumn("Machine", width="medium"),
            "LOCATION": st.column_config.TextColumn("Location", width="small"),
            "MACHINE_TYPE": st.column_config.TextColumn("Type", width="small"),
            "WORKING_PERCENTAGE": st.column_config.TextColumn("Working %", width="small"),
            "IDLE_PERCENTAGE": st.column_config.TextColumn("Idle %", width="small"),
            "OFF_PERCENTAGE": st.column_config.TextColumn("Off %", width="small"),
            "IDLE_COST_GBP": st.column_config.TextColumn("Idle Cost", width="small"),
            "TOTAL_COST_GBP": st.column_config.TextColumn("Total Cost", width="small"),
        }
    )

    # Export functionality
    st.subheader("Export Data")
    csv = df.to_csv(index=False).encode('utf-8')
    st.download_button(
        label="Download CSV",
        data=csv,
        file_name=f"fleet_utilization_{start_date}_{end_date}.csv",
        mime="text/csv"
    )

except Exception as e:
    st.error(f"Error fetching data: {str(e)}")
    st.exception(e)
```

---

## 2. Machine Timeline & Shift View

**File**: `pages/02_Machine_Timeline.py`

```python
import streamlit as st
import pandas as pd
import plotly.graph_objects as go
import plotly.express as px
from datetime import datetime, timedelta
import sys
sys.path.append('..')
from utils.snowflake_connector import SnowflakeConnection
from utils.chart_builders import COLORS

st.set_page_config(
    page_title="Machine Timeline & Shift View",
    page_icon="📅",
    layout="wide"
)

sf_conn = SnowflakeConnection()

st.title("📅 Machine Timeline & Shift View")
st.markdown("Real-time machine state monitoring with shift overlay and timeline visualization.")

# Sidebar filters
st.sidebar.header("Filters")

# Date selector (single day view)
selected_date = st.sidebar.date_input("Date", datetime.now())

# Tenant selector
tenants_query = "SELECT DISTINCT tenant_id, tenant_name FROM mart.dim_tenant ORDER BY tenant_name"
tenants_df = sf_conn.execute_query(tenants_query)
selected_tenant = st.sidebar.selectbox(
    "Tenant",
    options=tenants_df['TENANT_NAME'].tolist(),
    index=0
)
tenant_id = tenants_df[tenants_df['TENANT_NAME'] == selected_tenant]['TENANT_ID'].values[0]

# Machine selector
machines_query = f"""
    SELECT machine_id, machine_name, location, machine_type
    FROM mart.dim_machine
    WHERE tenant_id = '{tenant_id}'
    ORDER BY location, machine_name
"""
machines_df = sf_conn.execute_query(machines_query)
selected_machines = st.sidebar.multiselect(
    "Machines",
    options=machines_df['MACHINE_NAME'].tolist(),
    default=machines_df['MACHINE_NAME'].head(5).tolist()
)

# Get machine IDs for selected machines
machine_ids = machines_df[machines_df['MACHINE_NAME'].isin(selected_machines)]['MACHINE_ID'].tolist()

# View mode
view_mode = st.sidebar.radio("View Mode", ["Timeline", "Heatmap", "State Summary"])

# Auto-refresh
auto_refresh = st.sidebar.checkbox("Auto-refresh (30s)", value=False)
if auto_refresh:
    import time
    time.sleep(30)
    st.rerun()

# Fetch timeline data
@st.cache_data(ttl=30)
def get_machine_timeline(tenant_id, date, machine_ids):
    """Fetch machine state timeline data."""
    machine_ids_list = "','".join(machine_ids)

    query = f"""
    SELECT
        ms.machine_id,
        dm.machine_name,
        dm.location,
        ms.state,
        ms.timestamp_utc as start_time,
        ms.duration_minutes,
        ms.power_kw,
        ms.energy_kwh,
        ms.cost_gbp,
        DATEADD(minute, ms.duration_minutes, ms.timestamp_utc) as end_time
    FROM mart.fact_machine_state ms
    JOIN mart.dim_machine dm ON ms.machine_id = dm.machine_id
    WHERE ms.tenant_id = '{tenant_id}'
        AND ms.date_key = '{date}'
        AND ms.machine_id IN ('{machine_ids_list}')
    ORDER BY dm.machine_name, ms.timestamp_utc
    """
    return sf_conn.execute_query(query)

# Fetch shift data
@st.cache_data(ttl=300)
def get_shift_definitions(tenant_id):
    """Fetch shift definitions."""
    query = f"""
    SELECT
        shift_name,
        start_time,
        end_time,
        is_production_shift
    FROM mart.dim_shift
    WHERE tenant_id = '{tenant_id}'
    ORDER BY start_time
    """
    return sf_conn.execute_query(query)

try:
    if not machine_ids:
        st.warning("Please select at least one machine.")
        st.stop()

    timeline_df = get_machine_timeline(
        tenant_id,
        selected_date.strftime('%Y-%m-%d'),
        machine_ids
    )

    if timeline_df.empty:
        st.warning("No data found for the selected date and machines.")
        st.stop()

    shifts_df = get_shift_definitions(tenant_id)

    # Summary metrics
    st.subheader(f"Summary for {selected_date.strftime('%Y-%m-%d')}")
    col1, col2, col3, col4 = st.columns(4)

    with col1:
        total_duration = timeline_df['DURATION_MINUTES'].sum()
        st.metric("Total Time Tracked", f"{total_duration/60:.1f} hrs")

    with col2:
        working_duration = timeline_df[timeline_df['STATE'] == 'WORKING']['DURATION_MINUTES'].sum()
        working_pct = (working_duration / total_duration * 100) if total_duration > 0 else 0
        st.metric("Working Time", f"{working_pct:.1f}%", delta=f"{working_duration/60:.1f} hrs")

    with col3:
        idle_duration = timeline_df[timeline_df['STATE'] == 'IDLE']['DURATION_MINUTES'].sum()
        idle_pct = (idle_duration / total_duration * 100) if total_duration > 0 else 0
        st.metric("Idle Time", f"{idle_pct:.1f}%", delta=f"-{idle_duration/60:.1f} hrs", delta_color="inverse")

    with col4:
        total_energy = timeline_df['ENERGY_KWH'].sum()
        st.metric("Total Energy", f"{total_energy:.1f} kWh")

    # Visualization based on view mode
    if view_mode == "Timeline":
        st.subheader("Machine State Timeline")

        # Create Gantt chart
        fig = go.Figure()

        # Color mapping
        color_map = {
            'OFF': COLORS['off'],
            'IDLE': COLORS['idle'],
            'WORKING': COLORS['working']
        }

        # Add bars for each state
        for _, row in timeline_df.iterrows():
            fig.add_trace(go.Bar(
                y=[row['MACHINE_NAME']],
                x=[row['DURATION_MINUTES']],
                base=pd.to_datetime(row['START_TIME']).strftime('%Y-%m-%d %H:%M:%S'),
                orientation='h',
                marker=dict(color=color_map.get(row['STATE'], '#cccccc')),
                name=row['STATE'],
                showlegend=False,
                hovertemplate=(
                    f"<b>{row['MACHINE_NAME']}</b><br>" +
                    f"State: {row['STATE']}<br>" +
                    f"Start: {row['START_TIME']}<br>" +
                    f"Duration: {row['DURATION_MINUTES']:.0f} min<br>" +
                    f"Power: {row['POWER_KW']:.2f} kW<br>" +
                    f"Energy: {row['ENERGY_KWH']:.3f} kWh<br>" +
                    f"Cost: £{row['COST_GBP']:.3f}<extra></extra>"
                )
            ))

        # Add shift overlays
        if not shifts_df.empty:
            for _, shift in shifts_df.iterrows():
                shift_start = pd.to_datetime(f"{selected_date} {shift['START_TIME']}")
                shift_end = pd.to_datetime(f"{selected_date} {shift['END_TIME']}")

                fig.add_vrect(
                    x0=shift_start,
                    x1=shift_end,
                    fillcolor="lightblue" if shift['IS_PRODUCTION_SHIFT'] else "lightgray",
                    opacity=0.1,
                    layer="below",
                    line_width=0,
                )

                # Add shift label
                fig.add_annotation(
                    x=shift_start,
                    y=1.05,
                    yref="paper",
                    text=shift['SHIFT_NAME'],
                    showarrow=False,
                    font=dict(size=10)
                )

        fig.update_layout(
            barmode='overlay',
            xaxis=dict(
                title="Time of Day",
                type='date',
                tickformat='%H:%M',
                range=[
                    pd.to_datetime(f"{selected_date} 00:00:00"),
                    pd.to_datetime(f"{selected_date} 23:59:59")
                ]
            ),
            yaxis=dict(title="Machine"),
            height=max(400, len(selected_machines) * 80),
            hovermode='closest',
            showlegend=False
        )

        st.plotly_chart(fig, use_container_width=True)

        # Legend
        st.markdown("""
        **Legend:**
        - <span style='color:#2ca02c'>█</span> WORKING
        - <span style='color:#ff7f0e'>█</span> IDLE
        - <span style='color:#d62728'>█</span> OFF
        - <span style='background-color:lightblue; padding:2px 8px'>Blue overlay</span> Production Shift
        - <span style='background-color:lightgray; padding:2px 8px'>Gray overlay</span> Non-production Shift
        """, unsafe_allow_html=True)

    elif view_mode == "Heatmap":
        st.subheader("State Heatmap (Hourly)")

        # Aggregate by hour
        timeline_df['HOUR'] = pd.to_datetime(timeline_df['START_TIME']).dt.hour

        # Create pivot for heatmap
        state_numeric = {'OFF': 0, 'IDLE': 1, 'WORKING': 2}
        timeline_df['STATE_NUMERIC'] = timeline_df['STATE'].map(state_numeric)

        heatmap_data = timeline_df.groupby(['MACHINE_NAME', 'HOUR']).agg({
            'STATE_NUMERIC': 'mean',  # Average state (will be between 0-2)
            'DURATION_MINUTES': 'sum'
        }).reset_index()

        pivot = heatmap_data.pivot(index='MACHINE_NAME', columns='HOUR', values='STATE_NUMERIC')

        fig_heatmap = go.Figure(data=go.Heatmap(
            z=pivot.values,
            x=pivot.columns,
            y=pivot.index,
            colorscale=[[0, COLORS['off']], [0.5, COLORS['idle']], [1, COLORS['working']]],
            hovertemplate='Machine: %{y}<br>Hour: %{x}:00<br>Avg State: %{z:.2f}<extra></extra>',
            colorbar=dict(
                title="State",
                tickvals=[0, 1, 2],
                ticktext=['OFF', 'IDLE', 'WORKING']
            )
        ))

        fig_heatmap.update_layout(
            title="Machine State by Hour",
            xaxis_title="Hour of Day",
            yaxis_title="Machine",
            height=max(400, len(selected_machines) * 40)
        )

        st.plotly_chart(fig_heatmap, use_container_width=True)

    else:  # State Summary
        st.subheader("State Duration Summary")

        # Aggregate by machine and state
        summary = timeline_df.groupby(['MACHINE_NAME', 'STATE']).agg({
            'DURATION_MINUTES': 'sum',
            'ENERGY_KWH': 'sum',
            'COST_GBP': 'sum'
        }).reset_index()

        summary['DURATION_HOURS'] = summary['DURATION_MINUTES'] / 60

        # Pivot for stacked bar
        pivot_duration = summary.pivot(index='MACHINE_NAME', columns='STATE', values='DURATION_HOURS').fillna(0)

        fig_summary = go.Figure()

        for state in ['OFF', 'IDLE', 'WORKING']:
            if state in pivot_duration.columns:
                fig_summary.add_trace(go.Bar(
                    name=state,
                    x=pivot_duration.index,
                    y=pivot_duration[state],
                    marker_color=COLORS[state.lower()],
                    text=pivot_duration[state].apply(lambda x: f"{x:.1f}h"),
                    textposition='auto'
                ))

        fig_summary.update_layout(
            barmode='stack',
            title="State Duration by Machine (Hours)",
            xaxis_title="Machine",
            yaxis_title="Hours",
            height=400
        )

        st.plotly_chart(fig_summary, use_container_width=True)

        # Detailed table
        st.dataframe(
            summary.sort_values(['MACHINE_NAME', 'STATE']),
            use_container_width=True,
            hide_index=True,
            column_config={
                "DURATION_HOURS": st.column_config.NumberColumn("Hours", format="%.2f"),
                "ENERGY_KWH": st.column_config.NumberColumn("Energy (kWh)", format="%.2f"),
                "COST_GBP": st.column_config.NumberColumn("Cost (£)", format="%.2f")
            }
        )

    # Export
    st.subheader("Export Data")
    csv = timeline_df.to_csv(index=False).encode('utf-8')
    st.download_button(
        label="Download Timeline CSV",
        data=csv,
        file_name=f"machine_timeline_{selected_date}.csv",
        mime="text/csv"
    )

except Exception as e:
    st.error(f"Error fetching data: {str(e)}")
    st.exception(e)
```

---

## 3. Production Events & Product Mix

**File**: `pages/03_Production_Events.py`

```python
import streamlit as st
import pandas as pd
import plotly.graph_objects as go
import plotly.express as px
from datetime import datetime, timedelta
import sys
sys.path.append('..')
from utils.snowflake_connector import SnowflakeConnection

st.set_page_config(
    page_title="Production Events & Product Mix",
    page_icon="🏭",
    layout="wide"
)

sf_conn = SnowflakeConnection()

st.title("🏭 Production Events & Product Mix")
st.markdown("Automated production event detection, cycle time analysis, and product type clustering.")

# Sidebar filters
st.sidebar.header("Filters")

default_start = datetime.now() - timedelta(days=7)
default_end = datetime.now()

start_date = st.sidebar.date_input("Start Date", default_start)
end_date = st.sidebar.date_input("End Date", default_end)

# Tenant selector
tenants_query = "SELECT DISTINCT tenant_id, tenant_name FROM mart.dim_tenant ORDER BY tenant_name"
tenants_df = sf_conn.execute_query(tenants_query)
selected_tenant = st.sidebar.selectbox(
    "Tenant",
    options=tenants_df['TENANT_NAME'].tolist(),
    index=0
)
tenant_id = tenants_df[tenants_df['TENANT_NAME'] == selected_tenant]['TENANT_ID'].values[0]

# Machine selector
machines_query = f"""
    SELECT machine_id, machine_name, location
    FROM mart.dim_machine
    WHERE tenant_id = '{tenant_id}'
    ORDER BY location, machine_name
"""
machines_df = sf_conn.execute_query(machines_query)
selected_machine = st.sidebar.selectbox(
    "Machine",
    options=machines_df['MACHINE_NAME'].tolist()
)
machine_id = machines_df[machines_df['MACHINE_NAME'] == selected_machine]['MACHINE_ID'].values[0]

# Fetch production events
@st.cache_data(ttl=300)
def get_production_events(tenant_id, machine_id, start, end):
    """Fetch production events from Snowflake."""
    query = f"""
    SELECT
        event_id,
        event_start,
        event_end,
        duration_minutes,
        avg_power_kw,
        total_energy_kwh,
        product_cluster_id,
        is_outlier,
        outlier_reason
    FROM mart.fact_production_events
    WHERE tenant_id = '{tenant_id}'
        AND machine_id = '{machine_id}'
        AND date_key BETWEEN '{start}' AND '{end}'
    ORDER BY event_start
    """
    return sf_conn.execute_query(query)

# Fetch cluster statistics
@st.cache_data(ttl=300)
def get_cluster_stats(tenant_id, machine_id, start, end):
    """Fetch product cluster statistics."""
    query = f"""
    SELECT
        product_cluster_id,
        COUNT(*) as event_count,
        AVG(duration_minutes) as avg_duration,
        STDDEV(duration_minutes) as stddev_duration,
        AVG(avg_power_kw) as avg_power,
        SUM(total_energy_kwh) as total_energy
    FROM mart.fact_production_events
    WHERE tenant_id = '{tenant_id}'
        AND machine_id = '{machine_id}'
        AND date_key BETWEEN '{start}' AND '{end}'
        AND is_outlier = FALSE
    GROUP BY product_cluster_id
    ORDER BY event_count DESC
    """
    return sf_conn.execute_query(query)

try:
    events_df = get_production_events(
        tenant_id,
        machine_id,
        start_date.strftime('%Y-%m-%d'),
        end_date.strftime('%Y-%m-%d')
    )

    if events_df.empty:
        st.warning("No production events found for the selected period.")
        st.stop()

    clusters_df = get_cluster_stats(
        tenant_id,
        machine_id,
        start_date.strftime('%Y-%m-%d'),
        end_date.strftime('%Y-%m-%d')
    )

    # Summary metrics
    st.subheader("Production Summary")
    col1, col2, col3, col4 = st.columns(4)

    with col1:
        total_events = len(events_df)
        normal_events = len(events_df[events_df['IS_OUTLIER'] == False])
        st.metric("Total Events", total_events, delta=f"{normal_events} normal")

    with col2:
        avg_cycle = events_df[events_df['IS_OUTLIER'] == False]['DURATION_MINUTES'].mean()
        st.metric("Avg Cycle Time", f"{avg_cycle:.1f} min")

    with col3:
        total_energy = events_df['TOTAL_ENERGY_KWH'].sum()
        st.metric("Total Energy", f"{total_energy:.1f} kWh")

    with col4:
        num_clusters = len(clusters_df)
        outlier_count = len(events_df[events_df['IS_OUTLIER'] == True])
        st.metric("Product Types", num_clusters, delta=f"{outlier_count} outliers")

    # Product cluster analysis
    st.subheader("Product Type Clusters (DBSCAN)")

    col1, col2 = st.columns(2)

    with col1:
        # Cluster distribution pie chart
        fig_pie = go.Figure(data=[go.Pie(
            labels=[f"Cluster {c}" for c in clusters_df['PRODUCT_CLUSTER_ID']],
            values=clusters_df['EVENT_COUNT'],
            hole=0.3,
            hovertemplate='<b>%{label}</b><br>Count: %{value}<br>%{percent}<extra></extra>'
        )])
        fig_pie.update_layout(
            title="Event Distribution by Cluster",
            height=400
        )
        st.plotly_chart(fig_pie, use_container_width=True)

    with col2:
        # Cluster characteristics
        fig_cluster_chars = go.Figure()

        fig_cluster_chars.add_trace(go.Bar(
            name='Avg Duration',
            x=[f"Cluster {c}" for c in clusters_df['PRODUCT_CLUSTER_ID']],
            y=clusters_df['AVG_DURATION'],
            yaxis='y',
            marker_color='#1f77b4'
        ))

        fig_cluster_chars.add_trace(go.Scatter(
            name='Avg Power',
            x=[f"Cluster {c}" for c in clusters_df['PRODUCT_CLUSTER_ID']],
            y=clusters_df['AVG_POWER'],
            yaxis='y2',
            mode='lines+markers',
            marker_color='#ff7f0e',
            line=dict(width=3)
        ))

        fig_cluster_chars.update_layout(
            title="Cluster Characteristics",
            yaxis=dict(title="Duration (min)", side='left'),
            yaxis2=dict(title="Power (kW)", side='right', overlaying='y'),
            height=400,
            hovermode='x unified'
        )

        st.plotly_chart(fig_cluster_chars, use_container_width=True)

    # Cycle time histogram
    st.subheader("Cycle Time Distribution")

    # Filter out outliers for cleaner histogram
    normal_events = events_df[events_df['IS_OUTLIER'] == False]

    fig_hist = go.Figure()

    # Create histogram colored by cluster
    for cluster_id in sorted(normal_events['PRODUCT_CLUSTER_ID'].unique()):
        cluster_data = normal_events[normal_events['PRODUCT_CLUSTER_ID'] == cluster_id]

        fig_hist.add_trace(go.Histogram(
            x=cluster_data['DURATION_MINUTES'],
            name=f"Cluster {cluster_id}",
            opacity=0.7,
            nbinsx=30
        ))

    fig_hist.update_layout(
        barmode='overlay',
        title="Cycle Time Distribution by Cluster",
        xaxis_title="Duration (minutes)",
        yaxis_title="Frequency",
        height=400,
        hovermode='x unified'
    )

    st.plotly_chart(fig_hist, use_container_width=True)

    # Time series of events
    st.subheader("Production Events Over Time")

    events_df['EVENT_START_DT'] = pd.to_datetime(events_df['EVENT_START'])
    events_df['DATE'] = events_df['EVENT_START_DT'].dt.date

    # Daily event counts
    daily_counts = events_df.groupby(['DATE', 'PRODUCT_CLUSTER_ID']).size().reset_index(name='COUNT')

    fig_timeseries = px.line(
        daily_counts,
        x='DATE',
        y='COUNT',
        color='PRODUCT_CLUSTER_ID',
        title="Daily Production Events by Cluster",
        labels={'COUNT': 'Event Count', 'DATE': 'Date', 'PRODUCT_CLUSTER_ID': 'Cluster'}
    )
    fig_timeseries.update_layout(height=400)
    st.plotly_chart(fig_timeseries, use_container_width=True)

    # Outlier analysis
    st.subheader("Outlier Analysis")

    outliers = events_df[events_df['IS_OUTLIER'] == True]

    if len(outliers) > 0:
        col1, col2 = st.columns(2)

        with col1:
            # Outlier reasons
            outlier_reasons = outliers['OUTLIER_REASON'].value_counts()

            fig_reasons = go.Figure(data=[go.Bar(
                x=outlier_reasons.index,
                y=outlier_reasons.values,
                marker_color='#d62728'
            )])
            fig_reasons.update_layout(
                title="Outlier Reasons",
                xaxis_title="Reason",
                yaxis_title="Count",
                height=350
            )
            st.plotly_chart(fig_reasons, use_container_width=True)

        with col2:
            # Scatter: Duration vs Power (with outliers highlighted)
            fig_scatter = go.Figure()

            # Normal events
            fig_scatter.add_trace(go.Scatter(
                x=normal_events['DURATION_MINUTES'],
                y=normal_events['AVG_POWER_KW'],
                mode='markers',
                name='Normal',
                marker=dict(size=8, color='#2ca02c', opacity=0.6),
                text=[f"Cluster {c}" for c in normal_events['PRODUCT_CLUSTER_ID']],
                hovertemplate='<b>%{text}</b><br>Duration: %{x:.1f} min<br>Power: %{y:.2f} kW<extra></extra>'
            ))

            # Outliers
            fig_scatter.add_trace(go.Scatter(
                x=outliers['DURATION_MINUTES'],
                y=outliers['AVG_POWER_KW'],
                mode='markers',
                name='Outliers',
                marker=dict(size=12, color='#d62728', symbol='x'),
                text=outliers['OUTLIER_REASON'],
                hovertemplate='<b>Outlier</b><br>Duration: %{x:.1f} min<br>Power: %{y:.2f} kW<br>%{text}<extra></extra>'
            ))

            fig_scatter.update_layout(
                title="Event Scatter: Duration vs Power",
                xaxis_title="Duration (min)",
                yaxis_title="Avg Power (kW)",
                height=350
            )
            st.plotly_chart(fig_scatter, use_container_width=True)

        # Outlier table
        st.markdown("**Recent Outliers:**")
        outlier_display = outliers[['EVENT_START', 'DURATION_MINUTES', 'AVG_POWER_KW', 'OUTLIER_REASON']].head(10)
        st.dataframe(outlier_display, use_container_width=True, hide_index=True)
    else:
        st.info("No outliers detected in this period.")

    # Cluster statistics table
    st.subheader("Cluster Statistics")

    clusters_display = clusters_df.copy()
    clusters_display['PRODUCT_CLUSTER_ID'] = clusters_display['PRODUCT_CLUSTER_ID'].apply(lambda x: f"Cluster {x}")
    clusters_display['AVG_DURATION'] = clusters_display['AVG_DURATION'].apply(lambda x: f"{x:.1f} min")
    clusters_display['STDDEV_DURATION'] = clusters_display['STDDEV_DURATION'].apply(lambda x: f"±{x:.1f} min")
    clusters_display['AVG_POWER'] = clusters_display['AVG_POWER'].apply(lambda x: f"{x:.2f} kW")
    clusters_display['TOTAL_ENERGY'] = clusters_display['TOTAL_ENERGY'].apply(lambda x: f"{x:.1f} kWh")

    st.dataframe(
        clusters_display,
        use_container_width=True,
        hide_index=True,
        column_config={
            "PRODUCT_CLUSTER_ID": st.column_config.TextColumn("Cluster"),
            "EVENT_COUNT": st.column_config.NumberColumn("Events", format="%d"),
            "AVG_DURATION": st.column_config.TextColumn("Avg Duration"),
            "STDDEV_DURATION": st.column_config.TextColumn("Std Dev"),
            "AVG_POWER": st.column_config.TextColumn("Avg Power"),
            "TOTAL_ENERGY": st.column_config.TextColumn("Total Energy")
        }
    )

    # Export
    st.subheader("Export Data")
    col1, col2 = st.columns(2)

    with col1:
        csv_events = events_df.to_csv(index=False).encode('utf-8')
        st.download_button(
            label="Download Events CSV",
            data=csv_events,
            file_name=f"production_events_{machine_id}_{start_date}_{end_date}.csv",
            mime="text/csv"
        )

    with col2:
        csv_clusters = clusters_df.to_csv(index=False).encode('utf-8')
        st.download_button(
            label="Download Clusters CSV",
            data=csv_clusters,
            file_name=f"product_clusters_{machine_id}_{start_date}_{end_date}.csv",
            mime="text/csv"
        )

except Exception as e:
    st.error(f"Error fetching data: {str(e)}")
    st.exception(e)
```

---

## 4. Energy & Cost by State

**File**: `pages/04_Energy_Cost.py`

```python
import streamlit as st
import pandas as pd
import plotly.graph_objects as go
import plotly.express as px
from datetime import datetime, timedelta
import sys
sys.path.append('..')
from utils.snowflake_connector import SnowflakeConnection
from utils.chart_builders import COLORS

st.set_page_config(
    page_title="Energy & Cost Analysis",
    page_icon="⚡",
    layout="wide"
)

sf_conn = SnowflakeConnection()

st.title("⚡ Energy & Cost Analysis")
st.markdown("Analyze energy consumption and costs by machine state, tariff period, and time.")

# Sidebar filters
st.sidebar.header("Filters")

default_start = datetime.now() - timedelta(days=30)
default_end = datetime.now()

start_date = st.sidebar.date_input("Start Date", default_start)
end_date = st.sidebar.date_input("End Date", default_end)

# Tenant selector
tenants_query = "SELECT DISTINCT tenant_id, tenant_name FROM mart.dim_tenant ORDER BY tenant_name"
tenants_df = sf_conn.execute_query(tenants_query)
selected_tenant = st.sidebar.selectbox(
    "Tenant",
    options=tenants_df['TENANT_NAME'].tolist(),
    index=0
)
tenant_id = tenants_df[tenants_df['TENANT_NAME'] == selected_tenant]['TENANT_ID'].values[0]

# Aggregation level
agg_level = st.sidebar.radio("Aggregation", ["Fleet", "Location", "Machine Type", "Individual Machine"])

# Fetch energy data
@st.cache_data(ttl=300)
def get_energy_by_state(tenant_id, start, end, agg_level):
    """Fetch energy and cost data by state."""

    group_by_clause = {
        "Fleet": "d.date",
        "Location": "d.date, dm.location",
        "Machine Type": "d.date, dm.machine_type",
        "Individual Machine": "d.date, dm.machine_name"
    }[agg_level]

    select_dims = {
        "Fleet": "d.date",
        "Location": "d.date, dm.location",
        "Machine Type": "d.date, dm.machine_type",
        "Individual Machine": "d.date, dm.machine_name, dm.location"
    }[agg_level]

    query = f"""
    SELECT
        {select_dims},
        ms.state,
        SUM(ms.energy_kwh) as total_energy_kwh,
        SUM(ms.cost_gbp) as total_cost_gbp,
        SUM(ms.duration_minutes) as total_duration_minutes
    FROM mart.fact_machine_state ms
    JOIN mart.dim_machine dm ON ms.machine_id = dm.machine_id
    JOIN mart.dim_date d ON ms.date_key = d.date_key
    WHERE ms.tenant_id = '{tenant_id}'
        AND d.date BETWEEN '{start}' AND '{end}'
    GROUP BY {group_by_clause}, ms.state
    ORDER BY d.date
    """
    return sf_conn.execute_query(query)

# Fetch tariff breakdown
@st.cache_data(ttl=300)
def get_tariff_breakdown(tenant_id, start, end):
    """Fetch energy cost by tariff period."""
    query = f"""
    SELECT
        d.date,
        dt.tariff_period,
        SUM(ms.energy_kwh) as energy_kwh,
        AVG(dt.rate_per_kwh) as avg_rate,
        SUM(ms.cost_gbp) as cost_gbp
    FROM mart.fact_machine_state ms
    JOIN mart.dim_date d ON ms.date_key = d.date_key
    JOIN mart.dim_time dt ON ms.time_key = dt.time_key
    WHERE ms.tenant_id = '{tenant_id}'
        AND d.date BETWEEN '{start}' AND '{end}'
    GROUP BY d.date, dt.tariff_period
    ORDER BY d.date, dt.tariff_period
    """
    return sf_conn.execute_query(query)

try:
    energy_df = get_energy_by_state(
        tenant_id,
        start_date.strftime('%Y-%m-%d'),
        end_date.strftime('%Y-%m-%d'),
        agg_level
    )

    if energy_df.empty:
        st.warning("No energy data found for the selected period.")
        st.stop()

    tariff_df = get_tariff_breakdown(
        tenant_id,
        start_date.strftime('%Y-%m-%d'),
        end_date.strftime('%Y-%m-%d')
    )

    # Summary metrics
    st.subheader("Energy Summary")
    col1, col2, col3, col4 = st.columns(4)

    with col1:
        total_energy = energy_df['TOTAL_ENERGY_KWH'].sum()
        st.metric("Total Energy", f"{total_energy:,.0f} kWh")

    with col2:
        total_cost = energy_df['TOTAL_COST_GBP'].sum()
        st.metric("Total Cost", f"£{total_cost:,.2f}")

    with col3:
        idle_energy = energy_df[energy_df['STATE'] == 'IDLE']['TOTAL_ENERGY_KWH'].sum()
        idle_pct = (idle_energy / total_energy * 100) if total_energy > 0 else 0
        st.metric("Idle Energy", f"{idle_pct:.1f}%", delta=f"-{idle_energy:,.0f} kWh potential savings", delta_color="inverse")

    with col4:
        avg_rate = total_cost / total_energy if total_energy > 0 else 0
        st.metric("Avg Rate", f"£{avg_rate:.3f}/kWh")

    # Energy by state breakdown
    st.subheader("Energy Consumption by State")

    # Aggregate by state
    state_totals = energy_df.groupby('STATE').agg({
        'TOTAL_ENERGY_KWH': 'sum',
        'TOTAL_COST_GBP': 'sum'
    }).reset_index()

    col1, col2 = st.columns(2)

    with col1:
        # Pie chart: Energy by state
        fig_pie_energy = go.Figure(data=[go.Pie(
            labels=state_totals['STATE'],
            values=state_totals['TOTAL_ENERGY_KWH'],
            marker=dict(colors=[COLORS[s.lower()] for s in state_totals['STATE']]),
            hole=0.4,
            hovertemplate='<b>%{label}</b><br>Energy: %{value:,.0f} kWh<br>%{percent}<extra></extra>'
        )])
        fig_pie_energy.update_layout(
            title="Energy Distribution by State",
            height=400
        )
        st.plotly_chart(fig_pie_energy, use_container_width=True)

    with col2:
        # Bar chart: Cost by state
        fig_bar_cost = go.Figure(data=[go.Bar(
            x=state_totals['STATE'],
            y=state_totals['TOTAL_COST_GBP'],
            marker=dict(color=[COLORS[s.lower()] for s in state_totals['STATE']]),
            text=state_totals['TOTAL_COST_GBP'].apply(lambda x: f"£{x:,.2f}"),
            textposition='auto'
        )])
        fig_bar_cost.update_layout(
            title="Cost by State",
            xaxis_title="State",
            yaxis_title="Cost (£)",
            height=400
        )
        st.plotly_chart(fig_bar_cost, use_container_width=True)

    # Time series analysis
    st.subheader("Energy Trends Over Time")

    # Prepare time series data
    if agg_level == "Fleet":
        ts_data = energy_df.copy()
        color_col = 'STATE'
        line_group = None
    else:
        # For other aggregation levels, we need to pivot
        dim_col = {
            "Location": "LOCATION",
            "Machine Type": "MACHINE_TYPE",
            "Individual Machine": "MACHINE_NAME"
        }[agg_level]

        ts_data = energy_df.copy()
        color_col = dim_col
        line_group = 'STATE'

    # Daily energy stacked area chart
    if agg_level == "Fleet":
        pivot_ts = energy_df.pivot(index='DATE', columns='STATE', values='TOTAL_ENERGY_KWH').fillna(0)

        fig_area = go.Figure()

        for state in ['OFF', 'IDLE', 'WORKING']:
            if state in pivot_ts.columns:
                fig_area.add_trace(go.Scatter(
                    x=pivot_ts.index,
                    y=pivot_ts[state],
                    mode='lines',
                    name=state,
                    stackgroup='one',
                    fillcolor=COLORS[state.lower()],
                    line=dict(color=COLORS[state.lower()], width=0)
                ))

        fig_area.update_layout(
            title="Daily Energy Consumption by State",
            xaxis_title="Date",
            yaxis_title="Energy (kWh)",
            height=400,
            hovermode='x unified'
        )
        st.plotly_chart(fig_area, use_container_width=True)
    else:
        # Line chart for other aggregation levels
        fig_lines = px.line(
            energy_df,
            x='DATE',
            y='TOTAL_ENERGY_KWH',
            color=color_col,
            line_group='STATE' if agg_level != "Fleet" else None,
            title=f"Daily Energy by {agg_level}",
            labels={'TOTAL_ENERGY_KWH': 'Energy (kWh)', 'DATE': 'Date'}
        )
        fig_lines.update_layout(height=400)
        st.plotly_chart(fig_lines, use_container_width=True)

    # Tariff period analysis
    st.subheader("Cost by Tariff Period")

    if not tariff_df.empty:
        col1, col2 = st.columns(2)

        with col1:
            # Aggregate tariff totals
            tariff_totals = tariff_df.groupby('TARIFF_PERIOD').agg({
                'ENERGY_KWH': 'sum',
                'COST_GBP': 'sum',
                'AVG_RATE': 'mean'
            }).reset_index()

            # Stacked bar: Energy by tariff period
            fig_tariff_bar = go.Figure(data=[go.Bar(
                x=tariff_totals['TARIFF_PERIOD'],
                y=tariff_totals['ENERGY_KWH'],
                marker=dict(color=['#17becf', '#bcbd22', '#9467bd'][:len(tariff_totals)]),
                text=tariff_totals['ENERGY_KWH'].apply(lambda x: f"{x:,.0f} kWh"),
                textposition='auto'
            )])
            fig_tariff_bar.update_layout(
                title="Energy by Tariff Period",
                xaxis_title="Tariff Period",
                yaxis_title="Energy (kWh)",
                height=350
            )
            st.plotly_chart(fig_tariff_bar, use_container_width=True)

        with col2:
            # Rates and costs
            fig_tariff_combo = go.Figure()

            fig_tariff_combo.add_trace(go.Bar(
                name='Cost',
                x=tariff_totals['TARIFF_PERIOD'],
                y=tariff_totals['COST_GBP'],
                yaxis='y',
                marker_color='#e377c2'
            ))

            fig_tariff_combo.add_trace(go.Scatter(
                name='Avg Rate',
                x=tariff_totals['TARIFF_PERIOD'],
                y=tariff_totals['AVG_RATE'],
                yaxis='y2',
                mode='lines+markers',
                marker=dict(size=10, color='#ff7f0e'),
                line=dict(width=3)
            ))

            fig_tariff_combo.update_layout(
                title="Cost and Rates by Tariff Period",
                yaxis=dict(title="Cost (£)", side='left'),
                yaxis2=dict(title="Rate (£/kWh)", side='right', overlaying='y'),
                height=350,
                hovermode='x unified'
            )

            st.plotly_chart(fig_tariff_combo, use_container_width=True)

        # Time series of tariff costs
        pivot_tariff = tariff_df.pivot(index='DATE', columns='TARIFF_PERIOD', values='COST_GBP').fillna(0)

        fig_tariff_ts = go.Figure()

        for period in pivot_tariff.columns:
            fig_tariff_ts.add_trace(go.Scatter(
                x=pivot_tariff.index,
                y=pivot_tariff[period],
                mode='lines',
                name=period,
                stackgroup='one'
            ))

        fig_tariff_ts.update_layout(
            title="Daily Cost by Tariff Period",
            xaxis_title="Date",
            yaxis_title="Cost (£)",
            height=400,
            hovermode='x unified'
        )
        st.plotly_chart(fig_tariff_ts, use_container_width=True)

    # Detailed data table
    st.subheader("Detailed Energy Data")

    # Aggregate for display
    if agg_level == "Fleet":
        display_df = energy_df.groupby(['DATE', 'STATE']).agg({
            'TOTAL_ENERGY_KWH': 'sum',
            'TOTAL_COST_GBP': 'sum',
            'TOTAL_DURATION_MINUTES': 'sum'
        }).reset_index()
    else:
        group_cols = ['DATE']
        if agg_level == "Location":
            group_cols.append('LOCATION')
        elif agg_level == "Machine Type":
            group_cols.append('MACHINE_TYPE')
        else:
            group_cols.extend(['MACHINE_NAME', 'LOCATION'])

        group_cols.append('STATE')

        display_df = energy_df.groupby(group_cols).agg({
            'TOTAL_ENERGY_KWH': 'sum',
            'TOTAL_COST_GBP': 'sum',
            'TOTAL_DURATION_MINUTES': 'sum'
        }).reset_index()

    # Format for display
    display_df['TOTAL_ENERGY_KWH'] = display_df['TOTAL_ENERGY_KWH'].apply(lambda x: f"{x:,.1f}")
    display_df['TOTAL_COST_GBP'] = display_df['TOTAL_COST_GBP'].apply(lambda x: f"£{x:,.2f}")
    display_df['TOTAL_DURATION_MINUTES'] = display_df['TOTAL_DURATION_MINUTES'].apply(lambda x: f"{x/60:.1f} hrs")

    st.dataframe(
        display_df.head(100),
        use_container_width=True,
        hide_index=True
    )

    # Export
    st.subheader("Export Data")
    col1, col2 = st.columns(2)

    with col1:
        csv_energy = energy_df.to_csv(index=False).encode('utf-8')
        st.download_button(
            label="Download Energy Data CSV",
            data=csv_energy,
            file_name=f"energy_by_state_{start_date}_{end_date}.csv",
            mime="text/csv"
        )

    with col2:
        if not tariff_df.empty:
            csv_tariff = tariff_df.to_csv(index=False).encode('utf-8')
            st.download_button(
                label="Download Tariff Data CSV",
                data=csv_tariff,
                file_name=f"energy_by_tariff_{start_date}_{end_date}.csv",
                mime="text/csv"
            )

except Exception as e:
    st.error(f"Error fetching data: {str(e)}")
    st.exception(e)
```

---

## 5. Anomalies & Outliers

**File**: `pages/05_Anomalies.py`

```python
import streamlit as st
import pandas as pd
import plotly.graph_objects as go
import plotly.express as px
from datetime import datetime, timedelta
import sys
sys.path.append('..')
from utils.snowflake_connector import SnowflakeConnection

st.set_page_config(
    page_title="Anomalies & Outliers",
    page_icon="🚨",
    layout="wide"
)

sf_conn = SnowflakeConnection()

st.title("🚨 Anomalies & Outliers")
st.markdown("Identify unusual production events, power anomalies, and potential quality issues.")

# Sidebar filters
st.sidebar.header("Filters")

default_start = datetime.now() - timedelta(days=30)
default_end = datetime.now()

start_date = st.sidebar.date_input("Start Date", default_start)
end_date = st.sidebar.date_input("End Date", default_end)

# Tenant selector
tenants_query = "SELECT DISTINCT tenant_id, tenant_name FROM mart.dim_tenant ORDER BY tenant_name"
tenants_df = sf_conn.execute_query(tenants_query)
selected_tenant = st.sidebar.selectbox(
    "Tenant",
    options=tenants_df['TENANT_NAME'].tolist(),
    index=0
)
tenant_id = tenants_df[tenants_df['TENANT_NAME'] == selected_tenant]['TENANT_ID'].values[0]

# Anomaly type filter
anomaly_types = st.sidebar.multiselect(
    "Anomaly Types",
    options=["Duration Outliers", "Power Anomalies", "State Anomalies", "All"],
    default=["All"]
)

# Severity filter
severity_filter = st.sidebar.multiselect(
    "Severity",
    options=["High", "Medium", "Low"],
    default=["High", "Medium", "Low"]
)

# Fetch anomaly data
@st.cache_data(ttl=300)
def get_anomalies(tenant_id, start, end):
    """Fetch production event outliers."""
    query = f"""
    SELECT
        pe.event_id,
        dm.machine_name,
        dm.location,
        pe.event_start,
        pe.duration_minutes,
        pe.avg_power_kw,
        pe.total_energy_kwh,
        pe.product_cluster_id,
        pe.outlier_reason,
        CASE
            WHEN pe.duration_minutes > (SELECT AVG(duration_minutes) * 3 FROM mart.fact_production_events WHERE machine_id = pe.machine_id AND is_outlier = FALSE) THEN 'High'
            WHEN pe.duration_minutes > (SELECT AVG(duration_minutes) * 2 FROM mart.fact_production_events WHERE machine_id = pe.machine_id AND is_outlier = FALSE) THEN 'Medium'
            ELSE 'Low'
        END as severity
    FROM mart.fact_production_events pe
    JOIN mart.dim_machine dm ON pe.machine_id = dm.machine_id
    WHERE pe.tenant_id = '{tenant_id}'
        AND pe.date_key BETWEEN '{start}' AND '{end}'
        AND pe.is_outlier = TRUE
    ORDER BY pe.event_start DESC
    """
    return sf_conn.execute_query(query)

# Fetch power anomalies
@st.cache_data(ttl=300)
def get_power_anomalies(tenant_id, start, end):
    """Fetch power-based anomalies."""
    query = f"""
    SELECT
        ms.machine_id,
        dm.machine_name,
        dm.location,
        ms.timestamp_utc,
        ms.state,
        ms.power_kw,
        ms.energy_kwh,
        CASE
            WHEN ABS(ms.power_kw - AVG(ms.power_kw) OVER (PARTITION BY ms.machine_id, ms.state)) >
                 2 * STDDEV(ms.power_kw) OVER (PARTITION BY ms.machine_id, ms.state) THEN 'High'
            WHEN ABS(ms.power_kw - AVG(ms.power_kw) OVER (PARTITION BY ms.machine_id, ms.state)) >
                 1.5 * STDDEV(ms.power_kw) OVER (PARTITION BY ms.machine_id, ms.state) THEN 'Medium'
            ELSE 'Low'
        END as severity,
        'Power deviation from normal' as anomaly_type
    FROM mart.fact_machine_state ms
    JOIN mart.dim_machine dm ON ms.machine_id = dm.machine_id
    WHERE ms.tenant_id = '{tenant_id}'
        AND ms.date_key BETWEEN '{start}' AND '{end}'
        AND ms.state = 'WORKING'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ms.machine_id ORDER BY
        ABS(ms.power_kw - AVG(ms.power_kw) OVER (PARTITION BY ms.machine_id, ms.state)) DESC
    ) <= 20  -- Top 20 anomalies per machine
    ORDER BY severity DESC, ms.timestamp_utc DESC
    """
    return sf_conn.execute_query(query)

# Fetch state transition anomalies
@st.cache_data(ttl=300)
def get_state_anomalies(tenant_id, start, end):
    """Fetch unusual state transitions."""
    query = f"""
    WITH state_changes AS (
        SELECT
            ms.machine_id,
            dm.machine_name,
            dm.location,
            ms.timestamp_utc,
            ms.state,
            LAG(ms.state) OVER (PARTITION BY ms.machine_id ORDER BY ms.timestamp_utc) as prev_state,
            ms.duration_minutes,
            CASE
                WHEN ms.duration_minutes < 1 AND ms.state != 'OFF' THEN 'High'
                WHEN ms.duration_minutes < 5 AND ms.state = 'WORKING' THEN 'Medium'
                ELSE 'Low'
            END as severity
        FROM mart.fact_machine_state ms
        JOIN mart.dim_machine dm ON ms.machine_id = dm.machine_id
        WHERE ms.tenant_id = '{tenant_id}'
            AND ms.date_key BETWEEN '{start}' AND '{end}'
    )
    SELECT
        machine_id,
        machine_name,
        location,
        timestamp_utc,
        state,
        prev_state,
        duration_minutes,
        severity,
        'Rapid state change' as anomaly_type
    FROM state_changes
    WHERE duration_minutes < 5
        AND state != prev_state
    ORDER BY severity DESC, timestamp_utc DESC
    LIMIT 100
    """
    return sf_conn.execute_query(query)

try:
    # Fetch all anomaly types
    duration_anomalies = get_anomalies(
        tenant_id,
        start_date.strftime('%Y-%m-%d'),
        end_date.strftime('%Y-%m-%d')
    )

    power_anomalies = get_power_anomalies(
        tenant_id,
        start_date.strftime('%Y-%m-%d'),
        end_date.strftime('%Y-%m-%d')
    )

    state_anomalies = get_state_anomalies(
        tenant_id,
        start_date.strftime('%Y-%m-%d'),
        end_date.strftime('%Y-%m-%d')
    )

    # Filter by severity
    duration_anomalies = duration_anomalies[duration_anomalies['SEVERITY'].isin(severity_filter)]
    power_anomalies = power_anomalies[power_anomalies['SEVERITY'].isin(severity_filter)]
    state_anomalies = state_anomalies[state_anomalies['SEVERITY'].isin(severity_filter)]

    # Summary metrics
    st.subheader("Anomaly Summary")
    col1, col2, col3, col4 = st.columns(4)

    with col1:
        total_anomalies = len(duration_anomalies) + len(power_anomalies) + len(state_anomalies)
        st.metric("Total Anomalies", total_anomalies)

    with col2:
        high_severity = (
            len(duration_anomalies[duration_anomalies['SEVERITY'] == 'High']) +
            len(power_anomalies[power_anomalies['SEVERITY'] == 'High']) +
            len(state_anomalies[state_anomalies['SEVERITY'] == 'High'])
        )
        st.metric("High Severity", high_severity, delta="Requires attention", delta_color="inverse")

    with col3:
        st.metric("Duration Outliers", len(duration_anomalies))

    with col4:
        st.metric("Power Anomalies", len(power_anomalies))

    # Anomaly distribution
    st.subheader("Anomaly Distribution")

    col1, col2 = st.columns(2)

    with col1:
        # By type
        type_counts = pd.DataFrame({
            'Type': ['Duration Outliers', 'Power Anomalies', 'State Anomalies'],
            'Count': [len(duration_anomalies), len(power_anomalies), len(state_anomalies)]
        })

        fig_types = go.Figure(data=[go.Bar(
            x=type_counts['Type'],
            y=type_counts['Count'],
            marker_color=['#d62728', '#ff7f0e', '#9467bd'],
            text=type_counts['Count'],
            textposition='auto'
        )])
        fig_types.update_layout(
            title="Anomalies by Type",
            xaxis_title="Type",
            yaxis_title="Count",
            height=350
        )
        st.plotly_chart(fig_types, use_container_width=True)

    with col2:
        # By severity (across all types)
        all_severities = (
            list(duration_anomalies['SEVERITY']) +
            list(power_anomalies['SEVERITY']) +
            list(state_anomalies['SEVERITY'])
        )
        severity_counts = pd.Series(all_severities).value_counts()

        fig_severity = go.Figure(data=[go.Pie(
            labels=severity_counts.index,
            values=severity_counts.values,
            marker=dict(colors=['#d62728', '#ff7f0e', '#2ca02c']),
            hole=0.4
        )])
        fig_severity.update_layout(
            title="Anomalies by Severity",
            height=350
        )
        st.plotly_chart(fig_severity, use_container_width=True)

    # Duration Outliers
    if not duration_anomalies.empty and ("Duration Outliers" in anomaly_types or "All" in anomaly_types):
        st.subheader("Duration Outliers")

        col1, col2 = st.columns(2)

        with col1:
            # Outlier reasons
            reason_counts = duration_anomalies['OUTLIER_REASON'].value_counts()

            fig_reasons = go.Figure(data=[go.Bar(
                y=reason_counts.index,
                x=reason_counts.values,
                orientation='h',
                marker_color='#d62728'
            )])
            fig_reasons.update_layout(
                title="Outlier Reasons",
                xaxis_title="Count",
                yaxis_title="Reason",
                height=350
            )
            st.plotly_chart(fig_reasons, use_container_width=True)

        with col2:
            # Duration distribution
            fig_duration_dist = go.Figure()

            for severity in ['High', 'Medium', 'Low']:
                subset = duration_anomalies[duration_anomalies['SEVERITY'] == severity]
                if not subset.empty:
                    fig_duration_dist.add_trace(go.Box(
                        y=subset['DURATION_MINUTES'],
                        name=severity,
                        marker_color={'High': '#d62728', 'Medium': '#ff7f0e', 'Low': '#2ca02c'}[severity]
                    ))

            fig_duration_dist.update_layout(
                title="Duration Distribution by Severity",
                yaxis_title="Duration (minutes)",
                height=350
            )
            st.plotly_chart(fig_duration_dist, use_container_width=True)

        # Recent outliers table
        st.markdown("**Recent Duration Outliers:**")
        display_outliers = duration_anomalies[['MACHINE_NAME', 'EVENT_START', 'DURATION_MINUTES', 'AVG_POWER_KW', 'OUTLIER_REASON', 'SEVERITY']].head(10)
        st.dataframe(display_outliers, use_container_width=True, hide_index=True)

    # Power Anomalies
    if not power_anomalies.empty and ("Power Anomalies" in anomaly_types or "All" in anomaly_types):
        st.subheader("Power Anomalies")

        # Group by machine
        machine_power_counts = power_anomalies.groupby('MACHINE_NAME').size().reset_index(name='Count').sort_values('Count', ascending=False)

        col1, col2 = st.columns(2)

        with col1:
            # Machines with most power anomalies
            fig_machine_anomalies = go.Figure(data=[go.Bar(
                y=machine_power_counts['MACHINE_NAME'].head(10),
                x=machine_power_counts['Count'].head(10),
                orientation='h',
                marker_color='#ff7f0e'
            )])
            fig_machine_anomalies.update_layout(
                title="Top Machines by Power Anomalies",
                xaxis_title="Anomaly Count",
                yaxis_title="Machine",
                height=350
            )
            st.plotly_chart(fig_machine_anomalies, use_container_width=True)

        with col2:
            # Power scatter
            fig_power_scatter = go.Figure()

            fig_power_scatter.add_trace(go.Scatter(
                x=power_anomalies['TIMESTAMP_UTC'],
                y=power_anomalies['POWER_KW'],
                mode='markers',
                marker=dict(
                    size=8,
                    color=power_anomalies['SEVERITY'].map({'High': '#d62728', 'Medium': '#ff7f0e', 'Low': '#2ca02c'}),
                    opacity=0.6
                ),
                text=power_anomalies['MACHINE_NAME'],
                hovertemplate='<b>%{text}</b><br>Time: %{x}<br>Power: %{y:.2f} kW<extra></extra>'
            ))

            fig_power_scatter.update_layout(
                title="Power Anomalies Over Time",
                xaxis_title="Timestamp",
                yaxis_title="Power (kW)",
                height=350
            )
            st.plotly_chart(fig_power_scatter, use_container_width=True)

        # Recent power anomalies table
        st.markdown("**Recent Power Anomalies:**")
        display_power = power_anomalies[['MACHINE_NAME', 'TIMESTAMP_UTC', 'POWER_KW', 'ENERGY_KWH', 'SEVERITY']].head(10)
        st.dataframe(display_power, use_container_width=True, hide_index=True)

    # State Anomalies
    if not state_anomalies.empty and ("State Anomalies" in anomaly_types or "All" in anomaly_types):
        st.subheader("State Transition Anomalies")

        # State transition matrix
        transition_counts = state_anomalies.groupby(['PREV_STATE', 'STATE']).size().reset_index(name='Count')

        # Create transition matrix
        states = ['OFF', 'IDLE', 'WORKING']
        matrix = pd.DataFrame(0, index=states, columns=states)

        for _, row in transition_counts.iterrows():
            if pd.notna(row['PREV_STATE']) and row['PREV_STATE'] in states and row['STATE'] in states:
                matrix.loc[row['PREV_STATE'], row['STATE']] = row['Count']

        fig_heatmap = go.Figure(data=go.Heatmap(
            z=matrix.values,
            x=matrix.columns,
            y=matrix.index,
            colorscale='Reds',
            text=matrix.values,
            texttemplate='%{text}',
            textfont={"size": 14},
            hovertemplate='From: %{y}<br>To: %{x}<br>Count: %{z}<extra></extra>'
        ))

        fig_heatmap.update_layout(
            title="Rapid State Transition Matrix",
            xaxis_title="To State",
            yaxis_title="From State",
            height=400
        )
        st.plotly_chart(fig_heatmap, use_container_width=True)

        # Recent state anomalies table
        st.markdown("**Recent State Anomalies:**")
        display_state = state_anomalies[['MACHINE_NAME', 'TIMESTAMP_UTC', 'PREV_STATE', 'STATE', 'DURATION_MINUTES', 'SEVERITY']].head(10)
        st.dataframe(display_state, use_container_width=True, hide_index=True)

    # Export
    st.subheader("Export Anomaly Data")
    col1, col2, col3 = st.columns(3)

    with col1:
        if not duration_anomalies.empty:
            csv_duration = duration_anomalies.to_csv(index=False).encode('utf-8')
            st.download_button(
                label="Download Duration Outliers",
                data=csv_duration,
                file_name=f"duration_outliers_{start_date}_{end_date}.csv",
                mime="text/csv"
            )

    with col2:
        if not power_anomalies.empty:
            csv_power = power_anomalies.to_csv(index=False).encode('utf-8')
            st.download_button(
                label="Download Power Anomalies",
                data=csv_power,
                file_name=f"power_anomalies_{start_date}_{end_date}.csv",
                mime="text/csv"
            )

    with col3:
        if not state_anomalies.empty:
            csv_state = state_anomalies.to_csv(index=False).encode('utf-8')
            st.download_button(
                label="Download State Anomalies",
                data=csv_state,
                file_name=f"state_anomalies_{start_date}_{end_date}.csv",
                mime="text/csv"
            )

except Exception as e:
    st.error(f"Error fetching data: {str(e)}")
    st.exception(e)
```

---

## 6. Machine Health (SENTINEL)

**File**: `pages/06_Machine_Health.py`

```python
import streamlit as st
import pandas as pd
import plotly.graph_objects as go
import plotly.express as px
from datetime import datetime, timedelta
import sys
sys.path.append('..')
from utils.snowflake_connector import SnowflakeConnection

st.set_page_config(
    page_title="Machine Health Monitoring",
    page_icon="🔧",
    layout="wide"
)

sf_conn = SnowflakeConnection()

st.title("🔧 Machine Health Monitoring (SENTINEL)")
st.markdown("Monitor vibration, temperature, and power quality for predictive maintenance.")

# Sidebar filters
st.sidebar.header("Filters")

default_start = datetime.now() - timedelta(days=14)
default_end = datetime.now()

start_date = st.sidebar.date_input("Start Date", default_start)
end_date = st.sidebar.date_input("End Date", default_end)

# Tenant selector
tenants_query = "SELECT DISTINCT tenant_id, tenant_name FROM mart.dim_tenant ORDER BY tenant_name"
tenants_df = sf_conn.execute_query(tenants_query)
selected_tenant = st.sidebar.selectbox(
    "Tenant",
    options=tenants_df['TENANT_NAME'].tolist(),
    index=0
)
tenant_id = tenants_df[tenants_df['TENANT_NAME'] == selected_tenant]['TENANT_ID'].values[0]

# Machine selector (only machines with SENTINEL sensors)
machines_query = f"""
    SELECT DISTINCT dm.machine_id, dm.machine_name, dm.location
    FROM mart.dim_machine dm
    JOIN normalized.vibration_metrics vm ON dm.machine_id = vm.machine_id
    WHERE dm.tenant_id = '{tenant_id}'
    ORDER BY dm.location, dm.machine_name
"""
machines_df = sf_conn.execute_query(machines_query)

if machines_df.empty:
    st.warning("No machines with SENTINEL sensors found. SENTINEL sensors are required for health monitoring.")
    st.stop()

selected_machine = st.sidebar.selectbox(
    "Machine",
    options=machines_df['MACHINE_NAME'].tolist()
)
machine_id = machines_df[machines_df['MACHINE_NAME'] == selected_machine]['MACHINE_ID'].values[0]

# Metric selector
metric_type = st.sidebar.radio(
    "Metric Type",
    ["Vibration", "Temperature", "Power Quality", "All"]
)

# Fetch vibration data
@st.cache_data(ttl=300)
def get_vibration_metrics(tenant_id, machine_id, start, end):
    """Fetch vibration metrics from SENTINEL sensors."""
    query = f"""
    SELECT
        timestamp,
        vibration_rms,
        vibration_peak,
        vibration_frequency_hz,
        vibration_health_score
    FROM normalized.vibration_metrics
    WHERE tenant_id = '{tenant_id}'
        AND machine_id = '{machine_id}'
        AND DATE(timestamp) BETWEEN '{start}' AND '{end}'
    ORDER BY timestamp
    """
    return sf_conn.execute_query(query)

# Fetch temperature data
@st.cache_data(ttl=300)
def get_temperature_metrics(tenant_id, machine_id, start, end):
    """Fetch temperature metrics from SENTINEL sensors."""
    query = f"""
    SELECT
        timestamp,
        temperature_celsius,
        temperature_baseline,
        temperature_deviation
    FROM normalized.temperature_metrics
    WHERE tenant_id = '{tenant_id}'
        AND machine_id = '{machine_id}'
        AND DATE(timestamp) BETWEEN '{start}' AND '{end}'
    ORDER BY timestamp
    """
    return sf_conn.execute_query(query)

# Fetch power quality data
@st.cache_data(ttl=300)
def get_power_quality_metrics(tenant_id, machine_id, start, end):
    """Fetch power quality metrics from SENTINEL sensors."""
    query = f"""
    SELECT
        timestamp,
        power_factor,
        thd_voltage,
        thd_current,
        voltage_unbalance,
        current_unbalance
    FROM normalized.power_quality_metrics
    WHERE tenant_id = '{tenant_id}'
        AND machine_id = '{machine_id}'
        AND DATE(timestamp) BETWEEN '{start}' AND '{end}'
    ORDER BY timestamp
    """
    return sf_conn.execute_query(query)

# Fetch health alerts
@st.cache_data(ttl=60)
def get_health_alerts(tenant_id, machine_id, start, end):
    """Fetch machine health alerts."""
    query = f"""
    SELECT
        alert_timestamp,
        alert_type,
        severity,
        metric_name,
        metric_value,
        threshold_value,
        alert_message
    FROM mart.fact_health_alerts
    WHERE tenant_id = '{tenant_id}'
        AND machine_id = '{machine_id}'
        AND DATE(alert_timestamp) BETWEEN '{start}' AND '{end}'
    ORDER BY alert_timestamp DESC
    """
    return sf_conn.execute_query(query)

try:
    # Fetch data based on metric type
    vibration_df = None
    temperature_df = None
    power_quality_df = None

    if metric_type in ["Vibration", "All"]:
        vibration_df = get_vibration_metrics(tenant_id, machine_id, start_date.strftime('%Y-%m-%d'), end_date.strftime('%Y-%m-%d'))

    if metric_type in ["Temperature", "All"]:
        temperature_df = get_temperature_metrics(tenant_id, machine_id, start_date.strftime('%Y-%m-%d'), end_date.strftime('%Y-%m-%d'))

    if metric_type in ["Power Quality", "All"]:
        power_quality_df = get_power_quality_metrics(tenant_id, machine_id, start_date.strftime('%Y-%m-%d'), end_date.strftime('%Y-%m-%d'))

    alerts_df = get_health_alerts(tenant_id, machine_id, start_date.strftime('%Y-%m-%d'), end_date.strftime('%Y-%m-%d'))

    # Health summary
    st.subheader("Machine Health Summary")

    col1, col2, col3, col4 = st.columns(4)

    with col1:
        if vibration_df is not None and not vibration_df.empty:
            avg_health_score = vibration_df['VIBRATION_HEALTH_SCORE'].mean()
            health_status = "Good" if avg_health_score >= 80 else "Warning" if avg_health_score >= 60 else "Critical"
            st.metric("Health Score", f"{avg_health_score:.1f}/100", delta=health_status)
        else:
            st.metric("Health Score", "N/A")

    with col2:
        critical_alerts = len(alerts_df[alerts_df['SEVERITY'] == 'Critical']) if not alerts_df.empty else 0
        st.metric("Critical Alerts", critical_alerts, delta="Requires attention" if critical_alerts > 0 else "Normal", delta_color="inverse")

    with col3:
        warning_alerts = len(alerts_df[alerts_df['SEVERITY'] == 'Warning']) if not alerts_df.empty else 0
        st.metric("Warning Alerts", warning_alerts)

    with col4:
        total_alerts = len(alerts_df)
        st.metric("Total Alerts", total_alerts)

    # Recent alerts
    if not alerts_df.empty:
        st.subheader("Recent Health Alerts")

        # Critical alerts callout
        critical = alerts_df[alerts_df['SEVERITY'] == 'Critical']
        if not critical.empty:
            st.error(f"⚠️ {len(critical)} Critical alerts require immediate attention!")

            for _, alert in critical.head(3).iterrows():
                st.markdown(f"""
                <div style='background-color: #ffe6e6; padding: 10px; margin: 5px 0; border-left: 4px solid #d62728;'>
                    <b>{alert['ALERT_TYPE']}</b> - {alert['METRIC_NAME']}<br>
                    <small>{alert['ALERT_TIMESTAMP']}</small><br>
                    {alert['ALERT_MESSAGE']}
                </div>
                """, unsafe_allow_html=True)

        # Alerts timeline
        alerts_by_day = alerts_df.copy()
        alerts_by_day['DATE'] = pd.to_datetime(alerts_by_day['ALERT_TIMESTAMP']).dt.date
        alerts_timeline = alerts_by_day.groupby(['DATE', 'SEVERITY']).size().reset_index(name='Count')

        fig_alerts_timeline = px.bar(
            alerts_timeline,
            x='DATE',
            y='Count',
            color='SEVERITY',
            title="Health Alerts Timeline",
            color_discrete_map={'Critical': '#d62728', 'Warning': '#ff7f0e', 'Info': '#2ca02c'}
        )
        fig_alerts_timeline.update_layout(height=300)
        st.plotly_chart(fig_alerts_timeline, use_container_width=True)

    # Vibration monitoring
    if vibration_df is not None and not vibration_df.empty:
        st.subheader("Vibration Monitoring")

        col1, col2 = st.columns(2)

        with col1:
            # RMS vibration trend
            fig_vib_rms = go.Figure()

            fig_vib_rms.add_trace(go.Scatter(
                x=vibration_df['TIMESTAMP'],
                y=vibration_df['VIBRATION_RMS'],
                mode='lines',
                name='RMS Vibration',
                line=dict(color='#1f77b4', width=2)
            ))

            # Add baseline/threshold
            avg_rms = vibration_df['VIBRATION_RMS'].mean()
            threshold = avg_rms * 1.5

            fig_vib_rms.add_hline(
                y=threshold,
                line_dash="dash",
                line_color="red",
                annotation_text="Threshold"
            )

            fig_vib_rms.update_layout(
                title="RMS Vibration Trend",
                xaxis_title="Timestamp",
                yaxis_title="Vibration RMS (mm/s)",
                height=350,
                hovermode='x unified'
            )
            st.plotly_chart(fig_vib_rms, use_container_width=True)

        with col2:
            # Peak vibration vs frequency
            fig_vib_freq = go.Figure()

            fig_vib_freq.add_trace(go.Scatter(
                x=vibration_df['VIBRATION_FREQUENCY_HZ'],
                y=vibration_df['VIBRATION_PEAK'],
                mode='markers',
                marker=dict(
                    size=8,
                    color=vibration_df['VIBRATION_HEALTH_SCORE'],
                    colorscale='RdYlGn',
                    showscale=True,
                    colorbar=dict(title="Health Score")
                ),
                text=vibration_df['TIMESTAMP'],
                hovertemplate='Frequency: %{x:.1f} Hz<br>Peak: %{y:.2f} mm/s<br>Time: %{text}<extra></extra>'
            ))

            fig_vib_freq.update_layout(
                title="Peak Vibration vs Frequency",
                xaxis_title="Frequency (Hz)",
                yaxis_title="Peak Vibration (mm/s)",
                height=350
            )
            st.plotly_chart(fig_vib_freq, use_container_width=True)

        # Health score over time
        fig_health_score = go.Figure()

        fig_health_score.add_trace(go.Scatter(
            x=vibration_df['TIMESTAMP'],
            y=vibration_df['VIBRATION_HEALTH_SCORE'],
            mode='lines',
            fill='tozeroy',
            line=dict(color='#2ca02c', width=2),
            name='Health Score'
        ))

        # Add threshold zones
        fig_health_score.add_hrect(y0=0, y1=60, fillcolor="red", opacity=0.1, layer="below", line_width=0)
        fig_health_score.add_hrect(y0=60, y1=80, fillcolor="orange", opacity=0.1, layer="below", line_width=0)
        fig_health_score.add_hrect(y0=80, y1=100, fillcolor="green", opacity=0.1, layer="below", line_width=0)

        fig_health_score.update_layout(
            title="Vibration Health Score Trend",
            xaxis_title="Timestamp",
            yaxis_title="Health Score (0-100)",
            height=300,
            hovermode='x unified'
        )
        st.plotly_chart(fig_health_score, use_container_width=True)

    # Temperature monitoring
    if temperature_df is not None and not temperature_df.empty:
        st.subheader("Temperature Monitoring")

        col1, col2 = st.columns(2)

        with col1:
            # Temperature trend with baseline
            fig_temp = go.Figure()

            fig_temp.add_trace(go.Scatter(
                x=temperature_df['TIMESTAMP'],
                y=temperature_df['TEMPERATURE_CELSIUS'],
                mode='lines',
                name='Actual Temperature',
                line=dict(color='#d62728', width=2)
            ))

            fig_temp.add_trace(go.Scatter(
                x=temperature_df['TIMESTAMP'],
                y=temperature_df['TEMPERATURE_BASELINE'],
                mode='lines',
                name='Baseline',
                line=dict(color='#2ca02c', width=2, dash='dash')
            ))

            fig_temp.update_layout(
                title="Temperature Trend vs Baseline",
                xaxis_title="Timestamp",
                yaxis_title="Temperature (°C)",
                height=350,
                hovermode='x unified'
            )
            st.plotly_chart(fig_temp, use_container_width=True)

        with col2:
            # Temperature deviation histogram
            fig_temp_dev = go.Figure(data=[go.Histogram(
                x=temperature_df['TEMPERATURE_DEVIATION'],
                nbinsx=30,
                marker_color='#ff7f0e'
            )])

            fig_temp_dev.update_layout(
                title="Temperature Deviation Distribution",
                xaxis_title="Deviation from Baseline (°C)",
                yaxis_title="Frequency",
                height=350
            )
            st.plotly_chart(fig_temp_dev, use_container_width=True)

    # Power quality monitoring
    if power_quality_df is not None and not power_quality_df.empty:
        st.subheader("Power Quality Monitoring")

        col1, col2 = st.columns(2)

        with col1:
            # Power factor trend
            fig_pf = go.Figure()

            fig_pf.add_trace(go.Scatter(
                x=power_quality_df['TIMESTAMP'],
                y=power_quality_df['POWER_FACTOR'],
                mode='lines',
                line=dict(color='#9467bd', width=2),
                fill='tozeroy'
            ))

            # Target power factor line
            fig_pf.add_hline(
                y=0.95,
                line_dash="dash",
                line_color="green",
                annotation_text="Target (0.95)"
            )

            fig_pf.update_layout(
                title="Power Factor Trend",
                xaxis_title="Timestamp",
                yaxis_title="Power Factor",
                yaxis_range=[0, 1],
                height=350,
                hovermode='x unified'
            )
            st.plotly_chart(fig_pf, use_container_width=True)

        with col2:
            # THD (Total Harmonic Distortion)
            fig_thd = go.Figure()

            fig_thd.add_trace(go.Scatter(
                x=power_quality_df['TIMESTAMP'],
                y=power_quality_df['THD_VOLTAGE'],
                mode='lines',
                name='THD Voltage',
                line=dict(color='#e377c2', width=2)
            ))

            fig_thd.add_trace(go.Scatter(
                x=power_quality_df['TIMESTAMP'],
                y=power_quality_df['THD_CURRENT'],
                mode='lines',
                name='THD Current',
                line=dict(color='#bcbd22', width=2)
            ))

            # IEEE 519 limits
            fig_thd.add_hline(y=5, line_dash="dash", line_color="red", annotation_text="IEEE 519 Limit")

            fig_thd.update_layout(
                title="Total Harmonic Distortion (THD)",
                xaxis_title="Timestamp",
                yaxis_title="THD (%)",
                height=350,
                hovermode='x unified'
            )
            st.plotly_chart(fig_thd, use_container_width=True)

        # Voltage and current unbalance
        col1, col2 = st.columns(2)

        with col1:
            # Voltage unbalance
            fig_v_unbal = go.Figure(data=[go.Box(
                y=power_quality_df['VOLTAGE_UNBALANCE'],
                marker_color='#17becf',
                name='Voltage Unbalance'
            )])

            fig_v_unbal.add_hline(y=2, line_dash="dash", line_color="red", annotation_text="Limit (2%)")

            fig_v_unbal.update_layout(
                title="Voltage Unbalance Distribution",
                yaxis_title="Unbalance (%)",
                height=300
            )
            st.plotly_chart(fig_v_unbal, use_container_width=True)

        with col2:
            # Current unbalance
            fig_i_unbal = go.Figure(data=[go.Box(
                y=power_quality_df['CURRENT_UNBALANCE'],
                marker_color='#ff7f0e',
                name='Current Unbalance'
            )])

            fig_i_unbal.add_hline(y=10, line_dash="dash", line_color="red", annotation_text="Limit (10%)")

            fig_i_unbal.update_layout(
                title="Current Unbalance Distribution",
                yaxis_title="Unbalance (%)",
                height=300
            )
            st.plotly_chart(fig_i_unbal, use_container_width=True)

    # Detailed alerts table
    if not alerts_df.empty:
        st.subheader("Detailed Alert History")

        display_alerts = alerts_df.copy()
        display_alerts = display_alerts[['ALERT_TIMESTAMP', 'ALERT_TYPE', 'SEVERITY', 'METRIC_NAME', 'METRIC_VALUE', 'THRESHOLD_VALUE', 'ALERT_MESSAGE']]

        st.dataframe(
            display_alerts,
            use_container_width=True,
            hide_index=True,
            column_config={
                "ALERT_TIMESTAMP": st.column_config.DatetimeColumn("Timestamp", format="DD/MM/YYYY HH:mm"),
                "METRIC_VALUE": st.column_config.NumberColumn("Value", format="%.2f"),
                "THRESHOLD_VALUE": st.column_config.NumberColumn("Threshold", format="%.2f")
            }
        )

    # Export
    st.subheader("Export Health Data")
    col1, col2, col3 = st.columns(3)

    with col1:
        if vibration_df is not None and not vibration_df.empty:
            csv_vib = vibration_df.to_csv(index=False).encode('utf-8')
            st.download_button(
                label="Download Vibration Data",
                data=csv_vib,
                file_name=f"vibration_{machine_id}_{start_date}_{end_date}.csv",
                mime="text/csv"
            )

    with col2:
        if temperature_df is not None and not temperature_df.empty:
            csv_temp = temperature_df.to_csv(index=False).encode('utf-8')
            st.download_button(
                label="Download Temperature Data",
                data=csv_temp,
                file_name=f"temperature_{machine_id}_{start_date}_{end_date}.csv",
                mime="text/csv"
            )

    with col3:
        if not alerts_df.empty:
            csv_alerts = alerts_df.to_csv(index=False).encode('utf-8')
            st.download_button(
                label="Download Alerts",
                data=csv_alerts,
                file_name=f"health_alerts_{machine_id}_{start_date}_{end_date}.csv",
                mime="text/csv"
            )

except Exception as e:
    st.error(f"Error fetching data: {str(e)}")
    st.exception(e)
```

---

## 7. Environmental Monitoring (HAVEN)

**File**: `pages/07_Environmental.py`

```python
import streamlit as st
import pandas as pd
import plotly.graph_objects as go
import plotly.express as px
from datetime import datetime, timedelta
import sys
sys.path.append('..')
from utils.snowflake_connector import SnowflakeConnection

st.set_page_config(
    page_title="Environmental Monitoring",
    page_icon="🌡️",
    layout="wide"
)

sf_conn = SnowflakeConnection()

st.title("🌡️ Environmental Monitoring (HAVEN)")
st.markdown("Monitor temperature, humidity, air quality, VOCs, NOx, and noise levels in the workspace.")

# Sidebar filters
st.sidebar.header("Filters")

default_start = datetime.now() - timedelta(days=7)
default_end = datetime.now()

start_date = st.sidebar.date_input("Start Date", default_start)
end_date = st.sidebar.date_input("End Date", default_end)

# Tenant selector
tenants_query = "SELECT DISTINCT tenant_id, tenant_name FROM mart.dim_tenant ORDER BY tenant_name"
tenants_df = sf_conn.execute_query(tenants_query)
selected_tenant = st.sidebar.selectbox(
    "Tenant",
    options=tenants_df['TENANT_NAME'].tolist(),
    index=0
)
tenant_id = tenants_df[tenants_df['TENANT_NAME'] == selected_tenant]['TENANT_ID'].values[0]

# Zone/Location selector
zones_query = f"""
    SELECT DISTINCT zone_name
    FROM normalized.environmental_metrics
    WHERE tenant_id = '{tenant_id}'
    ORDER BY zone_name
"""
zones_df = sf_conn.execute_query(zones_query)

if zones_df.empty:
    st.warning("No environmental data found. HAVEN sensors are required for environmental monitoring.")
    st.stop()

selected_zones = st.sidebar.multiselect(
    "Zones",
    options=zones_df['ZONE_NAME'].tolist(),
    default=zones_df['ZONE_NAME'].tolist()
)

# Fetch environmental data
@st.cache_data(ttl=300)
def get_environmental_metrics(tenant_id, zones, start, end):
    """Fetch environmental metrics from HAVEN sensors."""
    zones_list = "','".join(zones)

    query = f"""
    SELECT
        timestamp,
        zone_name,
        temperature_celsius,
        humidity_percent,
        particulate_pm25,
        particulate_pm10,
        voc_index,
        nox_index,
        sound_level_db,
        light_level_lux
    FROM normalized.environmental_metrics
    WHERE tenant_id = '{tenant_id}'
        AND zone_name IN ('{zones_list}')
        AND DATE(timestamp) BETWEEN '{start}' AND '{end}'
    ORDER BY timestamp
    """
    return sf_conn.execute_query(query)

# Fetch compliance thresholds
@st.cache_data(ttl=3600)
def get_compliance_thresholds(tenant_id):
    """Fetch environmental compliance thresholds."""
    query = f"""
    SELECT
        metric_name,
        warning_threshold,
        critical_threshold,
        unit
    FROM mart.dim_environmental_thresholds
    WHERE tenant_id = '{tenant_id}'
    """
    return sf_conn.execute_query(query)

# Fetch compliance violations
@st.cache_data(ttl=300)
def get_compliance_violations(tenant_id, zones, start, end):
    """Fetch environmental compliance violations."""
    zones_list = "','".join(zones)

    query = f"""
    SELECT
        violation_timestamp,
        zone_name,
        metric_name,
        metric_value,
        threshold_value,
        severity,
        duration_minutes
    FROM mart.fact_environmental_violations
    WHERE tenant_id = '{tenant_id}'
        AND zone_name IN ('{zones_list}')
        AND DATE(violation_timestamp) BETWEEN '{start}' AND '{end}'
    ORDER BY violation_timestamp DESC
    """
    return sf_conn.execute_query(query)

try:
    env_df = get_environmental_metrics(
        tenant_id,
        selected_zones,
        start_date.strftime('%Y-%m-%d'),
        end_date.strftime('%Y-%m-%d')
    )

    if env_df.empty:
        st.warning("No environmental data found for the selected zones and period.")
        st.stop()

    thresholds_df = get_compliance_thresholds(tenant_id)
    violations_df = get_compliance_violations(
        tenant_id,
        selected_zones,
        start_date.strftime('%Y-%m-%d'),
        end_date.strftime('%Y-%m-%d')
    )

    # Summary metrics
    st.subheader("Environmental Summary")

    col1, col2, col3, col4 = st.columns(4)

    with col1:
        avg_temp = env_df['TEMPERATURE_CELSIUS'].mean()
        st.metric("Avg Temperature", f"{avg_temp:.1f}°C")

    with col2:
        avg_humidity = env_df['HUMIDITY_PERCENT'].mean()
        st.metric("Avg Humidity", f"{avg_humidity:.1f}%")

    with col3:
        avg_pm25 = env_df['PARTICULATE_PM25'].mean()
        st.metric("Avg PM2.5", f"{avg_pm25:.1f} µg/m³")

    with col4:
        total_violations = len(violations_df)
        critical_violations = len(violations_df[violations_df['SEVERITY'] == 'Critical']) if not violations_df.empty else 0
        st.metric("Violations", total_violations, delta=f"{critical_violations} critical", delta_color="inverse")

    # Compliance violations
    if not violations_df.empty:
        st.subheader("Compliance Violations")

        # Critical violations callout
        critical = violations_df[violations_df['SEVERITY'] == 'Critical']
        if not critical.empty:
            st.error(f"⚠️ {len(critical)} Critical environmental violations detected!")

            for _, violation in critical.head(3).iterrows():
                st.markdown(f"""
                <div style='background-color: #ffe6e6; padding: 10px; margin: 5px 0; border-left: 4px solid #d62728;'>
                    <b>{violation['ZONE_NAME']}</b> - {violation['METRIC_NAME']}<br>
                    <small>{violation['VIOLATION_TIMESTAMP']}</small><br>
                    Value: {violation['METRIC_VALUE']:.2f} (Threshold: {violation['THRESHOLD_VALUE']:.2f})<br>
                    Duration: {violation['DURATION_MINUTES']:.0f} minutes
                </div>
                """, unsafe_allow_html=True)

        # Violations by zone and metric
        col1, col2 = st.columns(2)

        with col1:
            violations_by_zone = violations_df.groupby('ZONE_NAME').size().reset_index(name='Count').sort_values('Count', ascending=False)

            fig_zone_violations = go.Figure(data=[go.Bar(
                y=violations_by_zone['ZONE_NAME'],
                x=violations_by_zone['Count'],
                orientation='h',
                marker_color='#d62728'
            )])
            fig_zone_violations.update_layout(
                title="Violations by Zone",
                xaxis_title="Violation Count",
                yaxis_title="Zone",
                height=300
            )
            st.plotly_chart(fig_zone_violations, use_container_width=True)

        with col2:
            violations_by_metric = violations_df.groupby('METRIC_NAME').size().reset_index(name='Count').sort_values('Count', ascending=False)

            fig_metric_violations = go.Figure(data=[go.Pie(
                labels=violations_by_metric['METRIC_NAME'],
                values=violations_by_metric['Count'],
                hole=0.4
            )])
            fig_metric_violations.update_layout(
                title="Violations by Metric",
                height=300
            )
            st.plotly_chart(fig_metric_violations, use_container_width=True)

    # Temperature and Humidity
    st.subheader("Temperature & Humidity")

    col1, col2 = st.columns(2)

    with col1:
        # Temperature by zone
        fig_temp = go.Figure()

        for zone in selected_zones:
            zone_data = env_df[env_df['ZONE_NAME'] == zone]
            fig_temp.add_trace(go.Scatter(
                x=zone_data['TIMESTAMP'],
                y=zone_data['TEMPERATURE_CELSIUS'],
                mode='lines',
                name=zone
            ))

        # Add comfort zone
        fig_temp.add_hrect(y0=18, y1=24, fillcolor="green", opacity=0.1, layer="below", line_width=0, annotation_text="Comfort Zone")

        fig_temp.update_layout(
            title="Temperature by Zone",
            xaxis_title="Timestamp",
            yaxis_title="Temperature (°C)",
            height=350,
            hovermode='x unified'
        )
        st.plotly_chart(fig_temp, use_container_width=True)

    with col2:
        # Humidity by zone
        fig_humidity = go.Figure()

        for zone in selected_zones:
            zone_data = env_df[env_df['ZONE_NAME'] == zone]
            fig_humidity.add_trace(go.Scatter(
                x=zone_data['TIMESTAMP'],
                y=zone_data['HUMIDITY_PERCENT'],
                mode='lines',
                name=zone
            ))

        # Add comfort zone
        fig_humidity.add_hrect(y0=40, y1=60, fillcolor="green", opacity=0.1, layer="below", line_width=0, annotation_text="Comfort Zone")

        fig_humidity.update_layout(
            title="Humidity by Zone",
            xaxis_title="Timestamp",
            yaxis_title="Humidity (%)",
            height=350,
            hovermode='x unified'
        )
        st.plotly_chart(fig_humidity, use_container_width=True)

    # Air Quality
    st.subheader("Air Quality Monitoring")

    col1, col2 = st.columns(2)

    with col1:
        # PM2.5 and PM10
        fig_pm = go.Figure()

        # Average across zones
        pm_by_time = env_df.groupby('TIMESTAMP').agg({
            'PARTICULATE_PM25': 'mean',
            'PARTICULATE_PM10': 'mean'
        }).reset_index()

        fig_pm.add_trace(go.Scatter(
            x=pm_by_time['TIMESTAMP'],
            y=pm_by_time['PARTICULATE_PM25'],
            mode='lines',
            name='PM2.5',
            line=dict(color='#ff7f0e', width=2)
        ))

        fig_pm.add_trace(go.Scatter(
            x=pm_by_time['TIMESTAMP'],
            y=pm_by_time['PARTICULATE_PM10'],
            mode='lines',
            name='PM10',
            line=dict(color='#d62728', width=2)
        ))

        # WHO guidelines
        fig_pm.add_hline(y=15, line_dash="dash", line_color="orange", annotation_text="PM2.5 WHO 24h (15)")
        fig_pm.add_hline(y=45, line_dash="dash", line_color="red", annotation_text="PM10 WHO 24h (45)")

        fig_pm.update_layout(
            title="Particulate Matter (PM2.5 & PM10)",
            xaxis_title="Timestamp",
            yaxis_title="Concentration (µg/m³)",
            height=350,
            hovermode='x unified'
        )
        st.plotly_chart(fig_pm, use_container_width=True)

    with col2:
        # VOC and NOx indices
        fig_indices = go.Figure()

        indices_by_time = env_df.groupby('TIMESTAMP').agg({
            'VOC_INDEX': 'mean',
            'NOX_INDEX': 'mean'
        }).reset_index()

        fig_indices.add_trace(go.Scatter(
            x=indices_by_time['TIMESTAMP'],
            y=indices_by_time['VOC_INDEX'],
            mode='lines',
            name='VOC Index',
            line=dict(color='#2ca02c', width=2)
        ))

        fig_indices.add_trace(go.Scatter(
            x=indices_by_time['TIMESTAMP'],
            y=indices_by_time['NOX_INDEX'],
            mode='lines',
            name='NOx Index',
            line=dict(color='#9467bd', width=2)
        ))

        # Threshold lines (index > 200 = poor air quality)
        fig_indices.add_hline(y=200, line_dash="dash", line_color="red", annotation_text="Poor Quality (200)")

        fig_indices.update_layout(
            title="VOC & NOx Air Quality Indices",
            xaxis_title="Timestamp",
            yaxis_title="Index (0-500)",
            height=350,
            hovermode='x unified'
        )
        st.plotly_chart(fig_indices, use_container_width=True)

    # Noise and Light
    st.subheader("Noise & Lighting Levels")

    col1, col2 = st.columns(2)

    with col1:
        # Sound levels by zone
        fig_sound = go.Figure()

        for zone in selected_zones:
            zone_data = env_df[env_df['ZONE_NAME'] == zone]
            fig_sound.add_trace(go.Scatter(
                x=zone_data['TIMESTAMP'],
                y=zone_data['SOUND_LEVEL_DB'],
                mode='lines',
                name=zone
            ))

        # OSHA limits
        fig_sound.add_hline(y=85, line_dash="dash", line_color="orange", annotation_text="OSHA 8h limit (85 dB)")
        fig_sound.add_hline(y=90, line_dash="dash", line_color="red", annotation_text="OSHA Action (90 dB)")

        fig_sound.update_layout(
            title="Sound Levels by Zone",
            xaxis_title="Timestamp",
            yaxis_title="Sound Level (dB)",
            height=350,
            hovermode='x unified'
        )
        st.plotly_chart(fig_sound, use_container_width=True)

    with col2:
        # Light levels by zone
        fig_light = go.Figure()

        for zone in selected_zones:
            zone_data = env_df[env_df['ZONE_NAME'] == zone]
            fig_light.add_trace(go.Scatter(
                x=zone_data['TIMESTAMP'],
                y=zone_data['LIGHT_LEVEL_LUX'],
                mode='lines',
                name=zone
            ))

        # Recommended levels
        fig_light.add_hrect(y0=300, y1=750, fillcolor="green", opacity=0.1, layer="below", line_width=0, annotation_text="Office/Light Work")

        fig_light.update_layout(
            title="Light Levels by Zone",
            xaxis_title="Timestamp",
            yaxis_title="Illuminance (lux)",
            height=350,
            hovermode='x unified'
        )
        st.plotly_chart(fig_light, use_container_width=True)

    # Heatmap: Zone comparison
    st.subheader("Zone Comparison Heatmap")

    # Calculate average values by zone
    zone_averages = env_df.groupby('ZONE_NAME').agg({
        'TEMPERATURE_CELSIUS': 'mean',
        'HUMIDITY_PERCENT': 'mean',
        'PARTICULATE_PM25': 'mean',
        'VOC_INDEX': 'mean',
        'NOX_INDEX': 'mean',
        'SOUND_LEVEL_DB': 'mean'
    }).reset_index()

    # Normalize for comparison
    from sklearn.preprocessing import StandardScaler
    scaler = StandardScaler()

    metrics_to_normalize = ['TEMPERATURE_CELSIUS', 'HUMIDITY_PERCENT', 'PARTICULATE_PM25', 'VOC_INDEX', 'NOX_INDEX', 'SOUND_LEVEL_DB']
    zone_averages[metrics_to_normalize] = scaler.fit_transform(zone_averages[metrics_to_normalize])

    # Create heatmap
    fig_heatmap = go.Figure(data=go.Heatmap(
        z=zone_averages[metrics_to_normalize].values.T,
        x=zone_averages['ZONE_NAME'],
        y=['Temp', 'Humidity', 'PM2.5', 'VOC', 'NOx', 'Sound'],
        colorscale='RdYlGn_r',
        hovertemplate='Zone: %{x}<br>Metric: %{y}<br>Normalized: %{z:.2f}<extra></extra>'
    ))

    fig_heatmap.update_layout(
        title="Normalized Environmental Metrics by Zone (Higher = Worse)",
        xaxis_title="Zone",
        yaxis_title="Metric",
        height=400
    )
    st.plotly_chart(fig_heatmap, use_container_width=True)

    # Compliance summary table
    if not thresholds_df.empty:
        st.subheader("Compliance Thresholds")

        st.dataframe(
            thresholds_df,
            use_container_width=True,
            hide_index=True,
            column_config={
                "METRIC_NAME": st.column_config.TextColumn("Metric"),
                "WARNING_THRESHOLD": st.column_config.NumberColumn("Warning", format="%.1f"),
                "CRITICAL_THRESHOLD": st.column_config.NumberColumn("Critical", format="%.1f"),
                "UNIT": st.column_config.TextColumn("Unit")
            }
        )

    # Violations table
    if not violations_df.empty:
        st.subheader("Violation History")

        display_violations = violations_df.copy()
        display_violations = display_violations[['VIOLATION_TIMESTAMP', 'ZONE_NAME', 'METRIC_NAME', 'METRIC_VALUE', 'THRESHOLD_VALUE', 'SEVERITY', 'DURATION_MINUTES']]

        st.dataframe(
            display_violations.head(50),
            use_container_width=True,
            hide_index=True,
            column_config={
                "VIOLATION_TIMESTAMP": st.column_config.DatetimeColumn("Timestamp", format="DD/MM/YYYY HH:mm"),
                "METRIC_VALUE": st.column_config.NumberColumn("Value", format="%.2f"),
                "THRESHOLD_VALUE": st.column_config.NumberColumn("Threshold", format="%.2f"),
                "DURATION_MINUTES": st.column_config.NumberColumn("Duration (min)", format="%.0f")
            }
        )

    # Export
    st.subheader("Export Environmental Data")
    col1, col2 = st.columns(2)

    with col1:
        csv_env = env_df.to_csv(index=False).encode('utf-8')
        st.download_button(
            label="Download Environmental Data",
            data=csv_env,
            file_name=f"environmental_{start_date}_{end_date}.csv",
            mime="text/csv"
        )

    with col2:
        if not violations_df.empty:
            csv_violations = violations_df.to_csv(index=False).encode('utf-8')
            st.download_button(
                label="Download Violations",
                data=csv_violations,
                file_name=f"environmental_violations_{start_date}_{end_date}.csv",
                mime="text/csv"
            )

except Exception as e:
    st.error(f"Error fetching data: {str(e)}")
    st.exception(e)
```

---

## 8. OEE & Benchmarking

**File**: `pages/08_OEE_Benchmarking.py`

```python
import streamlit as st
import pandas as pd
import plotly.graph_objects as go
import plotly.express as px
from datetime import datetime, timedelta
import sys
sys.path.append('..')
from utils.snowflake_connector import SnowflakeConnection

st.set_page_config(
    page_title="OEE & Benchmarking",
    page_icon="📈",
    layout="wide"
)

sf_conn = SnowflakeConnection()

st.title("📈 OEE & Benchmarking")
st.markdown("Overall Equipment Effectiveness (OEE) analysis and performance benchmarking across fleet.")

# Sidebar filters
st.sidebar.header("Filters")

default_start = datetime.now() - timedelta(days=30)
default_end = datetime.now()

start_date = st.sidebar.date_input("Start Date", default_start)
end_date = st.sidebar.date_input("End Date", default_end)

# Tenant selector
tenants_query = "SELECT DISTINCT tenant_id, tenant_name FROM mart.dim_tenant ORDER BY tenant_name"
tenants_df = sf_conn.execute_query(tenants_query)
selected_tenant = st.sidebar.selectbox(
    "Tenant",
    options=tenants_df['TENANT_NAME'].tolist(),
    index=0
)
tenant_id = tenants_df[tenants_df['TENANT_NAME'] == selected_tenant]['TENANT_ID'].values[0]

# Aggregation level
agg_level = st.sidebar.radio("View By", ["Fleet", "Location", "Machine Type", "Individual Machine"])

# Benchmark comparison
show_benchmark = st.sidebar.checkbox("Show Industry Benchmark", value=True)

# Fetch OEE data
@st.cache_data(ttl=300)
def get_oee_metrics(tenant_id, start, end, agg_level):
    """Fetch OEE metrics from Snowflake."""

    group_by_clause = {
        "Fleet": "d.date",
        "Location": "d.date, dm.location",
        "Machine Type": "d.date, dm.machine_type",
        "Individual Machine": "d.date, dm.machine_name"
    }[agg_level]

    select_dims = {
        "Fleet": "d.date",
        "Location": "d.date, dm.location",
        "Machine Type": "d.date, dm.machine_type",
        "Individual Machine": "d.date, dm.machine_name, dm.location"
    }[agg_level]

    query = f"""
    SELECT
        {select_dims},
        AVG(oee.availability) as availability,
        AVG(oee.performance) as performance,
        AVG(oee.quality) as quality,
        AVG(oee.oee_score) as oee_score,
        SUM(oee.planned_production_time_minutes) as planned_time,
        SUM(oee.actual_production_time_minutes) as actual_time,
        SUM(oee.ideal_cycle_time_minutes) as ideal_time,
        SUM(oee.total_units) as total_units,
        SUM(oee.good_units) as good_units
    FROM mart.fact_oee oee
    JOIN mart.dim_machine dm ON oee.machine_id = dm.machine_id
    JOIN mart.dim_date d ON oee.date_key = d.date_key
    WHERE oee.tenant_id = '{tenant_id}'
        AND d.date BETWEEN '{start}' AND '{end}'
    GROUP BY {group_by_clause}
    ORDER BY d.date
    """
    return sf_conn.execute_query(query)

# Fetch machine comparison
@st.cache_data(ttl=300)
def get_machine_comparison(tenant_id, start, end):
    """Fetch OEE comparison across machines."""
    query = f"""
    SELECT
        dm.machine_name,
        dm.location,
        dm.machine_type,
        AVG(oee.availability) as availability,
        AVG(oee.performance) as performance,
        AVG(oee.quality) as quality,
        AVG(oee.oee_score) as oee_score,
        SUM(oee.total_units) as total_units,
        SUM(oee.good_units) as good_units
    FROM mart.fact_oee oee
    JOIN mart.dim_machine dm ON oee.machine_id = dm.machine_id
    WHERE oee.tenant_id = '{tenant_id}'
        AND oee.date_key BETWEEN '{start}' AND '{end}'
    GROUP BY dm.machine_name, dm.location, dm.machine_type
    ORDER BY oee_score DESC
    """
    return sf_conn.execute_query(query)

# Fetch loss analysis
@st.cache_data(ttl=300)
def get_loss_analysis(tenant_id, start, end):
    """Fetch six big losses breakdown."""
    query = f"""
    SELECT
        dm.machine_name,
        loss_category,
        loss_type,
        SUM(loss_minutes) as total_loss_minutes,
        SUM(loss_cost_gbp) as total_loss_cost
    FROM mart.fact_oee_losses losses
    JOIN mart.dim_machine dm ON losses.machine_id = dm.machine_id
    WHERE losses.tenant_id = '{tenant_id}'
        AND losses.date_key BETWEEN '{start}' AND '{end}'
    GROUP BY dm.machine_name, loss_category, loss_type
    ORDER BY total_loss_minutes DESC
    """
    return sf_conn.execute_query(query)

try:
    oee_df = get_oee_metrics(
        tenant_id,
        start_date.strftime('%Y-%m-%d'),
        end_date.strftime('%Y-%m-%d'),
        agg_level
    )

    if oee_df.empty:
        st.warning("No OEE data found for the selected period.")
        st.stop()

    machine_comp_df = get_machine_comparison(
        tenant_id,
        start_date.strftime('%Y-%m-%d'),
        end_date.strftime('%Y-%m-%d')
    )

    loss_df = get_loss_analysis(
        tenant_id,
        start_date.strftime('%Y-%m-%d'),
        end_date.strftime('%Y-%m-%d')
    )

    # Calculate overall averages
    avg_availability = oee_df['AVAILABILITY'].mean() * 100
    avg_performance = oee_df['PERFORMANCE'].mean() * 100
    avg_quality = oee_df['QUALITY'].mean() * 100
    avg_oee = oee_df['OEE_SCORE'].mean() * 100

    # Industry benchmarks
    benchmark_availability = 90.0
    benchmark_performance = 95.0
    benchmark_quality = 99.0
    benchmark_oee = 85.0  # World class: 85%+

    # Summary metrics
    st.subheader("OEE Summary")

    col1, col2, col3, col4 = st.columns(4)

    with col1:
        delta_a = avg_availability - benchmark_availability if show_benchmark else None
        st.metric(
            "Availability",
            f"{avg_availability:.1f}%",
            delta=f"{delta_a:+.1f}% vs benchmark" if delta_a is not None else None
        )

    with col2:
        delta_p = avg_performance - benchmark_performance if show_benchmark else None
        st.metric(
            "Performance",
            f"{avg_performance:.1f}%",
            delta=f"{delta_p:+.1f}% vs benchmark" if delta_p is not None else None
        )

    with col3:
        delta_q = avg_quality - benchmark_quality if show_benchmark else None
        st.metric(
            "Quality",
            f"{avg_quality:.1f}%",
            delta=f"{delta_q:+.1f}% vs benchmark" if delta_q is not None else None
        )

    with col4:
        delta_oee = avg_oee - benchmark_oee if show_benchmark else None
        oee_class = "World Class" if avg_oee >= 85 else "Good" if avg_oee >= 60 else "Fair" if avg_oee >= 40 else "Poor"
        st.metric(
            "Overall OEE",
            f"{avg_oee:.1f}%",
            delta=f"{oee_class} | {delta_oee:+.1f}% vs benchmark" if delta_oee is not None else oee_class
        )

    # OEE components breakdown
    st.subheader("OEE Components Analysis")

    col1, col2 = st.columns(2)

    with col1:
        # Waterfall chart showing OEE calculation
        fig_waterfall = go.Figure(go.Waterfall(
            name="OEE",
            orientation="v",
            measure=["relative", "relative", "relative", "total"],
            x=["Availability", "Performance", "Quality", "OEE"],
            y=[avg_availability, -(100-avg_performance), -(100-avg_quality), 0],
            text=[f"{avg_availability:.1f}%", f"{avg_performance:.1f}%", f"{avg_quality:.1f}%", f"{avg_oee:.1f}%"],
            textposition="outside",
            connector={"line": {"color": "rgb(63, 63, 63)"}},
        ))

        if show_benchmark:
            fig_waterfall.add_hline(
                y=benchmark_oee,
                line_dash="dash",
                line_color="green",
                annotation_text="World Class (85%)"
            )

        fig_waterfall.update_layout(
            title="OEE Breakdown (A × P × Q)",
            yaxis_title="Percentage (%)",
            height=400,
            showlegend=False
        )
        st.plotly_chart(fig_waterfall, use_container_width=True)

    with col2:
        # Radar chart comparing to benchmark
        categories = ['Availability', 'Performance', 'Quality', 'OEE']

        fig_radar = go.Figure()

        fig_radar.add_trace(go.Scatterpolar(
            r=[avg_availability, avg_performance, avg_quality, avg_oee],
            theta=categories,
            fill='toself',
            name='Actual',
            line_color='#1f77b4'
        ))

        if show_benchmark:
            fig_radar.add_trace(go.Scatterpolar(
                r=[benchmark_availability, benchmark_performance, benchmark_quality, benchmark_oee],
                theta=categories,
                fill='toself',
                name='Benchmark',
                line_color='#2ca02c',
                line_dash='dash'
            ))

        fig_radar.update_layout(
            polar=dict(radialaxis=dict(visible=True, range=[0, 100])),
            title="OEE Components vs Benchmark",
            height=400,
            showlegend=True
        )
        st.plotly_chart(fig_radar, use_container_width=True)

    # OEE trends over time
    st.subheader("OEE Trends")

    # Aggregate by date
    if agg_level == "Fleet":
        daily_oee = oee_df.groupby('DATE').agg({
            'AVAILABILITY': 'mean',
            'PERFORMANCE': 'mean',
            'QUALITY': 'mean',
            'OEE_SCORE': 'mean'
        }).reset_index()

        fig_trends = go.Figure()

        fig_trends.add_trace(go.Scatter(
            x=daily_oee['DATE'],
            y=daily_oee['AVAILABILITY'] * 100,
            mode='lines',
            name='Availability',
            line=dict(color='#1f77b4', width=2)
        ))

        fig_trends.add_trace(go.Scatter(
            x=daily_oee['DATE'],
            y=daily_oee['PERFORMANCE'] * 100,
            mode='lines',
            name='Performance',
            line=dict(color='#ff7f0e', width=2)
        ))

        fig_trends.add_trace(go.Scatter(
            x=daily_oee['DATE'],
            y=daily_oee['QUALITY'] * 100,
            mode='lines',
            name='Quality',
            line=dict(color='#2ca02c', width=2)
        ))

        fig_trends.add_trace(go.Scatter(
            x=daily_oee['DATE'],
            y=daily_oee['OEE_SCORE'] * 100,
            mode='lines',
            name='OEE',
            line=dict(color='#d62728', width=3)
        ))

        if show_benchmark:
            fig_trends.add_hline(
                y=benchmark_oee,
                line_dash="dash",
                line_color="green",
                annotation_text="World Class"
            )

        fig_trends.update_layout(
            title="Daily OEE Component Trends",
            xaxis_title="Date",
            yaxis_title="Percentage (%)",
            height=400,
            hovermode='x unified'
        )
        st.plotly_chart(fig_trends, use_container_width=True)

    # Machine comparison
    st.subheader("Machine Performance Comparison")

    if not machine_comp_df.empty:
        col1, col2 = st.columns(2)

        with col1:
            # Top/bottom performers
            top_5 = machine_comp_df.head(5)
            bottom_5 = machine_comp_df.tail(5)

            fig_comparison = go.Figure()

            fig_comparison.add_trace(go.Bar(
                name='Top 5',
                y=top_5['MACHINE_NAME'],
                x=top_5['OEE_SCORE'] * 100,
                orientation='h',
                marker_color='#2ca02c',
                text=top_5['OEE_SCORE'].apply(lambda x: f"{x*100:.1f}%"),
                textposition='auto'
            ))

            fig_comparison.add_trace(go.Bar(
                name='Bottom 5',
                y=bottom_5['MACHINE_NAME'],
                x=bottom_5['OEE_SCORE'] * 100,
                orientation='h',
                marker_color='#d62728',
                text=bottom_5['OEE_SCORE'].apply(lambda x: f"{x*100:.1f}%"),
                textposition='auto'
            ))

            if show_benchmark:
                fig_comparison.add_vline(x=benchmark_oee, line_dash="dash", line_color="blue", annotation_text="Benchmark")

            fig_comparison.update_layout(
                title="Top & Bottom 5 Machines by OEE",
                xaxis_title="OEE (%)",
                yaxis_title="Machine",
                height=400,
                barmode='group'
            )
            st.plotly_chart(fig_comparison, use_container_width=True)

        with col2:
            # Scatter: Availability vs Performance
            fig_scatter = go.Figure()

            fig_scatter.add_trace(go.Scatter(
                x=machine_comp_df['AVAILABILITY'] * 100,
                y=machine_comp_df['PERFORMANCE'] * 100,
                mode='markers',
                marker=dict(
                    size=machine_comp_df['OEE_SCORE'] * 50,  # Size by OEE
                    color=machine_comp_df['QUALITY'] * 100,  # Color by Quality
                    colorscale='RdYlGn',
                    showscale=True,
                    colorbar=dict(title="Quality (%)")
                ),
                text=machine_comp_df['MACHINE_NAME'],
                hovertemplate='<b>%{text}</b><br>Availability: %{x:.1f}%<br>Performance: %{y:.1f}%<extra></extra>'
            ))

            if show_benchmark:
                fig_scatter.add_vline(x=benchmark_availability, line_dash="dash", line_color="gray")
                fig_scatter.add_hline(y=benchmark_performance, line_dash="dash", line_color="gray")

            fig_scatter.update_layout(
                title="Availability vs Performance (size=OEE, color=Quality)",
                xaxis_title="Availability (%)",
                yaxis_title="Performance (%)",
                height=400
            )
            st.plotly_chart(fig_scatter, use_container_width=True)

    # Six Big Losses analysis
    if not loss_df.empty:
        st.subheader("Six Big Losses Analysis")

        # Aggregate by category
        losses_by_category = loss_df.groupby('LOSS_CATEGORY').agg({
            'TOTAL_LOSS_MINUTES': 'sum',
            'TOTAL_LOSS_COST': 'sum'
        }).reset_index().sort_values('TOTAL_LOSS_MINUTES', ascending=False)

        col1, col2 = st.columns(2)

        with col1:
            # Pareto chart of losses
            fig_pareto = go.Figure()

            # Bar chart
            fig_pareto.add_trace(go.Bar(
                x=losses_by_category['LOSS_CATEGORY'],
                y=losses_by_category['TOTAL_LOSS_MINUTES'],
                name='Loss Minutes',
                marker_color='#ff7f0e',
                yaxis='y'
            ))

            # Cumulative line
            cumulative = losses_by_category['TOTAL_LOSS_MINUTES'].cumsum() / losses_by_category['TOTAL_LOSS_MINUTES'].sum() * 100

            fig_pareto.add_trace(go.Scatter(
                x=losses_by_category['LOSS_CATEGORY'],
                y=cumulative,
                name='Cumulative %',
                mode='lines+markers',
                marker_color='#d62728',
                yaxis='y2'
            ))

            fig_pareto.update_layout(
                title="Six Big Losses - Pareto Analysis",
                xaxis_title="Loss Category",
                yaxis=dict(title="Loss Time (minutes)", side='left'),
                yaxis2=dict(title="Cumulative %", side='right', overlaying='y', range=[0, 100]),
                height=400,
                hovermode='x unified'
            )
            st.plotly_chart(fig_pareto, use_container_width=True)

        with col2:
            # Cost impact by category
            fig_loss_cost = go.Figure(data=[go.Pie(
                labels=losses_by_category['LOSS_CATEGORY'],
                values=losses_by_category['TOTAL_LOSS_COST'],
                hole=0.4,
                hovertemplate='<b>%{label}</b><br>Cost: £%{value:,.2f}<br>%{percent}<extra></extra>'
            )])

            fig_loss_cost.update_layout(
                title="Cost Impact by Loss Category",
                height=400
            )
            st.plotly_chart(fig_loss_cost, use_container_width=True)

        # Detailed losses by type
        st.markdown("**Detailed Loss Breakdown:**")

        # Top 10 losses by time
        top_losses = loss_df.nlargest(10, 'TOTAL_LOSS_MINUTES')[['MACHINE_NAME', 'LOSS_CATEGORY', 'LOSS_TYPE', 'TOTAL_LOSS_MINUTES', 'TOTAL_LOSS_COST']]

        top_losses['TOTAL_LOSS_MINUTES'] = top_losses['TOTAL_LOSS_MINUTES'].apply(lambda x: f"{x:,.0f} min ({x/60:.1f} hrs)")
        top_losses['TOTAL_LOSS_COST'] = top_losses['TOTAL_LOSS_COST'].apply(lambda x: f"£{x:,.2f}")

        st.dataframe(
            top_losses,
            use_container_width=True,
            hide_index=True,
            column_config={
                "MACHINE_NAME": st.column_config.TextColumn("Machine"),
                "LOSS_CATEGORY": st.column_config.TextColumn("Category"),
                "LOSS_TYPE": st.column_config.TextColumn("Type"),
                "TOTAL_LOSS_MINUTES": st.column_config.TextColumn("Time Lost"),
                "TOTAL_LOSS_COST": st.column_config.TextColumn("Cost Impact")
            }
        )

    # Machine comparison table
    st.subheader("Detailed Machine OEE")

    display_comp = machine_comp_df.copy()
    display_comp['AVAILABILITY'] = display_comp['AVAILABILITY'].apply(lambda x: f"{x*100:.1f}%")
    display_comp['PERFORMANCE'] = display_comp['PERFORMANCE'].apply(lambda x: f"{x*100:.1f}%")
    display_comp['QUALITY'] = display_comp['QUALITY'].apply(lambda x: f"{x*100:.1f}%")
    display_comp['OEE_SCORE'] = display_comp['OEE_SCORE'].apply(lambda x: f"{x*100:.1f}%")

    st.dataframe(
        display_comp,
        use_container_width=True,
        hide_index=True,
        column_config={
            "MACHINE_NAME": st.column_config.TextColumn("Machine"),
            "LOCATION": st.column_config.TextColumn("Location"),
            "MACHINE_TYPE": st.column_config.TextColumn("Type"),
            "AVAILABILITY": st.column_config.TextColumn("Availability"),
            "PERFORMANCE": st.column_config.TextColumn("Performance"),
            "QUALITY": st.column_config.TextColumn("Quality"),
            "OEE_SCORE": st.column_config.TextColumn("OEE"),
            "TOTAL_UNITS": st.column_config.NumberColumn("Total Units", format="%d"),
            "GOOD_UNITS": st.column_config.NumberColumn("Good Units", format="%d")
        }
    )

    # Export
    st.subheader("Export OEE Data")
    col1, col2 = st.columns(2)

    with col1:
        csv_oee = machine_comp_df.to_csv(index=False).encode('utf-8')
        st.download_button(
            label="Download OEE Summary",
            data=csv_oee,
            file_name=f"oee_summary_{start_date}_{end_date}.csv",
            mime="text/csv"
        )

    with col2:
        if not loss_df.empty:
            csv_losses = loss_df.to_csv(index=False).encode('utf-8')
            st.download_button(
                label="Download Loss Analysis",
                data=csv_losses,
                file_name=f"oee_losses_{start_date}_{end_date}.csv",
                mime="text/csv"
            )

except Exception as e:
    st.error(f"Error fetching data: {str(e)}")
    st.exception(e)
```

---

## Implementation Summary

All 8 Streamlit dashboard pages are now complete with:

✅ **Production-ready code** - Complete implementations with error handling
✅ **Snowflake integration** - Queries from mart views with caching
✅ **Interactive visualizations** - Plotly charts with drill-down capabilities
✅ **Filters and controls** - Date ranges, tenant/machine selectors, view modes
✅ **Real-time updates** - Optional auto-refresh on timeline page
✅ **Export capabilities** - CSV downloads for all data
✅ **Responsive layouts** - Works on different screen sizes
✅ **Color-coded states** - Consistent OFF/IDLE/WORKING color scheme
✅ **Alert highlighting** - Critical alerts prominently displayed
✅ **Benchmark comparisons** - Industry standards on OEE page

## Next Steps

1. **Deploy** the Streamlit app using the complete file structure
2. **Configure** the `.streamlit/secrets.toml` with Snowflake credentials
3. **Test** each dashboard page with real data
4. **Customize** thresholds and benchmarks for your specific use case
5. **Add** authentication (see next document for auth guide)
6. **Deploy** to production (Docker/Cloud)

## Related Documents

- [STREAMLIT_DASHBOARD_GUIDE.md](STREAMLIT_DASHBOARD_GUIDE.md) - Project structure and utilities
- [SMDH_Data_Layer_Implementation_Guide.md](SMDH_Data_Layer_Implementation_Guide.md) - Backend SQL/Snowpark
- [DATA_INGESTION_MAPPING.md](DATA_INGESTION_MAPPING.md) - Data flow from sensors
