#!/bin/bash

# SMDH Certificate Management Helper
# Helps extract and manage IoT certificates from Terraform state

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default paths
TERRAFORM_DIR="../infrastructure/terraform"
CERTS_DIR="./certificates"

# Function to display usage
usage() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  extract-cert   Extract certificates from Terraform state"
    echo "  create-local   Create local test certificates (self-signed)"
    echo "  download-ca    Download AWS IoT Root CA certificates"
    echo "  validate       Validate certificate chain"
    echo "  info           Display certificate information"
    echo ""
    echo "Options:"
    echo "  -t TENANT      Tenant ID (for extract-cert)"
    echo "  -s SITE        Site ID (for extract-cert)"
    echo "  -d DEVICE      Device name (for extract-cert)"
    echo "  -c CERT        Certificate file path (for validate/info)"
    echo "  -o OUTPUT      Output directory (default: ./certificates)"
    echo "  -h             Show this help message"
    echo ""
    echo "Examples:"
    echo "  # Extract certificates for a specific device"
    echo "  $0 extract-cert -t tenant-001 -s site_001 -d gw_001"
    echo ""
    echo "  # Create local test certificates"
    echo "  $0 create-local -d test-device-001"
    echo ""
    echo "  # Download AWS Root CA"
    echo "  $0 download-ca"
    echo ""
    echo "  # Validate certificate"
    echo "  $0 validate -c ./certificates/device.crt"
}

# Function to extract certificates from Terraform state
extract_certificates() {
    local tenant=$1
    local site=$2
    local device=$3
    local output_dir=${4:-$CERTS_DIR}

    echo -e "${YELLOW}Extracting certificates from Terraform state...${NC}"

    # Create output directory
    mkdir -p "$output_dir/$tenant/$site"

    # Navigate to Terraform directory
    cd "$TERRAFORM_DIR"

    # Get the thing name
    local thing_name="smdh-gateway-${tenant}-${site}-${device}"

    echo "Looking for certificates for: $thing_name"

    # Extract certificate data from Terraform state
    echo -e "${BLUE}Extracting certificate and key...${NC}"

    # Get certificate ARN
    cert_arn=$(terraform state show "module.tenants[\"${tenant}\"].aws_iot_certificate.gateways[\"${thing_name}\"]" 2>/dev/null | grep "arn" | head -1 | awk '{print $3}' | tr -d '"')

    if [[ -z "$cert_arn" ]]; then
        echo -e "${RED}Error: Could not find certificate for ${thing_name}${NC}"
        echo "Available things:"
        terraform state list | grep "aws_iot_thing" | head -10
        return 1
    fi

    # Extract certificate PEM
    terraform state show "module.tenants[\"${tenant}\"].aws_iot_certificate.gateways[\"${thing_name}\"]" | \
        sed -n '/certificate_pem/,/EOT/p' | sed '1d;$d' > "$output_dir/$tenant/$site/${device}_certificate.pem"

    # Extract private key
    terraform state show "module.tenants[\"${tenant}\"].aws_iot_certificate.gateways[\"${thing_name}\"]" | \
        sed -n '/private_key/,/EOT/p' | sed '1d;$d' > "$output_dir/$tenant/$site/${device}_private_key.pem"

    # Extract public key
    terraform state show "module.tenants[\"${tenant}\"].aws_iot_certificate.gateways[\"${thing_name}\"]" | \
        sed -n '/public_key/,/EOT/p' | sed '1d;$d' > "$output_dir/$tenant/$site/${device}_public_key.pem"

    # Return to original directory
    cd - > /dev/null

    echo -e "${GREEN}✓ Certificates extracted to: $output_dir/$tenant/$site/${NC}"
    echo "  - Certificate: ${device}_certificate.pem"
    echo "  - Private Key: ${device}_private_key.pem"
    echo "  - Public Key: ${device}_public_key.pem"

    # Set appropriate permissions
    chmod 600 "$output_dir/$tenant/$site/${device}_private_key.pem"
    chmod 644 "$output_dir/$tenant/$site/${device}_certificate.pem"
    chmod 644 "$output_dir/$tenant/$site/${device}_public_key.pem"

    return 0
}

