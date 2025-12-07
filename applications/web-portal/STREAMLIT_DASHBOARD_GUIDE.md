# Streamlit Dashboard Implementation Guide

## Overview

This guide provides complete implementation details for building the Streamlit-based dashboard portal that connects to your Snowflake MART layer and delivers the manufacturing analytics dashboards.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Streamlit App                          │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐            │
│  │ Home/    │  │ Fleet    │  │ Machine  │  ... x8     │
│  │ Overview │  │ Util     │  │ Timeline │  dashboards │
│  └──────────┘  └──────────┘  └──────────┘            │
└─────────────────────────────────────────────────────────┘
                         ↓
              Snowflake Python Connector
                         ↓
┌─────────────────────────────────────────────────────────┐
│            Snowflake MART Schema                        │
│  ┌────────────────┐  ┌────────────────┐               │
│  │ Analytics Views│  │  Fact Tables   │               │
│  │ (Optimized)    │  │  (Pre-agg)     │               │
│  └────────────────┘  └────────────────┘               │
└─────────────────────────────────────────────────────────┘
```

## Project Structure

```
streamlit-app/
├── .streamlit/
│   ├── config.toml          # Streamlit configuration
│   └── secrets.toml         # Snowflake credentials (gitignored)
├── pages/
│   ├── 01_Fleet_Utilization.py
│   ├── 02_Machine_Timeline.py
│   ├── 03_Production_Events.py
│   ├── 04_Energy_Cost.py
│   ├── 05_Anomalies.py
│   ├── 06_Machine_Health.py
│   ├── 07_Environmental.py
│   └── 08_OEE_Benchmarking.py
├── utils/
│   ├── __init__.py
│   ├── snowflake_connector.py  # DB connection utilities
│   ├── chart_builders.py       # Reusable chart functions
│   ├── auth.py                 # Authentication/authorization
│   └── cache_manager.py        # Caching strategies
├── assets/
│   ├── logo.png
│   └── styles.css
├── Home.py                      # Main entry point
├── requirements.txt
└── README.md
```

## Setup and Configuration

### requirements.txt

```txt
streamlit==1.29.0
snowflake-connector-python==3.6.0
snowflake-snowpark-python==1.11.1
pandas==2.1.4
plotly==5.18.0
altair==5.2.0
python-dotenv==1.0.0
```

### .streamlit/config.toml

```toml
[theme]
primaryColor = "#2ca02c"
backgroundColor = "#0e1117"
secondaryBackgroundColor = "#262730"
textColor = "#fafafa"
font = "sans serif"

[server]
port = 8501
enableCORS = false
enableXsrfProtection = true
maxUploadSize = 200

[browser]
gatherUsageStats = false
```

### .streamlit/secrets.toml (Template - DO NOT COMMIT)

```toml
[snowflake]
account = "your-account.eu-west-2"
user = "streamlit_user"
password = "your-secure-password"
warehouse = "smdh_analytics_wh"
database = "smdh_tenant_company_a"
schema = "analytics"
role = "smdh_tenant_analyst_company_a"

[auth]
admin_users = ["admin@company.com"]
allowed_domains = ["company.com"]
```

## Core Utilities

### utils/snowflake_connector.py

```python
"""
Snowflake connection management with connection pooling and caching
"""
import streamlit as st
import snowflake.connector
from snowflake.connector import DictCursor
import pandas as pd
from typing import Dict, Any, Optional
import logging

logger = logging.getLogger(__name__)


