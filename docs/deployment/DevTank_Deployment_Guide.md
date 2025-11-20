# DevTank OpenSmartMonitor Deployment Guide
## SMDH Platform Integration

**Document Classification:** Internal Use Only
**Date:** 19 November 2025
**Author:** Architecture Team
**Status:** Deployment Guide

---

## Table of Contents

1. [Overview](#1-overview)
2. [Roles and Responsibilities](#2-roles-and-responsibilities)
3. [Deployment Summary](#3-deployment-summary)
4. [Prerequisites](#4-prerequisites)
5. [DevTank Device Configuration](#5-devtank-device-configuration)
6. [AWS IoT Core Setup](#6-aws-iot-core-setup)
7. [LoRaWAN Network Server Configuration](#7-lorawan-network-server-configuration)
8. [Payload Decoder Configuration](#8-payload-decoder-configuration)
9. [Testing and Validation](#9-testing-and-validation)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. Overview

This guide describes how to deploy DevTank OpenSmartMonitor (OSM) devices for integration with the SMDH (Smart Manufacturing Data Hub) platform. DevTank devices support two communication methods:

| Communication Type | Protocol | Data Path |
|-------------------|----------|-----------|
| **Wi-Fi Enabled** | MQTT over TLS | Device → Wi-Fi → MQTT Broker → AWS IoT Core |
| **LoRaWAN Enabled** | LoRaWAN | Device → LoRaWAN Gateway → Network Server → AWS IoT Core |

### 1.1 Architecture Overview

```
DevTank OSM Device (LoRaWAN)
        ↓ (LoRaWAN 868 MHz)
LoRaWAN Gateway (e.g., Milesight UG65)
        ↓ (MQTT)
AWS IoT Core (MQTT Broker)
        ↓ (IoT Rules Engine)
AWS Kinesis Data Streams
        ↓ (Snowflake Openflow)
Snowflake Raw Tables
```

### 1.2 Data Format

DevTank devices transmit binary-encoded sensor data that requires JavaScript decoding. The decoded output is JSON:

```json
{
  "BAT": 10000,
  "CC1": 291,
  "CC1_max": 298,
  "CC1_min": 285,
  "HUMI": 4259,
  "TEMP": 2276,
  "PM25": 12,
  "VOC": 150
}
```

---

## 2. Roles and Responsibilities

Successful deployment of DevTank devices requires coordination between two key roles:

### 2.1 Role Definitions

#### IT Operations Team

**Location:** Central/Remote

**Primary Responsibilities:**
- AWS IoT Core administration
- Certificate generation and management
- IoT Policy creation and maintenance
- Kinesis stream management
- LoRaWAN network server administration
- Snowflake database administration
- Security and compliance oversight

**Required Access:**
- AWS Console (IoT Core, Kinesis, IAM)
- LoRaWAN Network Server admin account
- Snowflake ACCOUNTADMIN or SECURITYADMIN role
- Certificate management systems

#### Onsite Configurer

**Location:** Customer/Manufacturing site

**Primary Responsibilities:**
- Physical device installation
- Device configuration via OSM Config GUI
- Wi-Fi network configuration
- Gateway placement and setup
- Initial device testing
- Site survey and coverage validation

**Required Access:**
- Physical access to devices and installation locations
- Laptop with Chrome browser and USB drivers
- Site Wi-Fi credentials (for Wi-Fi devices)
- Device credentials package from IT Operations

### 2.2 Role Interaction Workflow

```
┌─────────────────────────────────────────────────────────────────────┐
│                        DEPLOYMENT WORKFLOW                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  IT OPERATIONS                    ONSITE CONFIGURER                 │
│  ─────────────                    ─────────────────                 │
│                                                                     │
│  1. Receive deployment request                                      │
│         │                                                           │
│         ▼                                                           │
│  2. Create AWS IoT Thing                                            │
│         │                                                           │
│         ▼                                                           │
│  3. Generate certificates                                           │
│         │                                                           │
│         ▼                                                           │
│  4. Create/assign IoT Policy                                        │
│         │                                                           │
│         ▼                                                           │
│  5. Prepare Device Credentials ──────────────► 6. Receive package   │
│     Package                                         │               │
│         │                                           ▼               │
│         │                                    7. Install device      │
│         │                                           │               │
│         │                                           ▼               │
│         │                                    8. Configure device    │
│         │                                           │               │
│         │                                           ▼               │
│  9. Register in LoRaWAN ◄─────────────────── 9. Send DevEUI/AppKey  │
│     Network Server                           (LoRaWAN only)         │
│         │                                           │               │
│         ▼                                           ▼               │
│  10. Configure payload decoder               11. Test connectivity  │
│         │                                           │               │
│         ▼                                           ▼               │
│  12. Verify data in Snowflake ◄──────────── 13. Confirm readings    │
│         │                                                           │
│         ▼                                                           │
│  14. Handover to tenant                                             │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.3 Communication Touchpoints

| Touchpoint | From | To | Information Exchanged |
|------------|------|----|-----------------------|
| **Deployment Request** | Project Manager | IT Operations | Tenant ID, site details, device count |
| **Credentials Package** | IT Operations | Onsite Configurer | IoT endpoint, certificates, device IDs |
| **LoRaWAN Registration** | Onsite Configurer | IT Operations | DevEUI, AppKey (LoRaWAN devices) |
| **Validation Confirmation** | IT Operations | Onsite Configurer | Data flow confirmed in Snowflake |
| **Issue Escalation** | Onsite Configurer | IT Operations | Connection failures, error messages |

### 2.4 Device Credentials Package

IT Operations prepares this package for each device deployment:

**Package Contents:**

```
device_credentials_package/
├── README.txt                    # Quick start instructions
├── device_info.json              # Device metadata
│   {
│     "thing_name": "smdh-osm-company_a-site_001-osm_001",
│     "tenant_id": "company_a",
│     "site_id": "site_001",
│     "device_id": "osm_001",
│     "iot_endpoint": "a1b2c3d4e5f6g7-ats.iot.eu-west-2.amazonaws.com"
│   }
├── certificates/                 # For Wi-Fi devices only
│   ├── device-cert.pem
│   ├── device-private.key
│   └── AmazonRootCA1.pem
└── wifi_config.txt               # Wi-Fi specific settings
    MQTT Address: a1b2c3d4e5f6g7-ats.iot.eu-west-2.amazonaws.com
    MQTT Port: 8883
    MQTT Scheme: TCP (TLS)
```

---

## 3. Deployment Summary

### 3.1 Chronological Steps Overview

```
┌─────────────────────────────────────────────────┐
│  1. AWS: Create Thing + Certificates + Policy   │  ← IT Operations
└──────────────────────┬──────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────┐
│  2. SENSOR: Configure with AWS credentials      │  ← Onsite Configurer
│     - Wi-Fi: Enter IoT endpoint + port          │
│     - LoRaWAN: Note DevEUI + AppKey             │
└──────────────────────┬──────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────┐
│  3. NETWORK SERVER (LoRaWAN only):              │  ← IT Operations
│     Register device with DevEUI + AppKey        │
└──────────────────────┬──────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────┐
│  4. TEST: Verify data flows to Snowflake        │  ← Both roles
└─────────────────────────────────────────────────┘
```

### 3.2 Phase 1: AWS Preparation (IT Operations - One-time setup)

| Step | Action | AWS Service |
|------|--------|-------------|
| 1 | Create IoT Thing Type "DevTankOSM" | IoT Core |
| 2 | Create Kinesis Data Stream | Kinesis |
| 3 | Create IAM Role for IoT Rules → Kinesis | IAM |
| 4 | Create IoT Rule to route messages to Kinesis | IoT Core |
| 5 | Get IoT Endpoint URL | IoT Core |
| 6 | Create Snowflake raw tables and streams | Snowflake |

### 3.3 Phase 2: Per-Device Setup

#### IT Operations Tasks (Remote)

| Step | Action | Output |
|------|--------|--------|
| 1 | **Create IoT Thing** | Thing ARN |
| 2 | **Generate X.509 certificates** | cert.pem, private.key, Root CA |
| 3 | **Create/assign IoT Policy** | Policy ARN |
| 4 | **Attach certificate to Thing** | - |
| 5 | **Attach policy to certificate** | - |
| 6 | **Prepare credentials package** | ZIP file for Onsite Configurer |

#### Onsite Configurer Tasks (On-site)

| Step | Action | Notes |
|------|--------|-------|
| 1 | **Install device physically** | Mount sensor, connect power |
| 2 | **Connect device via USB-C** | Use laptop with Chrome |
| 3 | **Open OSM Config GUI** | https://osm-config.devtank.co.uk |
| 4 | **Configure communication** | Wi-Fi or LoRaWAN settings |
| 5 | **Set measurement intervals** | Per project requirements |
| 6 | **Save and backup configuration** | Download JSON backup |
| 7 | **Record DevEUI/AppKey** (LoRaWAN) | Send to IT Operations |
| 8 | **Verify device status** | Check "Connected" status |

#### IT Operations Tasks - LoRaWAN Registration (Remote)

| Step | Action | Notes |
|------|--------|-------|
| 1 | **Register device in network server** | Use DevEUI/AppKey from Onsite |
| 2 | **Configure payload decoder** | Add JavaScript decoder |
| 3 | **Enable AWS IoT integration** | Connect to IoT Core |

### 3.4 Phase 3: Validation (Both Roles)

| Step | Role | Action |
|------|------|--------|
| 1 | Onsite Configurer | Verify device shows "Connected" |
| 2 | IT Operations | Check messages in IoT Core MQTT test |
| 3 | IT Operations | Verify data in Kinesis stream |
| 4 | IT Operations | Query raw data in Snowflake |
| 5 | IT Operations | Confirm to Onsite Configurer |
| 6 | Onsite Configurer | Complete installation sign-off |

### 3.5 Time Estimates by Role

| Phase | IT Operations | Onsite Configurer |
|-------|---------------|-------------------|
| AWS setup (per device) | 10-15 minutes | - |
| Credentials package | 5 minutes | - |
| Physical installation | - | 15-30 minutes |
| Device configuration | - | 10-15 minutes |
| LoRaWAN registration | 10-15 minutes | - |
| Testing & validation | 10 minutes | 5 minutes |
| **Total per device** | **35-45 minutes** | **30-50 minutes** |

### 3.6 Detailed Step-by-Step: IT Operations

#### Step 1: Create IoT Thing

```bash
# Set variables for this deployment
export TENANT_ID="company_a"
export SITE_ID="site_001"
export DEVICE_ID="osm_001"
export AWS_REGION="eu-west-2"
export ACCOUNT_ID="123456789012"

# Create the Thing
aws iot create-thing \
  --thing-name "smdh-osm-${TENANT_ID}-${SITE_ID}-${DEVICE_ID}" \
  --thing-type-name "DevTankOSM" \
  --attribute-payload '{
    "attributes": {
      "tenant_id": "'${TENANT_ID}'",
      "site_id": "'${SITE_ID}'",
      "device_type": "OpenSmartMonitor"
    }
  }' \
  --region ${AWS_REGION}
```

#### Step 2: Generate Certificates

```bash
# Generate certificates and keys
aws iot create-keys-and-certificate \
  --set-as-active \
  --certificate-pem-outfile "${TENANT_ID}-${DEVICE_ID}-cert.pem" \
  --public-key-outfile "${TENANT_ID}-${DEVICE_ID}-public.key" \
  --private-key-outfile "${TENANT_ID}-${DEVICE_ID}-private.key" \
  --region ${AWS_REGION}

# Capture certificate ARN from output
export CERT_ARN="<certificate-arn-from-output>"

# Download Root CA
wget -O AmazonRootCA1.pem https://www.amazontrust.com/repository/AmazonRootCA1.pem
```

#### Step 3: Create or Reuse IoT Policy

```bash
# Check if tenant policy exists
aws iot get-policy \
  --policy-name "smdh-tenant-${TENANT_ID}-policy" \
  --region ${AWS_REGION} 2>/dev/null

# If not exists, create it (see Section 6.4 for full policy)
```

#### Step 4-5: Attach Certificate and Policy

```bash
# Attach certificate to thing
aws iot attach-thing-principal \
  --thing-name "smdh-osm-${TENANT_ID}-${SITE_ID}-${DEVICE_ID}" \
  --principal "${CERT_ARN}" \
  --region ${AWS_REGION}

# Attach policy to certificate
aws iot attach-policy \
  --policy-name "smdh-tenant-${TENANT_ID}-policy" \
  --target "${CERT_ARN}" \
  --region ${AWS_REGION}
```

#### Step 6: Prepare Credentials Package

```bash
# Get IoT endpoint
IOT_ENDPOINT=$(aws iot describe-endpoint \
  --endpoint-type iot:Data-ATS \
  --region ${AWS_REGION} \
  --query 'endpointAddress' \
  --output text)

# Create package directory
mkdir -p "device_package_${DEVICE_ID}"

# Create device info file
cat > "device_package_${DEVICE_ID}/device_info.json" << EOF
{
  "thing_name": "smdh-osm-${TENANT_ID}-${SITE_ID}-${DEVICE_ID}",
  "tenant_id": "${TENANT_ID}",
  "site_id": "${SITE_ID}",
  "device_id": "${DEVICE_ID}",
  "iot_endpoint": "${IOT_ENDPOINT}",
  "mqtt_port": 8883,
  "created_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

# Copy certificates (for Wi-Fi devices)
mkdir -p "device_package_${DEVICE_ID}/certificates"
cp "${TENANT_ID}-${DEVICE_ID}-cert.pem" "device_package_${DEVICE_ID}/certificates/"
cp "${TENANT_ID}-${DEVICE_ID}-private.key" "device_package_${DEVICE_ID}/certificates/"
cp AmazonRootCA1.pem "device_package_${DEVICE_ID}/certificates/"

# Create README
cat > "device_package_${DEVICE_ID}/README.txt" << EOF
DevTank OSM Device Credentials Package
======================================

Device: ${DEVICE_ID}
Tenant: ${TENANT_ID}
Site: ${SITE_ID}

For Wi-Fi devices, configure:
- MQTT Address: ${IOT_ENDPOINT}
- MQTT Port: 8883
- MQTT Scheme: TCP

For LoRaWAN devices:
- Configure DevEUI and AppKey in device
- Send DevEUI and AppKey to IT Operations for network server registration

Contact IT Operations if you encounter issues.
EOF

# Create ZIP package
zip -r "device_package_${DEVICE_ID}.zip" "device_package_${DEVICE_ID}/"

echo "Package ready: device_package_${DEVICE_ID}.zip"
echo "Send this package to the Onsite Configurer"
```

### 3.7 Detailed Step-by-Step: Onsite Configurer

#### Pre-arrival Checklist

- [ ] Received credentials package from IT Operations
- [ ] Laptop with Chrome browser
- [ ] USB-C cable
- [ ] USB drivers installed (Windows/Mac)
- [ ] Site Wi-Fi credentials (for Wi-Fi devices)
- [ ] Physical installation tools

#### On-site Procedure

**Step 1: Physical Installation**

1. Mount the DevTank sensor at the designated location
2. Ensure adequate signal coverage (Wi-Fi or LoRaWAN gateway range)
3. Connect power supply
4. Note the device serial number (printed on label)

**Step 2: Connect and Configure**

1. Connect device to laptop via USB-C cable
2. Open Chrome → https://osm-config.devtank.co.uk
3. Click **"Connect via USB"**
4. Select device from serial port dialog

**Step 3: Configure Communication**

*For Wi-Fi Devices:*

1. Open `device_info.json` from credentials package
2. In WiFi Configuration panel:
   - Select site Wi-Fi network (SSID)
   - Enter Wi-Fi password
   - Enter **MQTT Address**: (from device_info.json → iot_endpoint)
   - Set **MQTT Port**: `8883`
   - Set **MQTT Scheme**: `TCP`
3. Click **"Send"**

*For LoRaWAN Devices:*

1. In LoRaWAN Configuration panel:
   - Click **"Generate LoRa Dev EUI"** (or use existing)
   - Click **"Generate LoRa App Key"** (or use existing)
   - Select **Region**: `EU868 (4)`
2. **Record these values** to send to IT Operations:
   - DevEUI: `_______________________`
   - AppKey: `_______________________`
3. Click **"Send"**

**Step 4: Configure Measurements**

1. Set measurement intervals per project requirements:
   | Measurement | Recommended Interval |
   |-------------|---------------------|
   | TEMP, HUMI | 5 minutes |
   | PM1, PM25, PM4, PM10 | 15 minutes |
   | VOC, NOX | 15 minutes |
   | CC1, CC2 | 1 minute |
   | BAT | 60 minutes |

2. Click in each interval field and enter value
3. Or use **"Set Minimum Uplink Time"** for global setting

**Step 5: Save Configuration**

1. Click **"Save Configuration"** in navigation bar
2. Click **"Download Configuration"** to backup
3. Save as: `osm_${TENANT_ID}_${SITE_ID}_${DEVICE_ID}_config.json`

**Step 6: Send LoRaWAN Details to IT Operations**

For LoRaWAN devices, send this information to IT Operations:

```
Subject: LoRaWAN Registration Request - ${DEVICE_ID}

Device ID: ${DEVICE_ID}
Site: ${SITE_ID}
Tenant: ${TENANT_ID}

DevEUI: [value from device]
AppKey: [value from device]

Device installed and configured. Please register in network server.
```

**Step 7: Verify Connection**

1. For Wi-Fi: Check **Status** shows "Connected"
2. For LoRaWAN: Wait for IT Operations confirmation
3. Test measurements by clicking **"Get"** buttons
4. Confirm values are returned (not "n/a")

**Step 8: Complete Installation**

1. Disconnect USB cable
2. Secure device mounting
3. Document installation with photos
4. Complete site sign-off form

### 3.8 Detailed Step-by-Step: LoRaWAN Registration (IT Operations)

After receiving DevEUI/AppKey from Onsite Configurer:

#### TTN Registration

1. Login to TTN Console
2. Navigate to application `smdh-${TENANT_ID}`
3. Click **Add End Device** → **Manually**
4. Enter:
   - DevEUI: (from Onsite Configurer)
   - AppEUI: (same as DevEUI)
   - AppKey: (from Onsite Configurer)
5. Click **Register End Device**
6. Navigate to **Payload Formatters** → **Uplink**
7. Select **Custom JavaScript formatter**
8. Paste decoder (Section 8)
9. Save changes

#### Notify Onsite Configurer

```
Subject: Device Registered - ${DEVICE_ID}

Device ${DEVICE_ID} has been registered in the LoRaWAN network server.

Please verify:
1. Device shows join activity in OSM Config GUI
2. Status changes to "Connected"
3. Test measurements return values

Data should appear in Snowflake within 5-15 minutes of first transmission.

Confirm successful data flow so we can complete handover.
```

---

## 4. Prerequisites

### 4.1 Hardware Requirements

- DevTank OpenSmartMonitor device (Wi-Fi or LoRaWAN variant)
- USB-C cable for device configuration
- Computer with Google Chrome browser
- LoRaWAN gateway (for LoRaWAN devices) - e.g., Milesight UG65

### 4.2 Software Requirements

- **Windows/Mac**: Install CP210x USB-to-UART drivers
  - Download from: https://www.silabs.com/developers/usb-to-uart-bridge-vcp-drivers
  - Windows: Select "CP210x Windows Drivers"
  - Mac: Select "CP210x VCP Mac OSX Driver"

### 4.3 Account Requirements

- AWS Account with IoT Core access (eu-west-2 region)
- LoRaWAN Network Server account (ChirpStack, TTN, or Helium)
- SMDH Tenant ID assigned

### 4.4 Network Requirements

- For Wi-Fi devices: 2.4 GHz Wi-Fi network with internet access
- For LoRaWAN devices: LoRaWAN gateway within range (EU868 frequency)

---

## 5. DevTank Device Configuration

### 5.1 Connect to Device

1. Connect the OSM device to your computer using a USB-C cable
2. Open Google Chrome and navigate to: https://osm-config.devtank.co.uk
3. Click **"Connect via USB"**
4. Select the device from the browser's serial port dialog
5. The home page will display with device information

### 5.2 Configure Wi-Fi Device (for Wi-Fi variant)

If using a Wi-Fi enabled OSM device:

1. In the **WiFi Configuration** panel:
   - Click the reload icon next to **SSID** to scan for networks
   - Select your network from the dropdown (or select "Other:" for manual entry)
   - Enter the **WiFi Password**

2. Configure MQTT settings:
   | Field | Value |
   |-------|-------|
   | **MQTT Address** | `${IOT_ENDPOINT}.iot.eu-west-2.amazonaws.com` |
   | **MQTT User** | (leave blank for certificate auth) |
   | **MQTT Password** | (leave blank for certificate auth) |
   | **MQTT Port** | `8883` |
   | **MQTT Scheme** | `TCP` (TLS) |

3. Click **"Send"** to apply settings
4. Click **"Save Configuration"** in the navigation bar

### 5.3 Configure LoRaWAN Device (for LoRaWAN variant)

If using a LoRaWAN enabled OSM device:

1. In the **LoRaWAN Configuration** panel:
   - Click **"Generate LoRa Dev EUI"** or enter existing DevEUI
   - Click **"Generate LoRa App Key"** or enter existing AppKey
   - Select **Region**: `EU868 (4)`

2. **Record these values** - you will need them for network server registration:
   - Device EUI: `________________________`
   - Application Key: `________________________`

3. Click **"Send"** to apply settings
4. Click **"Save Configuration"** in the navigation bar

### 5.4 Configure Measurement Intervals

Configure how often each measurement is transmitted:

1. In the **Measurements** table on the left:
   - Each row shows a measurement type and its **Uplink Time (Mins)**
   - Setting a value to `0` disables that measurement

2. Recommended settings for SMDH:

   | Measurement | Uplink Time | Description |
   |-------------|-------------|-------------|
   | PM1 | 15 | Particulate Matter 1.0µm |
   | PM25 | 15 | Particulate Matter 2.5µm |
   | PM4 | 15 | Particulate Matter 4.0µm |
   | PM10 | 15 | Particulate Matter 10µm |
   | TEMP | 5 | Temperature |
   | HUMI | 5 | Humidity |
   | VOC | 15 | Volatile Organic Compounds |
   | NOX | 15 | Nitrogen Oxides |
   | CC1 | 1 | Current Clamp 1 (Energy) |
   | CC2 | 1 | Current Clamp 2 (Energy) |
   | BAT | 60 | Battery Level |

3. To set a global minimum uplink time:
   - Enter value in **"Set Minimum Uplink Time"** field
   - Click **"Submit"**

4. Click **"Save Configuration"**

### 5.5 Download Device Configuration

**Important**: Always backup your configuration before firmware updates.

1. Click **"Download Configuration"** in the navigation bar
2. Save the JSON file with a meaningful name (e.g., `osm_tenant_companyA_site001.json`)

### 5.6 Update Firmware (if required)

1. Check the **"Latest Firmware Available"** panel
2. Compare the SHA with your current **Firmware Version** (bottom left)
3. If different, click **"Flash Firmware"**
4. Wait for the update to complete and reconnect

For LoRaWAN devices, also update the communication module:
- Click **"Flash Comms Firmware"** to update the RAK3172 chip to v4.1.0

---

## 6. AWS IoT Core Setup

### 6.1 Create IoT Thing

Create an IoT Thing for each DevTank device:

```bash
# Set variables
export TENANT_ID="company_a"
export SITE_ID="site_001"
export DEVICE_ID="osm_001"
export AWS_REGION="eu-west-2"

# Create IoT Thing
aws iot create-thing \
  --thing-name "smdh-osm-${TENANT_ID}-${SITE_ID}-${DEVICE_ID}" \
  --thing-type-name "DevTankOSM" \
  --attribute-payload '{
    "attributes": {
      "tenant_id": "'${TENANT_ID}'",
      "site_id": "'${SITE_ID}'",
      "device_type": "OpenSmartMonitor",
      "sensor_types": "air_quality,energy,environment"
    }
  }' \
  --region ${AWS_REGION}
```

### 6.2 Create Thing Type (first time only)

```bash
aws iot create-thing-type \
  --thing-type-name "DevTankOSM" \
  --thing-type-properties '{
    "thingTypeDescription": "DevTank OpenSmartMonitor sensor device",
    "searchableAttributes": ["tenant_id", "site_id", "device_type"]
  }' \
  --region ${AWS_REGION}
```

### 6.3 Generate X.509 Certificates

```bash
# Create keys and certificate
aws iot create-keys-and-certificate \
  --set-as-active \
  --certificate-pem-outfile "${TENANT_ID}-${DEVICE_ID}-cert.pem" \
  --public-key-outfile "${TENANT_ID}-${DEVICE_ID}-public.key" \
  --private-key-outfile "${TENANT_ID}-${DEVICE_ID}-private.key" \
  --region ${AWS_REGION}

# Store the certificate ARN (from command output)
export CERT_ARN="arn:aws:iot:eu-west-2:123456789:cert/abc123..."

# Download Amazon Root CA
wget -O AmazonRootCA1.pem https://www.amazontrust.com/repository/AmazonRootCA1.pem
```

### 6.4 Create IoT Policy

Create a tenant-specific policy for the device:

```bash
# Create policy document
cat > iot-policy-${TENANT_ID}.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "iot:Connect",
      "Resource": "arn:aws:iot:eu-west-2:${ACCOUNT_ID}:client/smdh-osm-${TENANT_ID}-*"
    },
    {
      "Effect": "Allow",
      "Action": "iot:Publish",
      "Resource": [
        "arn:aws:iot:eu-west-2:${ACCOUNT_ID}:topic/smdh/${TENANT_ID}/sensor-data",
        "arn:aws:iot:eu-west-2:${ACCOUNT_ID}:topic/smdh/${TENANT_ID}/device-status"
      ]
    },
    {
      "Effect": "Allow",
      "Action": "iot:Subscribe",
      "Resource": "arn:aws:iot:eu-west-2:${ACCOUNT_ID}:topicfilter/smdh/${TENANT_ID}/commands/#"
    },
    {
      "Effect": "Allow",
      "Action": "iot:Receive",
      "Resource": "arn:aws:iot:eu-west-2:${ACCOUNT_ID}:topic/smdh/${TENANT_ID}/commands/*"
    }
  ]
}
EOF

# Create the policy
aws iot create-policy \
  --policy-name "smdh-osm-${TENANT_ID}-policy" \
  --policy-document file://iot-policy-${TENANT_ID}.json \
  --region ${AWS_REGION}
```

### 6.5 Attach Policy and Certificate to Thing

```bash
# Attach certificate to thing
aws iot attach-thing-principal \
  --thing-name "smdh-osm-${TENANT_ID}-${SITE_ID}-${DEVICE_ID}" \
  --principal "${CERT_ARN}" \
  --region ${AWS_REGION}

# Attach policy to certificate
aws iot attach-policy \
  --policy-name "smdh-osm-${TENANT_ID}-policy" \
  --target "${CERT_ARN}" \
  --region ${AWS_REGION}
```

### 6.6 Get IoT Endpoint

```bash
# Get your account's IoT endpoint
aws iot describe-endpoint \
  --endpoint-type iot:Data-ATS \
  --region ${AWS_REGION} \
  --query 'endpointAddress' \
  --output text

# Output example: a1b2c3d4e5f6g7-ats.iot.eu-west-2.amazonaws.com
```

### 6.7 Create IoT Rule for Kinesis

```bash
# Create IAM role for IoT Rules (first time only)
aws iam create-role \
  --role-name smdh-iot-kinesis-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "iot.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

# Attach Kinesis permissions
aws iam attach-role-policy \
  --role-name smdh-iot-kinesis-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonKinesisFullAccess

# Create IoT Rule
aws iot create-topic-rule \
  --rule-name smdh_devtank_to_kinesis \
  --topic-rule-payload '{
    "sql": "SELECT topic(2) as tenant_id, timestamp() as iot_timestamp, clientId() as device_id, * FROM '\''smdh/+/sensor-data'\''",
    "description": "Route DevTank sensor data to Kinesis",
    "actions": [{
      "kinesis": {
        "roleArn": "arn:aws:iam::'${ACCOUNT_ID}':role/smdh-iot-kinesis-role",
        "streamName": "smdh-sensor-data-stream",
        "partitionKey": "${tenant_id}"
      }
    }],
    "errorAction": {
      "republish": {
        "roleArn": "arn:aws:iam::'${ACCOUNT_ID}':role/smdh-iot-kinesis-role",
        "topic": "smdh/errors/devtank",
        "qos": 1
      }
    },
    "ruleDisabled": false
  }' \
  --region ${AWS_REGION}
```

---

## 7. LoRaWAN Network Server Configuration

For LoRaWAN devices, configure your network server to forward data to AWS IoT Core.

### 7.1 The Things Network (TTN) Setup

#### 7.1.1 Register Gateway

1. Access TTN Console: https://console.cloud.thethings.network
2. Select cluster: **Europe 1**
3. Navigate to **Gateways** → **Register Gateway**
4. Enter:
   - Gateway EUI (from your Milesight UG65)
   - Gateway name
   - Frequency plan: **Europe 863-870 MHz (SF9 for RX2)**
5. Click **Register Gateway**

#### 7.1.2 Create Application

1. Navigate to **Applications** → **Add Application**
2. Enter:
   - Application ID: `smdh-${TENANT_ID}`
   - Application name: `SMDH ${TENANT_ID}`
3. Click **Create Application**

#### 7.1.3 Register Device

1. Inside your application, click **Add End Device**
2. Select **Manually** tab
3. Configure:
   - Frequency plan: **Europe 863-870 MHz (SF9 for RX2)**
   - LoRaWAN version: **LoRaWAN Specification 1.0.0**
   - Regional Parameters: **TS001 Technical Specification 1.0.0**
4. Enter device identifiers:
   - DevEUI: (from DevTank device configuration)
   - AppEUI: (same as DevEUI)
   - AppKey: (from DevTank device configuration)
5. Click **Register End Device**

#### 7.1.4 Configure MQTT Integration

1. Navigate to **Integrations** → **MQTT**
2. Note the connection details for AWS IoT Core bridge
3. Configure AWS IoT Core to subscribe to TTN topics

### 7.2 ChirpStack Setup

#### 7.2.1 Create Device Profile

1. Navigate to **Device-profiles** → **Create**
2. Configure:
   - Device-profile name: `OSM_Sensor_Profile`
   - LoRaWAN MAC version: `1.0.2`
   - LoRaWAN Regional Parameters revision: `A`
   - Uplink interval (seconds): `300`
3. Under **CODEC** tab:
   - Select **Custom JavaScript codec functions**
   - Enter the decoder script (see Section 6)
4. Click **Create Device-Profile**

#### 7.2.2 Create Application

1. Navigate to **Applications** → **Create**
2. Enter:
   - Application name: `smdh_${TENANT_ID}`
   - Service profile: Select appropriate profile
3. Click **Create**

#### 7.2.3 Add Device

1. Inside your application, click **Create** (under Devices)
2. Configure:
   - Device name: `osm-${SITE_ID}-${DEVICE_ID}`
   - Device EUI: (from DevTank device)
   - Device-profile: `OSM_Sensor_Profile`
3. Click **Create Device**
4. Navigate to **Keys (OTAA)** tab
5. Enter **Application Key** (from DevTank device)
6. Click **Set Device-Keys**

#### 7.2.4 Configure AWS IoT Core Integration

1. Navigate to **Integrations** in your application
2. Add **AWS IoT** integration
3. Configure:
   - AWS Region: `eu-west-2`
   - AWS IoT Endpoint: (from Section 6.6)
   - Upload certificates generated in Section 6.3

### 7.3 Helium Setup

1. Access Helium Console: https://console.helium.com
2. Create organization
3. Navigate to **Devices** → **Add New Device**
4. Configure:
   - Device name: `osm-${TENANT_ID}-${DEVICE_ID}`
   - Dev EUI: (from DevTank device)
   - App Key: (from DevTank device)
   - App EUI: (fill with zeros)
5. Click **Save Device**
6. Verify device is within Helium Hotspot coverage at https://explorer.helium.com

---

## 8. Payload Decoder Configuration

DevTank devices transmit binary-encoded data that must be decoded to JSON.

### 8.1 JavaScript Decoder Function

Use this decoder in your LoRaWAN network server (TTN/ChirpStack/Helium):

```javascript
function decodeUplink(bytes) {
  var pos = 0;
  var data = {};

  var protocol_version = bytes[pos++];
  if (protocol_version !== 1) {
    return data;
  }

  var name;
  while (pos < bytes.length) {
    name = "";
    for (var i = 0; i < 4; i++) {
      if (bytes[pos] !== 0) {
        name += String.fromCharCode(bytes[pos]);
      }
      pos++;
    }

    if (name.length === 0) {
      break;
    }

    // Read value (2 bytes, little-endian)
    var value = bytes[pos] | (bytes[pos + 1] << 8);
    pos += 2;

    // Handle signed values for temperature
    if (name === "TEMP" || name.startsWith("TMP")) {
      if (value > 32767) {
        value = value - 65536;
      }
    }

    data[name] = value;
  }

  return {
    data: data
  };
}

// Alternative format for TTN v3
function Decoder(bytes, fPort) {
  return decodeUplink(bytes).data;
}
```

### 8.2 Decoded Output Format

The decoder produces JSON with the following structure:

```json
{
  "BAT": 3600,
  "BAT_max": 3650,
  "BAT_min": 3550,
  "CC1": 1250,
  "CC1_max": 1300,
  "CC1_min": 1200,
  "CC2": 850,
  "HUMI": 4500,
  "TEMP": 2250,
  "PM1": 8,
  "PM25": 12,
  "PM4": 15,
  "PM10": 18,
  "VOC": 150,
  "NOX": 25
}
```

### 8.3 Value Scaling

Apply these scaling factors when processing in Snowflake:

| Field | Raw Value | Scaling | Actual Value |
|-------|-----------|---------|--------------|
| TEMP | 2250 | ÷ 100 | 22.50 °C |
| HUMI | 4500 | ÷ 100 | 45.00 % |
| BAT | 3600 | ÷ 1000 | 3.6 V |
| CC1/CC2 | 1250 | ÷ 1 | 1250 mA |
| PM1/PM25/PM4/PM10 | 12 | ÷ 1 | 12 µg/m³ |
| VOC | 150 | ÷ 1 | 150 ppb |
| NOX | 25 | ÷ 1 | 25 ppb |

### 8.4 Snowflake Transformation

Transform the decoded payload in Snowflake Dynamic Tables:

```sql
CREATE OR REPLACE DYNAMIC TABLE smdh_tenant_${TENANT_ID}.normalized.devtank_readings
TARGET_LAG = '1 minute'
WAREHOUSE = streaming_wh
AS
SELECT
    tenant_id,
    device_id,
    iot_timestamp as timestamp,

    -- Temperature (scaled)
    payload:TEMP::FLOAT / 100 as temperature_c,

    -- Humidity (scaled)
    payload:HUMI::FLOAT / 100 as humidity_pct,

    -- Air Quality
    payload:PM1::INTEGER as pm1_ugm3,
    payload:PM25::INTEGER as pm25_ugm3,
    payload:PM4::INTEGER as pm4_ugm3,
    payload:PM10::INTEGER as pm10_ugm3,
    payload:VOC::INTEGER as voc_ppb,
    payload:NOX::INTEGER as nox_ppb,

    -- Energy (Current Clamps)
    payload:CC1::INTEGER as current_clamp_1_ma,
    payload:CC2::INTEGER as current_clamp_2_ma,

    -- Battery (scaled)
    payload:BAT::FLOAT / 1000 as battery_v,

    -- Source metadata
    'devtank_osm' as source_system,
    ingestion_timestamp

FROM smdh_tenant_${TENANT_ID}.raw.sensor_readings
WHERE source_system = 'lorawan_gateway'
  AND payload:TEMP IS NOT NULL;
```

---

## 9. Testing and Validation

### 9.1 Verify Device Connection

#### For Wi-Fi Devices:
1. In OSM Config GUI, check **Status** field shows "Connected"
2. Monitor AWS IoT Core console for incoming messages

#### For LoRaWAN Devices:
1. Check LoRaWAN network server for device join events
2. Verify "Last seen" timestamp updates

### 9.2 Test MQTT Connection (Wi-Fi)

```bash
# Subscribe to device topic in AWS IoT Core
aws iot-data subscribe \
  --topic "smdh/${TENANT_ID}/sensor-data" \
  --region eu-west-2

# Or use AWS IoT Core console MQTT test client
# Subscribe to: smdh/+/sensor-data
```

### 9.3 Verify Data in Snowflake

```sql
-- Check raw data ingestion
SELECT
    tenant_id,
    device_id,
    iot_timestamp,
    payload
FROM smdh_tenant_${TENANT_ID}.raw.sensor_readings
WHERE source_system = 'lorawan_gateway'
ORDER BY iot_timestamp DESC
LIMIT 10;

-- Verify decoded values
SELECT
    tenant_id,
    device_id,
    timestamp,
    temperature_c,
    humidity_pct,
    pm25_ugm3,
    battery_v
FROM smdh_tenant_${TENANT_ID}.normalized.devtank_readings
ORDER BY timestamp DESC
LIMIT 10;
```

### 9.4 Test Individual Measurements

In OSM Config GUI:
1. Click **"Get"** button next to each measurement
2. Verify values are returned (not "n/a")
3. Confirm values are within expected ranges

### 9.5 End-to-End Latency Test

1. Note the time when clicking "Get" for a measurement
2. Check Snowflake for corresponding record
3. Expected latency:
   - LoRaWAN path: 5-15 seconds
   - Wi-Fi MQTT path: 3-10 seconds

---

## 10. Troubleshooting

### 10.1 Device Won't Connect (Wi-Fi)

| Symptom | Possible Cause | Solution |
|---------|---------------|----------|
| Status: "Disconnected" | Wrong SSID/password | Re-enter Wi-Fi credentials |
| Status: "Disconnected" | MQTT settings incorrect | Verify IoT endpoint and port (8883) |
| Certificate error | Invalid certificates | Re-generate and re-upload certificates |
| Connection timeout | Firewall blocking | Ensure port 8883 outbound is open |

### 10.2 Device Won't Join (LoRaWAN)

| Symptom | Possible Cause | Solution |
|---------|---------------|----------|
| No join request | Out of gateway range | Move device closer to gateway |
| Join rejected | Wrong AppKey | Verify AppKey matches network server |
| Join rejected | Wrong DevEUI | Verify DevEUI matches registration |
| No data after join | Payload formatter missing | Add JavaScript decoder |

### 10.3 No Data in Snowflake

| Symptom | Possible Cause | Solution |
|---------|---------------|----------|
| No raw records | IoT Rule not firing | Check IoT Rule SQL and topic pattern |
| No raw records | Kinesis not receiving | Verify Kinesis stream exists |
| Raw data, no normalized | Decoder not applied | Check payload formatter in network server |
| Data delayed | Stream lag | Check Dynamic Table TARGET_LAG setting |

### 10.4 Invalid Measurement Values

| Symptom | Possible Cause | Solution |
|---------|---------------|----------|
| All values "n/a" | Sensor not equipped | Verify device model has that sensor |
| Values out of range | Scaling not applied | Apply scaling factors (Section 8.3) |
| Negative temperature | Sign conversion issue | Update decoder for signed values |

### 10.5 Common Error Messages

**"Failed to read measurement"**
- The device may not have that sensor installed
- Only OpenSense Air models have temperature/humidity/VOC sensors

**"Certificate not found"**
- Certificate not attached to IoT Thing
- Run `attach-thing-principal` command again

**"Policy does not allow"**
- IoT Policy doesn't permit the action
- Verify topic names match policy resources

### 10.6 Reset Device Configuration

If the device becomes unresponsive:

1. Connect via USB-C
2. Access OSM Config GUI
3. Click **"Load Configuration"**
4. Select your backup configuration file
5. Reconnect and verify settings

---

## Appendix A: Device Registration Checklist

Use this checklist for each new DevTank device:

### Device Configuration
- [ ] Drivers installed (Windows/Mac)
- [ ] Device connected via USB-C
- [ ] OSM Config GUI accessed
- [ ] Communication type configured (Wi-Fi or LoRaWAN)
- [ ] DevEUI/AppKey recorded (LoRaWAN)
- [ ] Measurement intervals configured
- [ ] Configuration downloaded as backup
- [ ] Firmware updated (if required)

### AWS IoT Core
- [ ] IoT Thing created
- [ ] X.509 certificates generated
- [ ] IoT Policy created
- [ ] Certificate attached to Thing
- [ ] Policy attached to Certificate
- [ ] IoT Rule configured for Kinesis

### LoRaWAN Network Server (if applicable)
- [ ] Gateway registered
- [ ] Application created
- [ ] Device registered with DevEUI/AppKey
- [ ] Payload decoder configured
- [ ] AWS IoT Core integration enabled

### Validation
- [ ] Device shows "Connected" status
- [ ] Data appears in AWS IoT Core
- [ ] Data flows to Kinesis stream
- [ ] Data appears in Snowflake raw tables
- [ ] Normalized data has correct values

---

## Appendix B: Reference Information

### MQTT Topic Structure

```
smdh/{tenant_id}/sensor-data     # Sensor readings
smdh/{tenant_id}/device-status   # Device health/status
smdh/{tenant_id}/commands/#      # Commands to device (subscribe)
smdh/errors/devtank              # Error messages
```

### Measurement Codes

| Code | Full Name | Sensor Type |
|------|-----------|-------------|
| PM1 | Particulate Matter 1.0µm | Air Quality |
| PM25 | Particulate Matter 2.5µm | Air Quality |
| PM4 | Particulate Matter 4.0µm | Air Quality |
| PM10 | Particulate Matter 10µm | Air Quality |
| TEMP | Temperature | Environment |
| HUMI | Humidity | Environment |
| VOC | Volatile Organic Compounds | Air Quality |
| NOX | Nitrogen Oxides | Air Quality |
| CC1 | Current Clamp 1 | Energy |
| CC2 | Current Clamp 2 | Energy |
| CC3 | Current Clamp 3 | Energy |
| BAT | Battery Level | Device |
| LGHT | Light Level | Environment |
| SND | Sound Level | Environment |

### AWS Region

All SMDH AWS resources are deployed in **eu-west-2 (London)**.

### Support Contacts

- **DevTank Support**: https://devtank.co.uk/contact
- **AWS IoT Core Documentation**: https://docs.aws.amazon.com/iot/
- **TTN Documentation**: https://www.thethingsindustries.com/docs/

---

*Document Version: 1.0*
*Last Updated: 19 November 2025*
