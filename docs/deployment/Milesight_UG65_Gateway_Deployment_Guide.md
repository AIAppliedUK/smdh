# Milesight UG65 LoRaWAN Gateway Deployment Guide
## SMDH Platform Integration

**Document Classification:** Internal Use Only
**Date:** 20 November 2025
**Author:** Architecture Team
**Status:** Deployment Guide

---

## Table of Contents

1. [Overview](#1-overview)
2. [Roles and Responsibilities](#2-roles-and-responsibilities)
3. [Deployment Summary](#3-deployment-summary)
4. [Prerequisites](#4-prerequisites)
5. [Gateway Physical Installation](#5-gateway-physical-installation)
6. [Initial Gateway Configuration](#6-initial-gateway-configuration)
7. [Network Server Integration](#7-network-server-integration)
8. [AWS IoT Core Integration](#8-aws-iot-core-integration)
9. [Testing and Validation](#9-testing-and-validation)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. Overview

This guide describes how to deploy Milesight UG65 LoRaWAN Gateways for integration with the SMDH (Smart Manufacturing Data Hub) platform. The UG65 gateway acts as a bridge between LoRaWAN sensor devices and cloud infrastructure.

### 1.1 Gateway Role in SMDH Architecture

```
LoRaWAN Sensor Devices (e.g., DevTank OSM)
        ↓ (LoRaWAN 868 MHz - EU)
Milesight UG65 Gateway
        ↓ (Ethernet/Wi-Fi/4G)
        ├→ The Things Network (TTN) → AWS IoT Core
        ├→ ChirpStack Network Server → AWS IoT Core
        └→ AWS IoT Core (Direct MQTT)
                ↓
        AWS Kinesis Data Streams
                ↓
        Snowflake Raw Tables
```

### 1.2 Gateway Capabilities

| Feature | Specification |
|---------|--------------|
| **LoRaWAN Standard** | LoRaWAN 1.0.2/1.0.3/1.1 |
| **Frequency Bands** | EU868, US915, AS923, AU915, IN865, RU864, KR920 |
| **Channels** | 8 channels (configurable) |
| **Max Devices** | 2000+ devices per gateway |
| **Backhaul Options** | Ethernet, Wi-Fi, 4G LTE (optional) |
| **Packet Forwarder** | Semtech UDP, MQTT Bridge |
| **Power** | PoE (802.3af), DC 12V |
| **Operating Temp** | -40°C to +70°C |
| **IP Rating** | IP67 (outdoor rated) |

### 1.3 Communication Modes

The UG65 supports multiple integration methods:

| Mode | Use Case | Configuration Complexity |
|------|----------|-------------------------|
| **Semtech UDP Packet Forwarder** | Connect to TTN, ChirpStack | Low |
| **MQTT Bridge** | Direct AWS IoT Core integration | Medium |
| **HTTP Integration** | Custom endpoints | Medium |

For SMDH deployments, we primarily use:
- **Semtech UDP** → The Things Network → AWS IoT Core
- **MQTT Bridge** → AWS IoT Core (direct connection)

---

## 2. Roles and Responsibilities

### 2.1 Role Definitions

#### Network Infrastructure Team

**Location:** Central/Remote

**Primary Responsibilities:**
- Gateway procurement and inventory
- Network configuration (IP addressing, VLANs, firewall rules)
- VPN setup (if required)
- LoRaWAN network server administration
- AWS IoT Core integration
- Certificate management
- Remote monitoring and maintenance

**Required Access:**
- Network equipment (switches, routers, firewalls)
- AWS Console (IoT Core, Kinesis)
- LoRaWAN Network Server admin
- Gateway web interface credentials

#### Onsite Installation Team

**Location:** Customer/Manufacturing site

**Primary Responsibilities:**
- Site survey for optimal gateway placement
- Physical gateway installation and mounting
- Power supply setup (PoE or DC power)
- Initial gateway configuration
- Network connectivity verification
- Signal coverage testing
- Documentation of installation (photos, GPS coordinates)

**Required Access:**
- Physical site access
- Ladder or lift equipment
- Laptop with Ethernet port
- Power tools for mounting
- Network credentials from Infrastructure Team

### 2.2 Deployment Workflow

```
┌─────────────────────────────────────────────────────────────────────┐
│                    GATEWAY DEPLOYMENT WORKFLOW                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  INFRASTRUCTURE TEAM             ONSITE INSTALLATION TEAM           │
│  ────────────────────            ─────────────────────              │
│                                                                     │
│  1. Receive deployment request                                      │
│         │                                                           │
│         ▼                                                           │
│  2. Prepare network config                                          │
│     - Allocate IP address                                           │
│     - Configure firewall rules                                      │
│     - Create VPN (if needed)                                        │
│         │                                                           │
│         ▼                                                           │
│  3. Generate gateway credentials                                    │
│     - AWS IoT certificates                                          │
│     - Network server keys                                           │
│         │                                                           │
│         ▼                                                           │
│  4. Prepare Config Package ──────────────► 5. Receive package       │
│                                                   │                 │
│                                                   ▼                 │
│                                            6. Conduct site survey   │
│                                                   │                 │
│                                                   ▼                 │
│                                            7. Install gateway       │
│                                               physically            │
│                                                   │                 │
│                                                   ▼                 │
│                                            8. Connect power +       │
│                                               network               │
│                                                   │                 │
│                                                   ▼                 │
│                                            9. Access web UI         │
│  10. Provide network settings ◄────────────      │                 │
│                                                   ▼                 │
│                                            11. Configure gateway    │
│                                                   │                 │
│                                                   ▼                 │
│                                            12. Test connectivity ───►│
│  13. Verify in network server                                       │
│         │                                                           │
│         ▼                                                           │
│  14. Register gateway in AWS IoT ◄─────── 15. Send Gateway EUI     │
│         │                                                           │
│         ▼                                                           │
│  16. Configure packet forwarder                                     │
│         │                                                           │
│         ▼                                                           │
│  17. Verify data flow ◄──────────────────── 18. Test with device   │
│         │                                                           │
│         ▼                                                           │
│  19. Enable monitoring                                              │
│         │                                                           │
│         ▼                                                           │
│  20. Handover to operations                                         │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.3 Communication Touchpoints

| Touchpoint | From | To | Information Exchanged |
|------------|------|----|-----------------------|
| **Deployment Request** | Project Manager | Infrastructure Team | Tenant ID, site location, coverage requirements |
| **Site Survey Report** | Onsite Team | Infrastructure Team | Coverage map, installation photos, obstacles |
| **Config Package** | Infrastructure Team | Onsite Team | IP address, network server details, certificates |
| **Gateway Registration** | Onsite Team | Infrastructure Team | Gateway EUI, serial number, GPS coordinates |
| **Connectivity Confirmation** | Infrastructure Team | Onsite Team | Network server registration confirmed |
| **Issue Escalation** | Onsite Team | Infrastructure Team | Connection failures, coverage gaps |

### 2.4 Gateway Configuration Package

Infrastructure Team prepares this package for gateway deployment:

**Package Contents:**

```
gateway_config_package/
├── README.txt                       # Quick start guide
├── gateway_info.json                # Gateway metadata
│   {
│     "gateway_eui": "24E124FFFEF12345",
│     "tenant_id": "company_a",
│     "site_id": "site_001",
│     "deployment_location": "Factory Building A - Roof",
│     "network_config": {
│       "ip_address": "10.50.100.10",
│       "subnet_mask": "255.255.255.0",
│       "gateway": "10.50.100.1",
│       "dns": ["8.8.8.8", "8.8.4.4"]
│     },
│     "network_server": "eu1.cloud.thethings.network"
│   }
├── network_server/
│   ├── ttn_credentials.txt          # TTN Gateway API key
│   └── chirpstack_config.txt        # ChirpStack endpoint
├── aws_certificates/                # For direct AWS IoT integration
│   ├── gateway-cert.pem
│   ├── gateway-private.key
│   └── AmazonRootCA1.pem
└── firewall_rules.txt               # Required port openings
```

---

## 3. Deployment Summary

### 3.1 Deployment Phases Overview

```
┌──────────────────────────────────────────────────┐
│  Phase 1: Pre-Deployment Planning               │  ← Infrastructure Team
│  - Site survey and coverage analysis            │
│  - Network design (IP, VLANs, firewall)          │
│  - Procure gateway and accessories               │
└────────────────────┬─────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────────┐
│  Phase 2: Physical Installation                 │  ← Onsite Team
│  - Mount gateway at optimal location            │
│  - Install antenna and lightning protection     │
│  - Connect power (PoE or DC)                     │
└────────────────────┬─────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────────┐
│  Phase 3: Network Configuration                 │  ← Both Teams
│  - Connect Ethernet/configure Wi-Fi             │
│  - Assign static IP or configure DHCP           │
│  - Test internet connectivity                   │
└────────────────────┬─────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────────┐
│  Phase 4: LoRaWAN Configuration                 │  ← Infrastructure Team
│  - Configure frequency plan (EU868)             │
│  - Set up packet forwarder                      │
│  - Register in network server                   │
└────────────────────┬─────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────────┐
│  Phase 5: Testing & Validation                  │  ← Both Teams
│  - Test with LoRaWAN device                     │
│  - Verify data reaches AWS IoT Core             │
│  - Conduct coverage test                        │
└──────────────────────────────────────────────────┘
```

### 3.2 Time Estimates

| Phase | Infrastructure Team | Onsite Team |
|-------|---------------------|-------------|
| Pre-deployment planning | 2-4 hours | - |
| Physical installation | - | 2-3 hours |
| Network configuration | 1 hour (remote) | 1 hour (onsite) |
| LoRaWAN configuration | 1-2 hours | - |
| Testing & validation | 1 hour | 1 hour |
| **Total per gateway** | **5-8 hours** | **4-5 hours** |

### 3.3 Network Requirements Checklist

Before deploying the gateway, ensure:

- [ ] **IP Address allocated** (static or DHCP reservation)
- [ ] **Firewall rules configured** (see Section 4.4)
- [ ] **Internet connectivity** available at installation site
- [ ] **PoE switch available** (802.3af) OR DC 12V power supply
- [ ] **Mounting location** identified (roof, wall, pole)
- [ ] **GPS coordinates** of installation location recorded
- [ ] **Network server credentials** prepared (TTN, ChirpStack, or AWS)

---

## 4. Prerequisites

### 4.1 Hardware Requirements

**Essential:**
- Milesight UG65 Gateway (EU868 variant for European deployments)
- LoRaWAN antenna (868 MHz, included with gateway)
- Ethernet cable (Cat5e or better)
- Power supply:
  - **Option A:** PoE-capable switch (802.3af standard)
  - **Option B:** DC 12V/1A power adapter

**Optional:**
- 4G LTE module and SIM card (for sites without wired network)
- Antenna extension cable (LMR-400, N-type connectors)
- Lightning arrestor (for outdoor installations)
- Weatherproof enclosure mounting bracket
- GPS antenna (for precise location tracking)

### 4.2 Site Requirements

**Coverage Planning:**
- Typical UG65 range: 2-5 km (urban), 10-15 km (rural)
- Line-of-sight preferred
- Elevation above ground level: minimum 5m recommended
- Avoid proximity to metal structures, large motors, or RF interference sources

**Physical Installation:**
- Mounting surface capable of supporting 2kg
- Access to power outlet or PoE switch port
- Protection from direct weather exposure (or use outdoor enclosure)
- Cable entry point sealed against moisture

**Environmental:**
- Operating temperature: -40°C to +70°C
- Humidity: 0-95% non-condensing
- IP67 rating (with proper cable gland installation)

### 4.3 Network Requirements

**Connectivity:**
- Ethernet port with internet access
- **OR** Wi-Fi network (2.4 GHz) with internet access
- **OR** 4G LTE coverage (if using cellular backhaul)

**Bandwidth:**
- Minimum: 256 kbps upstream
- Recommended: 1 Mbps or higher
- Data usage: ~100 MB/month (typical for 100 devices)

### 4.4 Firewall Rules

Configure firewall to allow **outbound** traffic:

| Protocol | Port | Destination | Purpose |
|----------|------|-------------|---------|
| **UDP** | 1700 | Network Server IP | Semtech Packet Forwarder |
| **TCP** | 1883 | Network Server IP | MQTT (unencrypted) |
| **TCP** | 8883 | Network Server IP | MQTT over TLS |
| **TCP** | 443 | `*.amazonaws.com` | AWS IoT Core HTTPS/WSS |
| **UDP** | 123 | NTP servers | Time synchronization |
| **TCP** | 80, 443 | `*.milesight-iot.com` | Firmware updates |

**For The Things Network (TTN):**
```
Destination: eu1.cloud.thethings.network
Ports: UDP 1700, TCP 8883
```

**For AWS IoT Core Direct:**
```
Destination: <your-iot-endpoint>-ats.iot.eu-west-2.amazonaws.com
Ports: TCP 8883
```

### 4.5 Account Requirements

- **Network Server Access:**
  - The Things Network (TTN) account, OR
  - ChirpStack server instance, OR
  - AWS IoT Core for LoRaWAN
- **AWS Account** with IoT Core access (eu-west-2 region)
- **SMDH Tenant ID** assigned

### 4.6 Tools and Equipment

**Onsite Installation:**
- Laptop with Ethernet port and web browser
- Ethernet cable (for initial configuration)
- Screwdriver set
- Cable ties and weatherproofing tape
- Multimeter (for power verification)
- Smartphone with LoRaWAN test app (e.g., "LoRaWAN Field Tester")
- Compass or GPS (for antenna orientation)

**Software:**
- Web browser (Chrome, Firefox, Edge)
- SSH client (optional, for advanced troubleshooting)
- Network scanner tool (e.g., Angry IP Scanner)

---

## 5. Gateway Physical Installation

### 5.1 Site Survey

Before installation, conduct a site survey:

#### 5.1.1 Coverage Assessment

1. **Identify installation location:**
   - Highest accessible point (roof, mast, building corner)
   - Central to planned sensor deployment area
   - Minimize obstructions (walls, metal structures)

2. **Check for RF interference sources:**
   - Avoid proximity to Wi-Fi access points (<3m separation)
   - Keep away from high-power electrical equipment
   - Note other RF transmitters in the area

3. **Document the site:**
   ```
   Site Survey Checklist:
   - [ ] GPS coordinates: _______________
   - [ ] Installation height: _______ meters
   - [ ] Compass bearing of antenna: _______ degrees
   - [ ] Photos: front view, installation point, surrounding area
   - [ ] Network connectivity verified (Ethernet/Wi-Fi/4G)
   - [ ] Power source identified
   ```

4. **Coverage modeling:**
   - Use online tools: [TTN Mapper](https://ttnmapper.org) or [Milesight Coverage Calculator](https://www.milesight-iot.com/lorawan/coverage-calculator/)
   - Input gateway coordinates and height
   - Identify potential dead zones

#### 5.1.2 Network Connectivity Test

```bash
# From onsite laptop connected to installation network
# Test internet connectivity
ping -c 5 8.8.8.8

# Test DNS resolution
nslookup eu1.cloud.thethings.network

# Test network server reachability
ping eu1.cloud.thethings.network

# Verify time sync (critical for LoRaWAN)
ntpdate -q pool.ntp.org
```

### 5.2 Physical Mounting

#### 5.2.1 Unboxing and Inspection

1. Open the UG65 package and verify contents:
   - [ ] UG65 gateway unit
   - [ ] LoRaWAN antenna (868 MHz)
   - [ ] Mounting bracket
   - [ ] Power adapter (if non-PoE version)
   - [ ] Quick start guide
   - [ ] Warranty card

2. Inspect for shipping damage
3. Note the **Gateway EUI** (printed on label and in web UI)

#### 5.2.2 Antenna Installation

1. **Attach the LoRaWAN antenna:**
   - Remove protective cap from N-type connector
   - Hand-tighten antenna to gateway connector
   - Use wrench for final 1/4 turn (do not overtighten)

2. **Antenna orientation:**
   - **Omnidirectional antenna:** Mount vertically (perpendicular to ground)
   - **Directional antenna:** Point towards sensor deployment area

3. **Lightning protection (outdoor installations):**
   - Install lightning arrestor between antenna and gateway
   - Ground the arrestor to building ground system

#### 5.2.3 Gateway Mounting

**Wall Mount:**
```
1. Mark mounting holes using bracket template
2. Drill holes (6mm diameter for M6 anchors)
3. Insert wall anchors
4. Secure mounting bracket with screws
5. Attach gateway to bracket
6. Ensure gateway is level
```

**Pole Mount:**
```
1. Position stainless steel clamps around pole
2. Attach mounting bracket to clamps
3. Tighten U-bolts securely
4. Mount gateway to bracket
5. Verify stability (gateway should not rotate)
```

**Indoor Installation:**
```
1. Mount on wall near window (for better LoRa propagation)
2. Ensure antenna has clear path (not blocked by metal/concrete)
3. Position away from heat sources
```

### 5.3 Power and Network Connection

#### 5.3.1 Power Options

**Option A: Power over Ethernet (Recommended)**
```
1. Connect Ethernet cable from PoE switch to gateway LAN port
2. Gateway will power on automatically
3. Verify LED indicators:
   - PWR (solid green): Power OK
   - LAN (blinking green): Network activity
```

**Option B: DC Power**
```
1. Connect DC 12V power adapter to gateway
2. Plug adapter into mains power
3. Connect Ethernet cable from standard switch to gateway LAN port
4. Verify same LED indicators
```

#### 5.3.2 LED Indicator Reference

| LED | State | Meaning |
|-----|-------|---------|
| **PWR** | Solid Green | Power on, normal operation |
| **LAN** | Blinking Green | Network data activity |
| **LAN** | Solid Green | Network connected, no activity |
| **LAN** | Off | No network connection |
| **WLAN** | Blinking Blue | Wi-Fi active |
| **LTE** | Blinking Green | 4G connected (if module installed) |
| **LoRa** | Blinking Green | LoRaWAN packets being forwarded |

#### 5.3.3 Cable Management

1. **Seal cable entries:**
   - Use cable glands for outdoor installations
   - Apply silicone sealant around entry points
   - Create drip loop to prevent water ingress

2. **Secure cables:**
   - Use cable ties to prevent strain on connectors
   - Leave slight slack for thermal expansion
   - Route cables away from sharp edges

---

## 6. Initial Gateway Configuration

### 6.1 Access Gateway Web Interface

#### 6.1.1 Find Gateway IP Address

**Method 1: DHCP Assignment (Default)**

The gateway requests an IP via DHCP by default.

```bash
# From laptop on same network, scan for gateway
# Using arp-scan (Linux/Mac)
sudo arp-scan --localnet | grep -i milesight

# Using Angry IP Scanner (Windows/Mac/Linux)
# Scan local subnet (e.g., 192.168.1.0/24)
# Look for device with hostname "UG65-XXXXXX"
```

**Method 2: Direct Connection**

If DHCP unavailable, connect laptop directly to gateway:

```
1. Connect Ethernet cable between laptop and gateway
2. Configure laptop static IP:
   - IP: 192.168.23.100
   - Subnet: 255.255.255.0
3. Gateway default IP: 192.168.23.150
```

#### 6.1.2 Login to Web Interface

1. Open web browser: `http://<gateway-ip>`
2. Default credentials:
   - **Username:** `admin`
   - **Password:** `password`
3. **IMPORTANT:** Change password immediately upon first login

### 6.2 Basic Configuration

#### 6.2.1 System Settings

Navigate to: **System → General Settings**

| Setting | Value | Notes |
|---------|-------|-------|
| **Device Name** | `smdh-gw-${TENANT_ID}-${SITE_ID}` | E.g., `smdh-gw-company_a-site_001` |
| **Description** | Installation location | E.g., "Factory A - North Building Roof" |
| **Time Zone** | `Europe/London` | Match site location |
| **NTP Server** | `pool.ntp.org` | Critical for LoRaWAN timing |
| **NTP Enable** | ✓ Enabled | Essential |

Click **Save & Apply**

#### 6.2.2 Network Configuration

Navigate to: **Network → WAN**

**For Static IP Assignment:**

| Setting | Example Value | Notes |
|---------|---------------|-------|
| **Protocol** | Static IP | Select from dropdown |
| **IP Address** | `10.50.100.10` | From Infrastructure Team |
| **Subnet Mask** | `255.255.255.0` | /24 network |
| **Gateway** | `10.50.100.1` | Default route |
| **DNS Server 1** | `8.8.8.8` | Google DNS |
| **DNS Server 2** | `8.8.4.4` | Backup DNS |

**For DHCP Assignment:**

| Setting | Value |
|---------|-------|
| **Protocol** | DHCP Client |
| **Hostname** | `smdh-gw-${TENANT_ID}-${SITE_ID}` |

Click **Save & Apply**

**Verify connectivity:**
```
Navigate to: Network → Diagnostics
- Ping Test: 8.8.8.8 (should succeed)
- DNS Test: google.com (should resolve)
```

#### 6.2.3 Wi-Fi Configuration (Alternative Backhaul)

If using Wi-Fi instead of Ethernet:

Navigate to: **Network → Wi-Fi**

| Setting | Value |
|---------|-------|
| **Mode** | Station (Client) |
| **SSID** | Site Wi-Fi network name |
| **Security** | WPA2-PSK |
| **Password** | Wi-Fi password |
| **IP Mode** | DHCP or Static |

Click **Save & Apply**

#### 6.2.4 Security Hardening

Navigate to: **System → Administration**

1. **Change default password:**
   - New password: Use strong password (12+ characters)
   - Confirm password

2. **Enable HTTPS:**
   - ✓ Enable HTTPS
   - Upload custom certificate (optional) or use self-signed

3. **Disable unused services:**
   - SSH: Enable only if needed for troubleshooting
   - HTTP: Disable after confirming HTTPS works

4. **Firewall:**
   Navigate to: **Network → Firewall**
   - Enable firewall
   - Allow only necessary inbound traffic (typically none)
   - Allow all outbound traffic

Click **Save & Apply**

### 6.3 LoRaWAN Configuration

#### 6.3.1 Radio Settings

Navigate to: **LoRaWAN → Radio**

| Setting | Value (EU868) | Notes |
|---------|---------------|-------|
| **Region** | EU868 | Europe 868 MHz |
| **Sub-Band** | N/A | (Used for US915) |
| **Channels** | Enable all 8 channels | Default for EU868 |

**EU868 Channel Plan:**

| Channel | Frequency (MHz) | Bandwidth | Data Rate |
|---------|----------------|-----------|-----------|
| 0 | 868.1 | 125 kHz | DR0-DR5 |
| 1 | 868.3 | 125 kHz | DR0-DR5 |
| 2 | 868.5 | 125 kHz | DR0-DR5 |
| 3 | 867.1 | 125 kHz | DR0-DR5 |
| 4 | 867.3 | 125 kHz | DR0-DR5 |
| 5 | 867.5 | 125 kHz | DR0-DR5 |
| 6 | 867.7 | 125 kHz | DR0-DR5 |
| 7 | 867.9 | 125 kHz | DR0-DR5 |

Click **Save & Apply**

#### 6.3.2 Gateway Location (GPS)

Navigate to: **LoRaWAN → General**

| Setting | Value | How to Obtain |
|---------|-------|---------------|
| **Latitude** | e.g., `51.5074` | Use Google Maps or GPS device |
| **Longitude** | e.g., `-0.1278` | Right-click on map → "What's here?" |
| **Altitude** | e.g., `25` meters | Building height + installation height |

**Why GPS coordinates matter:**
- Required for TTN gateway registration
- Used for geolocation in network server
- Helps with coverage planning and troubleshooting

---

## 7. Network Server Integration

The gateway must be connected to a LoRaWAN Network Server to manage device joins and data routing.

### 7.1 The Things Network (TTN) Integration

#### 7.1.1 Register Gateway in TTN Console

1. **Login to TTN Console:**
   - URL: https://console.cloud.thethings.network
   - Select region: **Europe 1 (eu1.cloud.thethings.network)**

2. **Add Gateway:**
   - Navigate to **Gateways** → **Add Gateway**
   - **Gateway EUI:** Enter gateway's EUI (from gateway label or web UI)
   - **Gateway ID:** `smdh-gw-${TENANT_ID}-${SITE_ID}` (lowercase, no spaces)
   - **Gateway name:** `SMDH Gateway - ${SITE_ID}`
   - **Frequency plan:** Europe 863-870 MHz (SF9 for RX2 - recommended)
   - Click **Create Gateway**

3. **Note Gateway API Key:**
   - After creation, navigate to **API Keys**
   - Click **Add API Key**
   - Rights: `Link as Gateway to a Gateway Server for traffic exchange`
   - Click **Create API Key**
   - **IMPORTANT:** Copy the API key (shown only once)

#### 7.1.2 Configure Gateway for TTN

Navigate to gateway web UI: **LoRaWAN → Packet Forwarder**

| Setting | Value |
|---------|-------|
| **Mode** | Basics Station |
| **Server** | LNS Server |
| **URI** | `wss://eu1.cloud.thethings.network` |
| **Port** | `8887` |
| **Authentication Mode** | TLS Server Authentication and Client Token |
| **Trust (CA Certificate)** | Use Built-in Certificate |
| **Client Token** | Paste API key from TTN |

**Alternative: Semtech UDP Packet Forwarder**

| Setting | Value |
|---------|-------|
| **Mode** | Packet Forwarder |
| **Server Address** | `eu1.cloud.thethings.network` |
| **Server Port (Up)** | `1700` |
| **Server Port (Down)** | `1700` |
| **Gateway ID** | Auto-detected (Gateway EUI) |

Click **Save & Apply**

#### 7.1.3 Verify Connection

In TTN Console:
1. Navigate to your gateway
2. Check **Live Data** tab
3. You should see:
   - **Status:** Connected
   - **Last seen:** Current timestamp
   - **Uplink:** Packet count increasing (if devices are transmitting)

### 7.2 ChirpStack Integration

#### 7.2.1 Register Gateway in ChirpStack

1. **Login to ChirpStack Application Server:**
   - URL: `https://<your-chirpstack-server>`

2. **Add Gateway:**
   - Navigate to **Gateways** → **Create**
   - **Gateway name:** `smdh-gw-${TENANT_ID}-${SITE_ID}`
   - **Gateway description:** Installation location
   - **Gateway ID:** Gateway EUI (format: `24e124fffef12345`)
   - **Network-server:** Select appropriate server
   - **Service-profile:** Select profile
   - **Gateway location:**
     - Latitude: `51.5074`
     - Longitude: `-0.1278`
     - Altitude: `25`
   - Click **Create Gateway**

#### 7.2.2 Configure Gateway for ChirpStack

Navigate to gateway web UI: **LoRaWAN → Packet Forwarder**

| Setting | Value |
|---------|-------|
| **Mode** | Packet Forwarder |
| **Server Address** | `<your-chirpstack-server-ip>` |
| **Server Port (Up)** | `1700` |
| **Server Port (Down)** | `1700` |
| **Gateway ID** | Auto-detected |

Click **Save & Apply**

#### 7.2.3 Verify Connection

In ChirpStack console:
1. Navigate to **Gateways** → Your gateway
2. Check **Live LoRaWAN frames** tab
3. Status should show: **Last seen at: [current time]**

### 7.3 AWS IoT Core for LoRaWAN (Alternative)

AWS IoT Core provides native LoRaWAN network server capabilities.

#### 7.3.1 Create Gateway in AWS IoT Core

```bash
# Set variables
export GATEWAY_EUI="24e124fffef12345"  # From gateway label
export GATEWAY_NAME="smdh-gw-company_a-site_001"
export AWS_REGION="eu-west-2"

# Create gateway
aws iotwireless create-wireless-gateway \
  --name ${GATEWAY_NAME} \
  --description "SMDH Gateway - Site 001" \
  --lorawan '{
    "GatewayEui": "'${GATEWAY_EUI}'",
    "RfRegion": "EU868"
  }' \
  --region ${AWS_REGION}
```

#### 7.3.2 Configure Gateway for AWS IoT Core

Navigate to gateway web UI: **LoRaWAN → Packet Forwarder**

| Setting | Value |
|---------|-------|
| **Mode** | Basics Station |
| **Server** | LNS Server |
| **URI** | `wss://<account-specific>.lorawan.eu-west-2.amazonaws.com` |
| **Port** | `8887` |
| **Authentication Mode** | TLS Server and Client Authentication |
| **Trust (CA Certificate)** | Upload AWS IoT Root CA |
| **Client Certificate** | Upload device certificate |
| **Client Key** | Upload private key |

---

## 8. AWS IoT Core Integration

For SMDH platform integration, gateway data must flow to AWS IoT Core.

### 8.1 Architecture Options

**Option A: TTN → AWS IoT Core** (Recommended)
```
Gateway → TTN → MQTT Integration → AWS IoT Core → Kinesis → Snowflake
```

**Option B: Gateway → AWS IoT Core (Direct)**
```
Gateway → AWS IoT Core → Kinesis → Snowflake
```

### 8.2 Configure TTN to AWS IoT Core Integration

#### 8.2.1 Create IoT Thing for Gateway

```bash
export GATEWAY_ID="smdh-gw-company_a-site_001"
export AWS_REGION="eu-west-2"

# Create Thing
aws iot create-thing \
  --thing-name ${GATEWAY_ID} \
  --thing-type-name "LoRaWANGateway" \
  --attribute-payload '{
    "attributes": {
      "tenant_id": "company_a",
      "site_id": "site_001",
      "gateway_type": "Milesight_UG65"
    }
  }' \
  --region ${AWS_REGION}
```

#### 8.2.2 Configure TTN MQTT Integration

1. **In TTN Console:**
   - Navigate to your application
   - Go to **Integrations** → **MQTT**
   - Note connection details:
     ```
     Server: eu1.cloud.thethings.network
     Port: 8883 (TLS) or 1883 (non-TLS)
     Username: <application-id>@<tenant-id>
     Password: <API key with device read rights>
     Topic: v3/<application-id>/devices/+/up
     ```

2. **Create IoT Rule to Subscribe to TTN:**

```bash
# Create IAM role for IoT Rule (if not exists)
aws iam create-role \
  --role-name smdh-iot-ttn-bridge-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "iot.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

# Create IoT Rule
aws iot create-topic-rule \
  --rule-name smdh_ttn_to_kinesis \
  --topic-rule-payload '{
    "sql": "SELECT end_device_ids.device_id as device_id, uplink_message.decoded_payload as payload, uplink_message.rx_metadata[0].gateway_ids.gateway_id as gateway_id, received_at as timestamp FROM '\''v3/+/devices/+/up'\''",
    "description": "Route TTN uplink messages to Kinesis",
    "actions": [{
      "kinesis": {
        "roleArn": "arn:aws:iam::123456789:role/smdh-iot-ttn-bridge-role",
        "streamName": "smdh-sensor-data-stream",
        "partitionKey": "${device_id}"
      }
    }],
    "ruleDisabled": false
  }' \
  --region ${AWS_REGION}
```

### 8.3 Monitor Gateway Status in AWS

Create CloudWatch dashboard to monitor gateway health:

```bash
# Create CloudWatch metric filter for gateway connectivity
aws logs put-metric-filter \
  --log-group-name "/aws/iot/gateway-logs" \
  --filter-name "GatewayDisconnect" \
  --filter-pattern "[time, gateway_id, event=DISCONNECT]" \
  --metric-transformations \
    metricName=GatewayDisconnections,\
    metricNamespace=SMDH/LoRaWAN,\
    metricValue=1,\
    defaultValue=0
```

---

## 9. Testing and Validation

### 9.1 Gateway Connectivity Tests

#### 9.1.1 Verify Network Server Connection

**In Gateway Web UI:**
Navigate to: **LoRaWAN → Packet Forwarder → Status**

Check:
- [ ] Status: **Connected**
- [ ] Uplink packets: **> 0** (if devices transmitting)
- [ ] Downlink packets: **> 0** (if devices sending confirmed messages)
- [ ] Last activity: **Recent timestamp**

**In Network Server Console (TTN/ChirpStack):**
- [ ] Gateway shows as **Online**
- [ ] **Last seen:** Within last 30 seconds
- [ ] **Activity:** Receiving heartbeat packets

#### 9.1.2 Network Diagnostics

Navigate to: **Network → Diagnostics** in gateway web UI

**Ping Test:**
```
Target: eu1.cloud.thethings.network
Packets: 10
Result: 0% packet loss, <50ms latency (typical)
```

**DNS Test:**
```
Hostname: eu1.cloud.thethings.network
Result: Should resolve to IP address
```

**NTP Test:**
Navigate to: **System → Time**
- [ ] NTP Status: **Synchronized**
- [ ] System time: **Correct** (within 1 second of actual time)

### 9.2 LoRaWAN Coverage Test

#### 9.2.1 Test with LoRaWAN Device

1. **Register a test device in network server** (see DevTank deployment guide)

2. **Place device at various test locations:**
   - Near gateway (< 50m)
   - Medium range (200-500m)
   - Edge of expected coverage (1-2 km)

3. **Trigger uplink transmission** (via device button or measurement)

4. **Check reception in network server:**
   - Navigate to device → Live Data
   - Verify uplink appears
   - Check RSSI and SNR values:
     ```
     Excellent: RSSI > -90 dBm, SNR > 5 dB
     Good:      RSSI -90 to -110 dBm, SNR 0 to 5 dB
     Fair:      RSSI -110 to -120 dBm, SNR -5 to 0 dB
     Poor:      RSSI < -120 dBm, SNR < -5 dB
     ```

#### 9.2.2 Document Coverage Map

Create coverage documentation:

```
Coverage Test Report - Gateway: smdh-gw-company_a-site_001
Date: 2025-11-20
Tester: [Name]

Test Location 1: Factory Floor - North End
  Coordinates: 51.5074, -0.1278
  Distance from gateway: 150m
  RSSI: -95 dBm
  SNR: 8 dB
  Status: ✓ Good coverage

Test Location 2: Warehouse - Loading Dock
  Coordinates: 51.5080, -0.1285
  Distance from gateway: 280m
  RSSI: -105 dBm
  SNR: 3 dB
  Status: ✓ Acceptable coverage

Test Location 3: Outdoor Storage Area
  Coordinates: 51.5090, -0.1295
  Distance from gateway: 450m
  RSSI: -112 dBm
  SNR: -2 dB
  Status: ⚠ Marginal coverage (consider additional gateway)
```

Use online tools to visualize:
- Upload test results to [TTN Mapper](https://ttnmapper.org)
- Generate coverage map PDF for documentation

### 9.3 End-to-End Data Flow Test

#### 9.3.1 Test Message from Device to Snowflake

1. **Trigger device transmission:**
   - Activate DevTank sensor measurement
   - Note timestamp

2. **Verify in Network Server:**
   ```
   TTN Console → Applications → Devices → [device] → Live Data
   Expected: Uplink message with decoded payload
   Latency: < 5 seconds from transmission
   ```

3. **Verify in AWS IoT Core:**
   ```bash
   # Subscribe to topic
   aws iot-data subscribe \
     --topic "v3/+/devices/+/up" \
     --region eu-west-2

   Expected: JSON message with device data
   Latency: < 10 seconds from transmission
   ```

4. **Verify in Kinesis Stream:**
   ```bash
   aws kinesis get-records \
     --shard-iterator $(aws kinesis get-shard-iterator \
       --stream-name smdh-sensor-data-stream \
       --shard-id shardId-000000000000 \
       --shard-iterator-type LATEST \
       --query 'ShardIterator' \
       --output text) \
     --region eu-west-2
   ```

5. **Verify in Snowflake:**
   ```sql
   SELECT
       device_id,
       timestamp,
       payload,
       gateway_id
   FROM smdh_tenant_company_a.raw.sensor_readings
   WHERE gateway_id = 'smdh-gw-company_a-site_001'
   ORDER BY timestamp DESC
   LIMIT 5;
   ```

Expected total latency: **< 30 seconds** from device transmission to Snowflake

### 9.4 Gateway Performance Monitoring

Navigate to: **System → Status** in gateway web UI

**Key Metrics to Monitor:**

| Metric | Normal Range | Action if Abnormal |
|--------|--------------|-------------------|
| **CPU Usage** | < 50% | Reboot if > 80% sustained |
| **Memory Usage** | < 70% | Reboot if > 90% |
| **Temperature** | < 60°C | Check ventilation if > 70°C |
| **Uptime** | Continuous | Investigate if frequent reboots |
| **Network Traffic** | Steady | Investigate spikes or drops |

**LoRaWAN Statistics:**

Navigate to: **LoRaWAN → Statistics**

| Metric | Expected Value |
|--------|----------------|
| **Total Uplinks** | Increasing steadily |
| **Total Downlinks** | Small percentage of uplinks |
| **RX Success Rate** | > 95% |
| **TX Success Rate** | > 98% |

---

## 10. Troubleshooting

### 10.1 Gateway Won't Power On

| Symptom | Possible Cause | Solution |
|---------|---------------|----------|
| No LEDs illuminate | No power | Verify PoE switch supports 802.3af; check DC adapter |
| PWR LED off | Faulty power supply | Test with known-good adapter; verify voltage (12V DC) |
| LEDs flash then turn off | Insufficient PoE power | Use PoE injector or DC power instead |
| Device hot to touch | Overheating | Ensure adequate ventilation; check ambient temperature |

**Verification Steps:**
```
1. Test PoE port with multimeter: should provide 48V DC
2. Test DC adapter output: should provide 12V DC @ 1A
3. Try alternative power source
4. Contact Milesight support if hardware failure suspected
```

### 10.2 Network Connectivity Issues

| Symptom | Possible Cause | Solution |
|---------|---------------|----------|
| LAN LED off | No Ethernet connection | Check cable, verify switch port is active |
| Can't access web UI | Wrong IP address | Scan network or connect directly (192.168.23.150) |
| Ping fails | Network misconfiguration | Verify IP settings match network requirements |
| DNS resolution fails | Wrong DNS servers | Configure DNS: 8.8.8.8, 8.8.4.4 |
| Can't reach internet | Firewall blocking | Check firewall rules (Section 4.4) |

**Debugging Commands:**

From gateway web UI → **Network → Diagnostics:**

```
Test 1: Ping default gateway
Target: <gateway-ip>
Expected: 0% packet loss

Test 2: Ping external IP
Target: 8.8.8.8
Expected: 0% packet loss

Test 3: DNS resolution
Target: google.com
Expected: Resolves to IP address

Test 4: Ping network server
Target: eu1.cloud.thethings.network
Expected: 0% packet loss, <100ms latency
```

### 10.3 Network Server Connection Issues

| Symptom | Possible Cause | Solution |
|---------|---------------|----------|
| Status: Disconnected | Wrong server address | Verify network server URL/IP |
| Authentication failed | Invalid API key/token | Regenerate API key in network server |
| Connection timeout | Firewall blocking | Check UDP 1700 or TCP 8883 allowed |
| Certificate error | Wrong CA certificate | Use built-in cert or download from network server |
| Intermittent disconnects | Network instability | Check for packet loss, DNS issues |

**TTN Specific Troubleshooting:**

```
Expected URI: wss://eu1.cloud.thethings.network
Expected Port: 8887 (Basics Station)
Authentication: Client Token (API key)

Common Errors:
- "connection refused" → Wrong URI or port
- "unauthorized" → Invalid API key
- "certificate verify failed" → Wrong CA cert
```

**ChirpStack Specific Troubleshooting:**

```
Expected Server: <chirpstack-server-ip>
Expected Port: 1700 (Semtech UDP)

Common Errors:
- "no route to host" → Server unreachable (check firewall)
- No error but gateway offline in ChirpStack → Wrong Gateway EUI
```

### 10.4 No LoRaWAN Packets Received

| Symptom | Possible Cause | Solution |
|---------|---------------|----------|
| LoRa LED never blinks | Wrong frequency plan | Verify EU868 selected, match device region |
| No uplinks in network server | Antenna not connected | Check antenna connection, verify tightness |
| RSSI very weak (< -130 dBm) | Antenna issue | Replace antenna, check for damage |
| Packets received but not decoded | Missing payload decoder | Configure JavaScript decoder in network server |
| Some devices work, others don't | Device not registered | Verify device DevEUI registered in network server |

**Coverage Debugging:**

```
1. Verify gateway location coordinates are correct
2. Check antenna is vertical (omnidirectional) or aimed correctly (directional)
3. Use spectrum analyzer app to verify 868 MHz activity
4. Test with device very close to gateway (<10m) to eliminate coverage issues
5. Check for RF interference (Wi-Fi, other LoRa gateways on same channel)
```

### 10.5 Time Synchronization Issues

LoRaWAN Class B/C require accurate time synchronization.

| Symptom | Possible Cause | Solution |
|---------|---------------|----------|
| NTP sync failed | NTP server unreachable | Verify firewall allows UDP 123 |
| System time wrong | Wrong timezone | Set timezone in System → General |
| "GPS time not available" | No GPS antenna connected | Connect GPS antenna or use NTP only |
| Time drifts over days | Hardware RTC issue | Enable NTP auto-sync every hour |

**Verify Time Sync:**

Navigate to: **System → Time**
```
System Time: 2025-11-20 14:35:22
NTP Status: Synchronized
NTP Server: pool.ntp.org
Last Sync: 2 minutes ago
```

### 10.6 Firmware Update Issues

| Symptom | Possible Cause | Solution |
|---------|---------------|----------|
| Update fails | Insufficient storage | Clear logs: System → Log → Clear |
| Update hangs at 50% | Network interruption | Ensure stable connection, try again |
| Gateway won't boot after update | Corrupted firmware | Enter recovery mode, reflash firmware |
| "File too large" error | Wrong firmware file | Download correct UG65 firmware from Milesight |

**Safe Firmware Update Procedure:**

```
1. Backup current configuration:
   System → Backup & Restore → Download Configuration

2. Download latest firmware:
   URL: https://www.milesight-iot.com/support/firmware/
   Model: UG65 (verify exact model variant)

3. Upload and install:
   System → Firmware Upgrade → Choose File → Upload
   Wait 5-10 minutes for update to complete
   Gateway will reboot automatically

4. Verify after reboot:
   - Check firmware version: System → General
   - Verify network connectivity
   - Confirm LoRaWAN connection to network server
   - Restore configuration if needed
```

### 10.7 Performance Degradation

| Symptom | Possible Cause | Solution |
|---------|---------------|----------|
| High CPU usage | Too many devices | Consider deploying additional gateway |
| High packet loss | RF interference | Change channels or relocate gateway |
| Slow web UI | High load | Disable unnecessary services |
| Frequent reboots | Overheating | Improve ventilation, check temperature |
| Memory leak | Firmware bug | Update to latest firmware |

**Performance Optimization:**

```
1. Limit concurrent devices: Max 500-1000 per gateway for optimal performance
2. Disable unused features:
   - Disable Wi-Fi if using Ethernet
   - Disable built-in network server if using external (TTN/ChirpStack)
3. Adjust log levels:
   System → Log → Set to "Error" only in production
4. Regular maintenance:
   - Reboot monthly during maintenance window
   - Clear logs weekly
   - Update firmware quarterly
```

### 10.8 Common Error Messages

**"Failed to connect to network server"**
- Verify server address and port
- Check firewall rules allow outbound connection
- Regenerate API key if using authentication

**"Invalid Gateway EUI"**
- Gateway EUI must match between device and network server registration
- Gateway EUI is fixed (printed on label), cannot be changed
- Verify no typos in network server registration

**"Certificate verification failed"**
- For Basics Station: Verify CA certificate is correct
- Try using built-in certificates instead of custom
- Check system time is synchronized (required for TLS)

**"Uplink frequency not allowed"**
- Device transmitting on frequency not in gateway's channel plan
- Verify both device and gateway configured for same region (EU868)
- Check if all 8 channels enabled in gateway

---

## Appendix A: Gateway Deployment Checklist

Use this checklist for each gateway deployment:

### Pre-Deployment Planning
- [ ] Site survey completed
- [ ] GPS coordinates recorded: ______________
- [ ] Installation height determined: _______ meters
- [ ] Network connectivity confirmed (Ethernet/Wi-Fi/4G)
- [ ] IP address allocated (if static): ______________
- [ ] Firewall rules configured
- [ ] Network server account created (TTN/ChirpStack/AWS)
- [ ] Gateway EUI recorded: ______________

### Physical Installation
- [ ] Gateway mounted securely
- [ ] Antenna attached and oriented correctly
- [ ] Power connected (PoE or DC)
- [ ] Ethernet cable connected and tested
- [ ] Cable entries sealed (outdoor installation)
- [ ] Lightning protection installed (outdoor installation)
- [ ] LED indicators showing normal operation
- [ ] Installation photos taken

### Network Configuration
- [ ] Web UI accessible at: http://______________
- [ ] Default password changed
- [ ] Device name set: smdh-gw-${TENANT_ID}-${SITE_ID}
- [ ] Static IP configured (if required)
- [ ] DNS servers configured
- [ ] NTP synchronization enabled and working
- [ ] Internet connectivity verified
- [ ] HTTPS enabled

### LoRaWAN Configuration
- [ ] Frequency plan set to EU868 (or appropriate region)
- [ ] All 8 channels enabled
- [ ] GPS coordinates entered
- [ ] Altitude configured
- [ ] Packet forwarder mode selected (Basics Station/Semtech UDP)
- [ ] Network server address configured
- [ ] Authentication configured (API key/certificates)

### Network Server Registration
- [ ] Gateway registered in network server
- [ ] Gateway ID matches Gateway EUI
- [ ] Location coordinates entered
- [ ] Gateway shows as "Online" in console
- [ ] API keys generated and stored securely

### Testing & Validation
- [ ] Gateway status: Connected
- [ ] Network server shows gateway online
- [ ] Test device uplink received
- [ ] RSSI and SNR values acceptable
- [ ] Coverage test completed at key locations
- [ ] Data flows to AWS IoT Core
- [ ] Data appears in Kinesis stream
- [ ] Data visible in Snowflake

### Documentation
- [ ] Configuration backup downloaded
- [ ] Credentials stored securely
- [ ] Coverage map created
- [ ] Installation report completed
- [ ] Handover documentation provided

---

## Appendix B: Reference Information

### Gateway Specifications

**Model:** Milesight UG65

**Radio:**
- LoRaWAN Frequency: EU868 / US915 / AS923 / AU915 / IN865 / RU864 / KR920
- TX Power: 27 dBm max
- RX Sensitivity: -139 dBm @ SF12 / 125 kHz
- Channels: 8 (or 16 with dual-channel variant)

**Network:**
- Ethernet: 10/100 Mbps, RJ45
- Wi-Fi: 802.11 b/g/n, 2.4 GHz
- 4G LTE: Optional module (Cat 4, multiple bands)
- VPN: IPsec, OpenVPN, GRE, L2TP, PPTP

**Power:**
- PoE: 802.3af (IEEE standard)
- DC: 12V/1A
- Consumption: 8W typical, 12W max

**Physical:**
- Dimensions: 142 × 105 × 40 mm
- Weight: 380g
- Mounting: Wall or pole mount
- Ingress Protection: IP67

**Operating Conditions:**
- Temperature: -40°C to +70°C
- Humidity: 0-95% RH non-condensing

### Default Network Settings

| Parameter | Default Value |
|-----------|---------------|
| IP Mode | DHCP Client |
| Static IP (if DHCP fails) | 192.168.23.150 |
| Subnet Mask | 255.255.255.0 |
| HTTP Port | 80 |
| HTTPS Port | 443 |
| SSH Port | 22 (disabled by default) |
| Username | admin |
| Password | password |

### Network Server Endpoints

**The Things Network:**
```
Region: Europe
Server: eu1.cloud.thethings.network
Basics Station URI: wss://eu1.cloud.thethings.network
Basics Station Port: 8887
Semtech UDP Port: 1700
```

**ChirpStack (self-hosted):**
```
Server: <your-server-ip>
Semtech UDP Port: 1700
MQTT Port: 1883 (or 8883 for TLS)
```

**AWS IoT Core for LoRaWAN:**
```
Region: eu-west-2 (London)
URI: wss://<account-id>.lorawan.eu-west-2.amazonaws.com
Port: 8887
```

### Firewall Requirements Summary

**Outbound (from gateway to internet):**
```
UDP 1700 → Network server (Semtech Packet Forwarder)
TCP 8883 → Network server (MQTT/TLS)
TCP 443  → *.amazonaws.com (AWS IoT Core)
UDP 123  → NTP servers (time sync)
TCP 80/443 → *.milesight-iot.com (firmware updates)
```

**Inbound (from internet to gateway):**
```
TCP 80/443 → Gateway (optional, for remote web UI access)
TCP 22 → Gateway (optional, for remote SSH access)
```

### Useful Commands and URLs

**Web UI Access:**
```
Default: http://192.168.23.150
Production: http://<gateway-ip> or https://<gateway-ip>
```

**SSH Access (if enabled):**
```bash
ssh admin@<gateway-ip>
# Default password: password
```

**Verify NTP Sync:**
```bash
# Via web UI: System → Time
# Via SSH:
ntpq -p
```

**View System Logs:**
```
Web UI: System → Log
Filter: LoRaWAN, Network, System
```

**Backup Configuration:**
```
Web UI: System → Backup & Restore → Download Configuration
Save as: ug65_${GATEWAY_ID}_config_${DATE}.bin
```

### Support Resources

- **Milesight Support:** https://www.milesight-iot.com/support/
- **Milesight Documentation:** https://www.milesight-iot.com/documents/
- **TTN Documentation:** https://www.thethingsindustries.com/docs/gateways/milesight-ug65/
- **LoRaWAN Specification:** https://lora-alliance.org/resource_hub/lorawan-specification-v1-0-3/
- **AWS IoT Core for LoRaWAN:** https://docs.aws.amazon.com/iot/latest/developerguide/connect-iot-lorawan.html

### Maintenance Schedule

| Task | Frequency | Responsible Team |
|------|-----------|------------------|
| Verify gateway online status | Daily | Infrastructure Team (automated) |
| Check packet statistics | Weekly | Infrastructure Team |
| Review system logs | Weekly | Infrastructure Team |
| Clear old logs | Monthly | Infrastructure Team |
| Reboot gateway | Monthly | Infrastructure Team |
| Firmware update check | Quarterly | Infrastructure Team |
| Site visit and physical inspection | Annually | Onsite Team |
| Backup configuration | After any change | Infrastructure Team |

---

## Appendix C: Network Server Comparison

| Feature | The Things Network (TTN) | ChirpStack | AWS IoT Core for LoRaWAN |
|---------|--------------------------|------------|--------------------------|
| **Hosting** | Cloud (free community) | Self-hosted or cloud | AWS Managed |
| **Cost** | Free (fair use policy) | Free (self-hosted) | Pay per device/message |
| **Device Limit** | Unlimited (fair use) | Unlimited | Unlimited |
| **Payload Decoders** | JavaScript | JavaScript | AWS Lambda |
| **Integrations** | MQTT, HTTP, Storage | MQTT, HTTP, gRPC | Native AWS services |
| **Geolocation** | Built-in (TDoA) | Plugin available | AWS Location Service |
| **Multitenancy** | Limited | Full support | Account-based |
| **SLA** | None (community) | Self-managed | AWS SLA |
| **Setup Complexity** | Low | Medium | Medium |
| **Best For** | Proof of concept, small deployments | Medium deployments, full control | Enterprise, AWS-native |

**SMDH Recommendation:**
- **Development/Testing:** The Things Network
- **Production (< 1000 devices):** The Things Network or ChirpStack
- **Production (> 1000 devices):** AWS IoT Core for LoRaWAN or ChirpStack cluster

---

*Document Version: 1.0*
*Last Updated: 20 November 2025*