class SnowflakeConnection:
    """Manages Snowflake database connections with connection pooling"""

    def __init__(self):
        self.connection = None

    @st.cache_resource
    def get_connection(_self):
        """Get or create a Snowflake connection (singleton pattern)"""
        if _self.connection is None or _self.connection.is_closed():
            try:
                _self.connection = snowflake.connector.connect(
                    account=st.secrets["snowflake"]["account"],
                    user=st.secrets["snowflake"]["user"],
                    password=st.secrets["snowflake"]["password"],
                    warehouse=st.secrets["snowflake"]["warehouse"],
                    database=st.secrets["snowflake"]["database"],
                    schema=st.secrets["snowflake"]["schema"],
                    role=st.secrets["snowflake"]["role"],
                    client_session_keep_alive=True,
                    network_timeout=30
                )
                logger.info("Snowflake connection established")
            except Exception as e:
                logger.error(f"Failed to connect to Snowflake: {e}")
                st.error(f"Database connection failed: {e}")
                raise
        return _self.connection

    def execute_query(self, query: str, params: Optional[Dict[str, Any]] = None) -> pd.DataFrame:
        """Execute a query and return results as DataFrame"""
        conn = self.get_connection()
        try:
            if params:
                df = pd.read_sql(query, conn, params=params)
            else:
                df = pd.read_sql(query, conn)
            return df
        except Exception as e:
            logger.error(f"Query execution failed: {e}")
            st.error(f"Query failed: {e}")
            raise

    def execute_with_cursor(self, query: str, params: Optional[tuple] = None):
        """Execute query with cursor for non-SELECT operations"""
        conn = self.get_connection()
        cursor = conn.cursor(DictCursor)
        try:
            if params:
                cursor.execute(query, params)
            else:
                cursor.execute(query)
            conn.commit()
            return cursor
        except Exception as e:
            logger.error(f"Cursor execution failed: {e}")
            conn.rollback()
            raise
        finally:
            cursor.close()


# Global connection instance
sf_conn = SnowflakeConnection()


@st.cache_data(ttl=300)  # Cache for 5 minutes
def get_fleet_utilization(start_date: str, end_date: str, site_filter: Optional[str] = None) -> pd.DataFrame:
    """Get fleet utilization data with optional filtering"""
    query = """
    SELECT * FROM v_fleet_utilization
    WHERE date_key BETWEEN %(start_date)s AND %(end_date)s
    """

    if site_filter:
        query += " AND site_name = %(site_filter)s"

    query += " ORDER BY idle_percentage DESC"

    params = {
        'start_date': start_date,
        'end_date': end_date,
        'site_filter': site_filter
    }

    return sf_conn.execute_query(query, params)


@st.cache_data(ttl=60)  # Cache for 1 minute (near real-time)
def get_current_machine_status() -> pd.DataFrame:
    """Get current status of all machines"""
    query = "SELECT * FROM v_current_machine_status ORDER BY machine_name"
    return sf_conn.execute_query(query)


@st.cache_data(ttl=300)
def get_machine_timeline(machine_name: str, date: str) -> pd.DataFrame:
    """Get detailed timeline for a specific machine and date"""
    query = """
    SELECT * FROM v_machine_timeline
    WHERE machine_name = %(machine_name)s
        AND DATE(timestamp_utc) = %(date)s
    ORDER BY timestamp_utc
    """
    params = {'machine_name': machine_name, 'date': date}
    return sf_conn.execute_query(query, params)


@st.cache_data(ttl=300)
def get_production_events(start_date: str, end_date: str, machine_filter: Optional[str] = None) -> pd.DataFrame:
    """Get production events with clustering"""
    query = """
    SELECT * FROM v_production_events
    WHERE DATE(start_timestamp) BETWEEN %(start_date)s AND %(end_date)s
    """

    if machine_filter:
        query += " AND machine_name = %(machine_filter)s"

    query += " ORDER BY start_timestamp DESC"

    params = {
        'start_date': start_date,
        'end_date': end_date,
        'machine_filter': machine_filter
    }

    return sf_conn.execute_query(query, params)


@st.cache_data(ttl=300)
def get_energy_cost_analysis(start_date: str, end_date: str) -> pd.DataFrame:
    """Get energy and cost analysis data"""
    query = """
    SELECT * FROM v_energy_cost_analysis
    WHERE date_key BETWEEN %(start_date)s AND %(end_date)s
    ORDER BY date_key DESC, total_cost_gbp DESC
    """
    params = {'start_date': start_date, 'end_date': end_date}
    return sf_conn.execute_query(query, params)


@st.cache_data(ttl=300)
def get_anomalies(start_date: str, end_date: str, severity: Optional[str] = None) -> pd.DataFrame:
    """Get detected anomalies"""
    query = """
    SELECT * FROM v_anomalies
    WHERE DATE(detected_timestamp) BETWEEN %(start_date)s AND %(end_date)s
    """

    if severity:
        query += " AND severity = %(severity)s"

    query += " ORDER BY detected_timestamp DESC"

    params = {
        'start_date': start_date,
        'end_date': end_date,
        'severity': severity
    }

    return sf_conn.execute_query(query, params)