# Function to create local self-signed certificates for testing
create_local_certificates() {
    local device=$1
    local output_dir=${2:-$CERTS_DIR}

    echo -e "${YELLOW}Creating local test certificates...${NC}"

    mkdir -p "$output_dir/local"

    # Generate private key
    openssl genrsa -out "$output_dir/local/${device}_private_key.pem" 2048

    # Generate certificate signing request
    openssl req -new \
        -key "$output_dir/local/${device}_private_key.pem" \
        -out "$output_dir/local/${device}.csr" \
        -subj "/C=GB/ST=London/L=London/O=SMDH Test/CN=${device}"

    # Generate self-signed certificate
    openssl x509 -req \
        -in "$output_dir/local/${device}.csr" \
        -signkey "$output_dir/local/${device}_private_key.pem" \
        -out "$output_dir/local/${device}_certificate.pem" \
        -days 365

    # Extract public key
    openssl rsa -in "$output_dir/local/${device}_private_key.pem" \
        -pubout -out "$output_dir/local/${device}_public_key.pem"

    # Clean up CSR
    rm "$output_dir/local/${device}.csr"

    echo -e "${GREEN}✓ Local test certificates created in: $output_dir/local${NC}"
    echo "  - Certificate: ${device}_certificate.pem"
    echo "  - Private Key: ${device}_private_key.pem"
    echo "  - Public Key: ${device}_public_key.pem"

    # Set permissions
    chmod 600 "$output_dir/local/${device}_private_key.pem"
    chmod 644 "$output_dir/local/${device}_certificate.pem"
    chmod 644 "$output_dir/local/${device}_public_key.pem"
}

# Function to download AWS IoT Root CA certificates
download_root_ca() {
    local output_dir=${1:-$CERTS_DIR}

    echo -e "${YELLOW}Downloading AWS IoT Root CA certificates...${NC}"

    mkdir -p "$output_dir/ca"

    # Download Amazon Root CA 1
    echo "Downloading Amazon Root CA 1..."
    curl -s https://www.amazontrust.com/repository/AmazonRootCA1.pem \
        -o "$output_dir/ca/AmazonRootCA1.pem"

    # Download Amazon Root CA 3
    echo "Downloading Amazon Root CA 3..."
    curl -s https://www.amazontrust.com/repository/AmazonRootCA3.pem \
        -o "$output_dir/ca/AmazonRootCA3.pem"

    # Download Starfield Root CA (legacy support)
    echo "Downloading Starfield Services Root CA..."
    curl -s https://www.amazontrust.com/repository/SFSRootCAG2.pem \
        -o "$output_dir/ca/SFSRootCAG2.pem"

    echo -e "${GREEN}✓ Root CA certificates downloaded to: $output_dir/ca${NC}"
    ls -la "$output_dir/ca/"
}

# Function to validate certificate chain
validate_certificate() {
    local cert_file=$1

    echo -e "${YELLOW}Validating certificate...${NC}"

    if [[ ! -f "$cert_file" ]]; then
        echo -e "${RED}Error: Certificate file not found: $cert_file${NC}"
        return 1
    fi

    # Display certificate details
    echo -e "${BLUE}Certificate Details:${NC}"
    openssl x509 -in "$cert_file" -noout -text | grep -E "(Subject:|Issuer:|Not Before:|Not After:)"

    # Check certificate validity
    echo -e "\n${BLUE}Certificate Validity:${NC}"
    if openssl x509 -in "$cert_file" -noout -checkend 0; then
        echo -e "${GREEN}✓ Certificate is currently valid${NC}"
    else
        echo -e "${RED}✗ Certificate has expired or is not yet valid${NC}"
    fi

    # Check certificate dates
    not_before=$(openssl x509 -in "$cert_file" -noout -startdate | cut -d= -f2)
    not_after=$(openssl x509 -in "$cert_file" -noout -enddate | cut -d= -f2)
    echo "  Valid from: $not_before"
    echo "  Valid to:   $not_after"

    # Verify certificate signature
    echo -e "\n${BLUE}Signature Verification:${NC}"
    if openssl x509 -in "$cert_file" -noout; then
        echo -e "${GREEN}✓ Certificate signature is valid${NC}"
    else
        echo -e "${RED}✗ Certificate signature is invalid${NC}"
    fi
}

