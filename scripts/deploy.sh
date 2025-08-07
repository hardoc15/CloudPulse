
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

deploy_infrastructure() {
    print_status "Deploying CloudPulse infrastructure..."
    
    cd "$(dirname "$0")/../terraform"
    
    if [ ! -d ".terraform" ]; then
        print_error "Terraform not initialized. Run ./scripts/setup.sh first."
        exit 1
    fi
    
    print_status "Planning Terraform deployment..."
    terraform plan -out=tfplan
    
    echo ""
    read -p "Do you want to proceed with the deployment? [y/N]: " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Deployment cancelled."
        rm -f tfplan
        exit 0
    fi
    
    print_status "Applying Terraform configuration..."
    terraform apply tfplan
    
    rm -f tfplan
    
    print_success "Infrastructure deployment complete!"
    
    cd - >/dev/null
}

get_terraform_outputs() {
    print_status "Getting infrastructure details..."
    
    cd "$(dirname "$0")/../terraform"
    
    if ! terraform show >/dev/null 2>&1; then
        print_error "No infrastructure found. Deploy first with terraform apply."
        exit 1
    fi
    
    API_ENDPOINT=$(terraform output -raw api_gateway_url 2>/dev/null || echo "")
    KINESIS_STREAM=$(terraform output -raw kinesis_stream_name 2>/dev/null || echo "")
    DASHBOARD_URL=$(terraform output -raw cloudwatch_dashboard_url 2>/dev/null || echo "")
    S3_BUCKET=$(terraform output -raw s3_data_lake_bucket 2>/dev/null || echo "")
    
    cd - >/dev/null
    
    if [ -z "$API_ENDPOINT" ] || [ -z "$KINESIS_STREAM" ]; then
        print_error "Failed to get infrastructure outputs. Check if deployment was successful."
        exit 1
    fi
    
    print_success "Infrastructure details retrieved"
    echo "  API Endpoint: $API_ENDPOINT/ingest"
    echo "  Kinesis Stream: $KINESIS_STREAM"
    echo "  S3 Bucket: $S3_BUCKET"
    echo "  Dashboard: $DASHBOARD_URL"
}

test_data_generator() {
    print_status "Testing data generator..."
    
    cd "$(dirname "$0")/../src/data-generator"
    
    if [ ! -d "venv" ]; then
        print_error "Python environment not found. Run ./scripts/setup.sh first."
        exit 1
    fi
    
    source venv/bin/activate
    
    print_status "Generating sample data..."
    python app.py --test
    
    print_success "Data generator test complete"
    
    cd - >/dev/null
}

send_test_data() {
    print_status "Sending test data to the pipeline..."
    
    cd "$(dirname "$0")/../src/data-generator"
    source venv/bin/activate
    
    print_status "Sending single test record..."
    python app.py --api-endpoint "$API_ENDPOINT/ingest" --single
    
    print_success "Test data sent successfully!"
    
    cd - >/dev/null
}

start_data_generation() {
    print_status "Starting continuous data generation..."
    
    cd "$(dirname "$0")/../src/data-generator"
    source venv/bin/activate
    
    echo ""
    print_status "Data Generation Options:"
    echo "1. Low rate (1 record/second for 5 minutes)"
    echo "2. Medium rate (10 records/second for 10 minutes)"
    echo "3. High rate (50 records/second for 5 minutes)"
    echo "4. Custom configuration"
    echo "5. Skip data generation"
    echo ""
    
    read -p "Select option [1-5]: " -n 1 -r
    echo ""
    
    case $REPLY in
        1)
            print_status "Starting low rate data generation..."
            python app.py --api-endpoint "$API_ENDPOINT/ingest" --rate 1 --duration 300 --batch-size 5
            ;;
        2)
            print_status "Starting medium rate data generation..."
            python app.py --api-endpoint "$API_ENDPOINT/ingest" --rate 10 --duration 600 --batch-size 10
            ;;
        3)
            print_status "Starting high rate data generation..."
            python app.py --api-endpoint "$API_ENDPOINT/ingest" --rate 50 --duration 300 --batch-size 25
            ;;
        4)
            echo ""
            read -p "Enter rate (records/second): " rate
            read -p "Enter duration (seconds): " duration
            read -p "Enter batch size: " batch_size
            
            print_status "Starting custom data generation..."
            python app.py --api-endpoint "$API_ENDPOINT/ingest" --rate "$rate" --duration "$duration" --batch-size "$batch_size"
            ;;
        5)
            print_status "Skipping data generation."
            ;;
        *)
            print_warning "Invalid option. Skipping data generation."
            ;;
    esac
    
    cd - >/dev/null
}

show_monitoring_info() {
    print_success "Deployment and setup complete!"
    echo ""
    echo "🎯 CloudPulse is now running!"
    echo "================================="
    echo ""
    echo "📊 Monitoring & Dashboards:"
    echo "  CloudWatch Dashboard: $DASHBOARD_URL"
    echo "  AWS Console: https://console.aws.amazon.com/cloudwatch/"
    echo ""
    echo "📡 API Endpoint:"
    echo "  $API_ENDPOINT/ingest"
    echo ""
    echo "🗄️  Data Storage:"
    echo "  S3 Bucket: $S3_BUCKET"
    echo "  Kinesis Stream: $KINESIS_STREAM"
    echo ""
    echo "🔧 Manual Data Generation:"
    echo "  cd src/data-generator && source venv/bin/activate"
    echo "  python app.py --api-endpoint $API_ENDPOINT/ingest --rate 10"
    echo ""
    echo "🛠️  Infrastructure Management:"
    echo "  View resources: cd terraform && terraform show"
    echo "  Destroy: cd terraform && terraform destroy"
    echo ""
    echo "📈 Next Steps:"
    echo "  1. Check the CloudWatch dashboard for metrics"
    echo "  2. Explore the S3 bucket for processed data"
    echo "  3. Set up additional alerts if needed"
    echo "  4. Customize the data generation patterns"
    echo ""
}

show_help() {
    echo "CloudPulse Deployment Script"
    echo ""
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  --infrastructure-only   Deploy infrastructure only"
    echo "  --test-only            Test data generator only"
    echo "  --start-generator      Start data generation only"
    echo ""
    echo "Default: Deploy infrastructure and optionally start data generation"
}

INFRASTRUCTURE_ONLY=false
TEST_ONLY=false
START_GENERATOR=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --infrastructure-only)
            INFRASTRUCTURE_ONLY=true
            shift
            ;;
        --test-only)
            TEST_ONLY=true
            shift
            ;;
        --start-generator)
            START_GENERATOR=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

main() {
    echo ""
    print_status "🚀 CloudPulse Deployment Script"
    echo "===================================="
    echo ""
    
    if [ "$TEST_ONLY" = true ]; then
        test_data_generator
        return
    fi
    
    if [ "$START_GENERATOR" = true ]; then
        get_terraform_outputs
        start_data_generation
        return
    fi
    
    deploy_infrastructure
    
    get_terraform_outputs
    
    if [ "$INFRASTRUCTURE_ONLY" = false ]; then
        test_data_generator
        
        send_test_data
        
        start_data_generation
    fi
    
    show_monitoring_info
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