@st.cache_data(ttl=600)  # Cache for 10 minutes
def get_oee_summary(start_date: str, end_date: str) -> pd.DataFrame:
    """Get OEE summary data"""
    query = """
    SELECT * FROM v_oee_summary
    WHERE date_key BETWEEN %(start_date)s AND %(end_date)s
    ORDER BY oee_percentage DESC
    """
    params = {'start_date': start_date, 'end_date': end_date}
    return sf_conn.execute_query(query, params)


def clear_all_caches():
    """Clear all cached data (use when data refresh is needed)"""
    st.cache_data.clear()
    logger.info("All caches cleared")
```

### utils/chart_builders.py

```python
"""
Reusable chart building functions using Plotly
"""
import plotly.graph_objects as go
import plotly.express as px
import pandas as pd
from typing import List, Dict, Any


# Color scheme matching your design
COLORS = {
    'off': '#d62728',      # Red
    'idle': '#ff7f0e',     # Orange
    'working': '#2ca02c',  # Green
    'peak': '#e377c2',     # Pink
    'shoulder': '#bcbd22', # Yellow-green
    'offpeak': '#17becf'   # Cyan
}


def create_stacked_bar_utilization(df: pd.DataFrame) -> go.Figure:
    """Create stacked bar chart for machine utilization"""
    fig = go.Figure()

    fig.add_trace(go.Bar(
        name='Off',
        x=df['machine_name'],
        y=df['off_percentage'],
        marker_color=COLORS['off']
    ))

    fig.add_trace(go.Bar(
        name='Idle',
        x=df['machine_name'],
        y=df['idle_percentage'],
        marker_color=COLORS['idle']
    ))

    fig.add_trace(go.Bar(
        name='Working',
        x=df['machine_name'],
        y=df['working_percentage'],
        marker_color=COLORS['working']
    ))

    fig.update_layout(
        barmode='stack',
        title='Machine Utilization Breakdown',
        xaxis_title='Machine',
        yaxis_title='Percentage (%)',
        hovermode='x unified',
        xaxis_tickangle=-45,
        height=500
    )

    return fig


def create_timeline_chart(df: pd.DataFrame) -> go.Figure:
    """Create Gantt-style timeline chart for machine states"""

    # Create state segments
    segments = []
    for i in range(len(df) - 1):
        segments.append({
            'Start': df.iloc[i]['timestamp_utc'],
            'Finish': df.iloc[i + 1]['timestamp_utc'],
            'State': df.iloc[i]['state'],
            'Power': df.iloc[i]['power_kw']
        })

    df_segments = pd.DataFrame(segments)

    fig = px.timeline(
        df_segments,
        x_start='Start',
        x_end='Finish',
        y=['State'] * len(df_segments),
        color='State',
        color_discrete_map=COLORS,
        hover_data=['Power']
    )

    fig.update_layout(
        title='Machine State Timeline',
        xaxis_title='Time',
        yaxis_title='',
        height=300,
        showlegend=True
    )

    return fig


def create_production_histogram(df: pd.DataFrame) -> go.Figure:
    """Create histogram of production event durations with clustering"""

    fig = go.Figure()

    # Get unique clusters
    clusters = df['event_type'].unique()

    for cluster in clusters:
        cluster_data = df[df['event_type'] == cluster]
        fig.add_trace(go.Histogram(
            x=cluster_data['duration_minutes'],
            name=cluster,
            opacity=0.7,
            nbinsx=30
        ))

    fig.update_layout(
        title='Production Event Duration Distribution',
        xaxis_title='Duration (minutes)',
        yaxis_title='Count',
        barmode='overlay',
        height=400
    )

    return fig