# Function to display certificate information
certificate_info() {
    local cert_file=$1

    echo -e "${YELLOW}Certificate Information${NC}"
    echo "=" | tr '=' '-'

    if [[ ! -f "$cert_file" ]]; then
        echo -e "${RED}Error: Certificate file not found: $cert_file${NC}"
        return 1
    fi

    # Extract and display key information
    echo -e "${BLUE}Subject:${NC}"
    openssl x509 -in "$cert_file" -noout -subject | sed 's/subject=/  /'

    echo -e "\n${BLUE}Issuer:${NC}"
    openssl x509 -in "$cert_file" -noout -issuer | sed 's/issuer=/  /'

    echo -e "\n${BLUE}Serial Number:${NC}"
    openssl x509 -in "$cert_file" -noout -serial | sed 's/serial=/  /'

    echo -e "\n${BLUE}Validity Period:${NC}"
    openssl x509 -in "$cert_file" -noout -dates | sed 's/^/  /'

    echo -e "\n${BLUE}Signature Algorithm:${NC}"
    openssl x509 -in "$cert_file" -noout -text | grep "Signature Algorithm" | head -1 | sed 's/^/  /'

    echo -e "\n${BLUE}Key Usage:${NC}"
    openssl x509 -in "$cert_file" -noout -text | grep -A1 "Key Usage" | tail -1 | sed 's/^/  /'

    echo -e "\n${BLUE}Fingerprints:${NC}"
    echo -n "  SHA1:   "
    openssl x509 -in "$cert_file" -noout -fingerprint -sha1 | cut -d= -f2
    echo -n "  SHA256: "
    openssl x509 -in "$cert_file" -noout -fingerprint -sha256 | cut -d= -f2
}

# Main script execution
COMMAND=$1
shift

# Parse options
while getopts "t:s:d:c:o:h" opt; do
    case $opt in
        t) TENANT="$OPTARG" ;;
        s) SITE="$OPTARG" ;;
        d) DEVICE="$OPTARG" ;;
        c) CERT_FILE="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        h) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done

# Set default output directory if not specified
OUTPUT_DIR=${OUTPUT_DIR:-$CERTS_DIR}

# Execute command
case $COMMAND in
    extract-cert)
        if [[ -z "$TENANT" || -z "$SITE" || -z "$DEVICE" ]]; then
            echo -e "${RED}Error: Tenant, site, and device are required for extract-cert${NC}"
            usage
            exit 1
        fi
        extract_certificates "$TENANT" "$SITE" "$DEVICE" "$OUTPUT_DIR"
        ;;

    create-local)
        if [[ -z "$DEVICE" ]]; then
            echo -e "${RED}Error: Device name is required for create-local${NC}"
            usage
            exit 1
        fi
        create_local_certificates "$DEVICE" "$OUTPUT_DIR"
        ;;

    download-ca)
        download_root_ca "$OUTPUT_DIR"
        ;;

    validate)
        if [[ -z "$CERT_FILE" ]]; then
            echo -e "${RED}Error: Certificate file is required for validate${NC}"
            usage
            exit 1
        fi
        validate_certificate "$CERT_FILE"
        ;;

    info)
        if [[ -z "$CERT_FILE" ]]; then
            echo -e "${RED}Error: Certificate file is required for info${NC}"
            usage
            exit 1
        fi
        certificate_info "$CERT_FILE"
        ;;

    *)
        echo -e "${RED}Error: Unknown command: $COMMAND${NC}"
        usage
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}Operation complete!${NC}"