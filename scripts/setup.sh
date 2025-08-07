#!/bin/bash

# CloudPulse Setup Script
# This script sets up the CloudPulse project environment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS credentials
check_aws_credentials() {
    print_status "Checking AWS credentials..."
    if ! command_exists aws; then
        print_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        print_error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    print_success "AWS credentials are configured"
    
    # Display current AWS identity
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    REGION=$(aws configure get region || echo "us-east-1")
    print_status "AWS Account: $ACCOUNT_ID"
    print_status "AWS Region: $REGION"
}

# Function to check dependencies
check_dependencies() {
    print_status "Checking dependencies..."
    
    local missing_deps=()
    
    if ! command_exists terraform; then
        missing_deps+=("terraform")
    fi
    
    if ! command_exists python3; then
        missing_deps+=("python3")
    fi
    
    if ! command_exists pip3; then
        missing_deps+=("pip3")
    fi
    
    if ! command_exists docker; then
        missing_deps+=("docker")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        print_status "Please install the missing dependencies and run this script again."
        
        if [[ "$OSTYPE" == "darwin"* ]]; then
            print_status "On macOS, you can install them with:"
            echo "  brew install terraform python3 docker"
        elif [[ "$OSTYPE" == "linux"* ]]; then
            print_status "On Ubuntu/Debian, you can install them with:"
            echo "  sudo apt update"
            echo "  sudo apt install terraform python3 python3-pip docker.io"
        fi
        exit 1
    fi
    
    print_success "All dependencies are installed"
}

# Function to setup Python environment
setup_python_environment() {
    print_status "Setting up Python environment..."
    
    cd "$(dirname "$0")/../src/data-generator"
    
    # Create virtual environment if it doesn't exist
    if [ ! -d "venv" ]; then
        print_status "Creating Python virtual environment..."
        python3 -m venv venv
    fi
    
    # Activate virtual environment
    source venv/bin/activate
    
    # Install requirements
    print_status "Installing Python requirements..."
    pip install -r requirements.txt
    
    print_success "Python environment setup complete"
    
    cd - >/dev/null
}

# Function to initialize Terraform
initialize_terraform() {
    print_status "Initializing Terraform..."
    
    cd "$(dirname "$0")/../terraform"
    
    # Initialize Terraform
    terraform init
    
    # Validate configuration
    print_status "Validating Terraform configuration..."
    terraform validate
    
    print_success "Terraform initialization complete"
    
    cd - >/dev/null
}

# Function to create terraform.tfvars if it doesn't exist
create_terraform_vars() {
    local tfvars_file="$(dirname "$0")/../terraform/terraform.tfvars"
    
    if [ ! -f "$tfvars_file" ]; then
        print_status "Creating terraform.tfvars file..."
        
        # Get current AWS region
        local region=$(aws configure get region || echo "us-east-1")
        
        cat > "$tfvars_file" << EOF
# CloudPulse Configuration
# Modify these values as needed

aws_region    = "$region"
environment   = "dev"

# Kinesis configuration
kinesis_shard_count     = 2
kinesis_retention_period = 24

# Lambda configuration
lambda_memory_size = 256
lambda_timeout     = 30

# DynamoDB configuration
dynamodb_billing_mode = "PAY_PER_REQUEST"

# Monitoring configuration
alert_email = ""  # Add your email address for alerts

# Resource protection
enable_deletion_protection = false
EOF
        
        print_success "Created terraform.tfvars file"
        print_warning "Please edit terraform.tfvars to customize your configuration"
        print_warning "Especially add your email address for alerts"
    else
        print_status "terraform.tfvars already exists"
    fi
}

# Function to show next steps
show_next_steps() {
    print_success "CloudPulse setup complete!"
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. Edit terraform/terraform.tfvars to customize your configuration"
    echo "   - Add your email address for alerts"
    echo "   - Adjust resource sizes if needed"
    echo ""
    echo "2. Plan the infrastructure deployment:"
    echo "   cd terraform && terraform plan"
    echo ""
    echo "3. Deploy the infrastructure:"
    echo "   cd terraform && terraform apply"
    echo ""
    echo "4. Test the data generator:"
    echo "   cd src/data-generator && source venv/bin/activate"
    echo "   python app.py --test"
    echo ""
    echo "5. Start sending data (after infrastructure is deployed):"
    echo "   python app.py --api-endpoint <API_ENDPOINT_FROM_TERRAFORM_OUTPUT>"
    echo ""
    echo "6. View the dashboard:"
    echo "   Check the CloudWatch dashboard URL from terraform outputs"
    echo ""
}

# Main execution
main() {
    echo ""
    print_status "🚀 CloudPulse Setup Script"
    echo "================================="
    echo ""
    
    check_dependencies
    check_aws_credentials
    create_terraform_vars
    setup_python_environment
    initialize_terraform
    
    echo ""
    show_next_steps
}

# Check if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