def create_energy_breakdown_pie(df: pd.DataFrame) -> go.Figure:
    """Create pie chart for energy breakdown by state"""

    # Aggregate by state
    energy_by_state = {
        'Working': df['working_energy_kwh'].sum(),
        'Idle': df['idle_energy_kwh'].sum(),
        'Off': df['off_energy_kwh'].sum()
    }

    fig = go.Figure(data=[go.Pie(
        labels=list(energy_by_state.keys()),
        values=list(energy_by_state.values()),
        marker_colors=[COLORS['working'], COLORS['idle'], COLORS['off']],
        hole=0.3
    )])

    fig.update_layout(
        title='Energy Consumption by State',
        height=400
    )

    return fig


def create_cost_by_tariff(df: pd.DataFrame) -> go.Figure:
    """Create stacked bar for cost by tariff band and state"""

    # Aggregate by machine
    machines = df['machine_name'].unique()

    fig = go.Figure()

    # Working state by tariff
    fig.add_trace(go.Bar(
        name='Working (Peak)',
        x=machines,
        y=[df[df['machine_name'] == m]['peak_cost_gbp'].sum() *
           (df[df['machine_name'] == m]['working_percentage'].mean() / 100)
           for m in machines],
        marker_color=COLORS['peak']
    ))

    # Idle state
    fig.add_trace(go.Bar(
        name='Idle',
        x=machines,
        y=[df[df['machine_name'] == m]['idle_cost_gbp'].sum() for m in machines],
        marker_color=COLORS['idle']
    ))

    fig.update_layout(
        barmode='stack',
        title='Energy Cost by Machine and State',
        xaxis_title='Machine',
        yaxis_title='Cost (£)',
        height=500
    )

    return fig


def create_oee_radar(df: pd.DataFrame, machine_name: str) -> go.Figure:
    """Create radar chart for OEE components"""

    machine_data = df[df['machine_name'] == machine_name].iloc[0]

    categories = ['Availability', 'Performance', 'Quality', 'OEE']
    values = [
        machine_data['availability_percentage'],
        machine_data['performance_percentage'],
        machine_data.get('quality_percentage', 100),  # Default if not available
        machine_data['oee_percentage']
    ]

    fig = go.Figure()

    fig.add_trace(go.Scatterpolar(
        r=values,
        theta=categories,
        fill='toself',
        name=machine_name
    ))

    fig.update_layout(
        polar=dict(
            radialaxis=dict(
                visible=True,
                range=[0, 100]
            )
        ),
        showlegend=True,
        title=f'OEE Breakdown - {machine_name}',
        height=400
    ))

    return fig
```

### Home.py (Main Dashboard Entry)

```python
"""
SMDH Manufacturing Analytics Portal - Home Page
"""
import streamlit as st
from datetime import datetime, timedelta
import pandas as pd
from utils.snowflake_connector import (
    get_current_machine_status,
    get_fleet_utilization
)
from utils.chart_builders import create_stacked_bar_utilization

# Page configuration
st.set_page_config(
    page_title="SMDH Analytics Portal",
    page_icon="🏭",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Custom CSS
st.markdown("""
<style>
    .main-header {
        font-size: 3rem;
        font-weight: bold;
        color: #2ca02c;
    }
    .metric-card {
        background-color: #262730;
        padding: 1rem;
        border-radius: 0.5rem;
        border-left: 4px solid #2ca02c;
    }
    .status-online {
        color: #2ca02c;
    }
    .status-offline {
        color: #d62728;
    }
</style>
""", unsafe_allow_html=True)

# Header
st.markdown('<p class="main-header">🏭 SMDH Manufacturing Analytics</p>', unsafe_allow_html=True)
st.markdown("Real-time insights into machine utilization, production, energy, and quality")

# Sidebar navigation
with st.sidebar:
    st.image("assets/logo.png", use_column_width=True) if st.sidebar else None
    st.markdown("### Navigation")
    st.markdown("Use the pages in the sidebar to explore different analytics dashboards")

    # Tenant selector (if multi-tenant)
    st.markdown("---")
    st.markdown("### Settings")
    tenant = st.selectbox("Select Facility", ["Main Factory", "Site A", "Site B"])

    # Date range for overview
    date_range = st.date_input(
        "Overview Period",
        value=(datetime.now() - timedelta(days=7), datetime.now()),
        max_value=datetime.now()
    )

# Main content
try:
    # Get current status
    with st.spinner("Loading current status..."):
        current_status = get_current_machine_status()

    # KPI Row
    st.markdown("## 📊 Current Status")
    col1, col2, col3, col4 = st.columns(4)

    with col1:
        total_machines = len(current_status)
        st.metric("Total Machines", total_machines, "Monitored")

    with col2:
        online_machines = (current_status['status'] != 'OFFLINE').sum()
        st.metric("Online", online_machines, f"{online_machines/total_machines*100:.1f}%")

    with col3:
        working_machines = (current_status['current_state'] == 'WORKING').sum()
        st.metric("Working Now", working_machines, f"{working_machines/total_machines*100:.1f}%")

    with col4:
        idle_machines = (current_status['current_state'] == 'IDLE').sum()
        st.metric("Idle", idle_machines, "⚠️" if idle_machines > total_machines * 0.3 else "")

    # Machine status table
    st.markdown("## 🔧 Machine Status")

    # Add status indicators
    def status_indicator(row):
        if row['status'] == 'OFFLINE':
            return '🔴'
        elif row['current_state'] == 'WORKING':
            return '🟢'
        elif row['current_state'] == 'IDLE':
            return '🟡'
        else:
            return '⚫'

    current_status['Status'] = current_status.apply(status_indicator, axis=1)

    # Display table
    st.dataframe(
        current_status[[
            'Status', 'machine_name', 'line_name', 'site_name',
            'current_state', 'current_power_kw', 'minutes_since_update'
        ]].rename(columns={
            'machine_name': 'Machine',
            'line_name': 'Line',
            'site_name': 'Site',
            'current_state': 'State',
            'current_power_kw': 'Power (kW)',
            'minutes_since_update': 'Last Update (min)'
        }),
        use_container_width=True,
        hide_index=True
    )

    # Fleet overview
    st.markdown("## 📈 Fleet Utilization (Last 7 Days)")

    with st.spinner("Loading fleet data..."):
        fleet_data = get_fleet_utilization(
            str(date_range[0]),
            str(date_range[1])
        )

    if not fleet_data.empty:
        # Aggregate by machine
        fleet_agg = fleet_data.groupby('machine_name').agg({
            'off_percentage': 'mean',
            'idle_percentage': 'mean',
            'working_percentage': 'mean',
            'idle_cost_gbp': 'sum'
        }).reset_index()

        # Create chart
        fig = create_stacked_bar_utilization(fleet_agg)
        st.plotly_chart(fig, use_container_width=True)

        # Summary stats
        col1, col2, col3 = st.columns(3)

        with col1:
            avg_utilization = fleet_agg['working_percentage'].mean()
            st.metric("Average Utilization", f"{avg_utilization:.1f}%")

        with col2:
            total_idle_cost = fleet_agg['idle_cost_gbp'].sum()
            st.metric("Total Idle Cost", f"£{total_idle_cost:,.0f}")

        with col3:
            max_idle_machine = fleet_agg.loc[fleet_agg['idle_percentage'].idxmax(), 'machine_name']
            st.metric("Highest Idle", max_idle_machine)

    # Quick actions
    st.markdown("## ⚡ Quick Actions")

    col1, col2, col3 = st.columns(3)

    with col1:
        if st.button("📊 View Detailed Reports"):
            st.switch_page("pages/01_Fleet_Utilization.py")

    with col2:
        if st.button("🔍 Investigate Anomalies"):
            st.switch_page("pages/05_Anomalies.py")

    with col3:
        if st.button("⚡ Energy Analysis"):
            st.switch_page("pages/04_Energy_Cost.py")

except Exception as e:
    st.error(f"Error loading dashboard: {e}")
    st.exception(e)

# Footer
st.markdown("---")
st.markdown("SMDH Manufacturing Analytics Portal | Powered by Snowflake & Streamlit")
```

This guide continues in the next document with the individual dashboard pages...

Would you like me to continue with:
1. Individual dashboard page implementations (Fleet Utilization, Machine Timeline, etc.)?
2. Authentication and authorization setup?
3. Deployment guide (Docker, Cloud)?
4. Data ingestion mapping document?

Let me know which aspect you'd like me to develop next!