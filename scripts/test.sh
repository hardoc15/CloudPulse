#!/bin/bash

# CloudPulse Test Script
# End-to-end testing for the CloudPulse pipeline

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

# Function to get terraform outputs
get_infrastructure_info() {
    print_status "Getting infrastructure information..."
    
    cd "$(dirname "$0")/../terraform"
    
    # Check if infrastructure exists
    if ! terraform show >/dev/null 2>&1; then
        print_error "No infrastructure found. Deploy first with ./scripts/deploy.sh"
        exit 1
    fi
    
    # Get outputs
    API_ENDPOINT=$(terraform output -raw api_gateway_url 2>/dev/null || echo "")
    KINESIS_STREAM=$(terraform output -raw kinesis_stream_name 2>/dev/null || echo "")
    S3_BUCKET=$(terraform output -raw s3_data_lake_bucket 2>/dev/null || echo "")
    
    cd - >/dev/null
    
    if [ -z "$API_ENDPOINT" ] || [ -z "$KINESIS_STREAM" ] || [ -z "$S3_BUCKET" ]; then
        print_error "Failed to get infrastructure outputs"
        exit 1
    fi
    
    print_success "Infrastructure information retrieved"
    echo "  API Endpoint: $API_ENDPOINT"
    echo "  Kinesis Stream: $KINESIS_STREAM"
    echo "  S3 Bucket: $S3_BUCKET"
}

# Function to test data generator
test_data_generator() {
    print_status "Testing data generator..."
    
    cd "$(dirname "$0")/../src/data-generator"
    
    # Check virtual environment
    if [ ! -d "venv" ]; then
        print_error "Virtual environment not found. Run ./scripts/setup.sh first."
        exit 1
    fi
    
    source venv/bin/activate
    
    # Test basic functionality
    print_status "Testing data generation..."
    python app.py --test
    
    print_success "Data generator test passed"
    cd - >/dev/null
}

# Function to test API Gateway
test_api_gateway() {
    print_status "Testing API Gateway endpoint..."
    
    # Create test payload
    local test_payload='{
        "sensor_id": "test_sensor_001",
        "temperature": 23.5,
        "humidity": 45.2,
        "location": "Test_Location",
        "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
    }'
    
    # Send test request
    local response_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "$test_payload" \
        "$API_ENDPOINT/ingest")
    
    if [ "$response_code" = "200" ]; then
        print_success "API Gateway test passed (HTTP $response_code)"
    else
        print_error "API Gateway test failed (HTTP $response_code)"
        return 1
    fi
}

# Function to test Kinesis stream
test_kinesis_stream() {
    print_status "Testing Kinesis stream..."
    
    # Check stream status
    local stream_status=$(aws kinesis describe-stream --stream-name "$KINESIS_STREAM" --query 'StreamDescription.StreamStatus' --output text 2>/dev/null || echo "ERROR")
    
    if [ "$stream_status" = "ACTIVE" ]; then
        print_success "Kinesis stream is active"
    else
        print_error "Kinesis stream is not active (Status: $stream_status)"
        return 1
    fi
    
    # Test putting a record directly
    local test_data='{"sensor_id": "test_kinesis", "temperature": 25.0, "humidity": 50.0, "location": "test"}'
    local result=$(aws kinesis put-record \
        --stream-name "$KINESIS_STREAM" \
        --data "$test_data" \
        --partition-key "test_kinesis" \
        --query 'SequenceNumber' \
        --output text 2>/dev/null || echo "ERROR")
    
    if [ "$result" != "ERROR" ]; then
        print_success "Kinesis put-record test passed"
    else
        print_error "Kinesis put-record test failed"
        return 1
    fi
}

# Function to test S3 bucket
test_s3_bucket() {
    print_status "Testing S3 bucket..."
    
    # Check if bucket exists and is accessible
    if aws s3 ls "s3://$S3_BUCKET" >/dev/null 2>&1; then
        print_success "S3 bucket is accessible"
    else
        print_error "S3 bucket is not accessible"
        return 1
    fi
    
    # Test writing a test file
    local test_content="CloudPulse test file - $(date)"
    if echo "$test_content" | aws s3 cp - "s3://$S3_BUCKET/test/test-$(date +%s).txt" >/dev/null 2>&1; then
        print_success "S3 write test passed"
    else
        print_error "S3 write test failed"
        return 1
    fi
}

# Function to test Lambda functions
test_lambda_functions() {
    print_status "Testing Lambda functions..."
    
    cd "$(dirname "$0")/../terraform"
    
    # Get Lambda function names
    local data_processor=$(terraform output -json lambda_function_names 2>/dev/null | jq -r '.data_processor' || echo "")
    local data_transformer=$(terraform output -json lambda_function_names 2>/dev/null | jq -r '.data_transformer' || echo "")
    
    cd - >/dev/null
    
    if [ -z "$data_processor" ] || [ -z "$data_transformer" ]; then
        print_warning "Could not get Lambda function names, skipping test"
        return 0
    fi
    
    # Test data processor function
    local processor_status=$(aws lambda get-function --function-name "$data_processor" --query 'Configuration.State' --output text 2>/dev/null || echo "ERROR")
    if [ "$processor_status" = "Active" ]; then
        print_success "Data processor Lambda is active"
    else
        print_error "Data processor Lambda is not active (Status: $processor_status)"
        return 1
    fi
    
    # Test data transformer function
    local transformer_status=$(aws lambda get-function --function-name "$data_transformer" --query 'Configuration.State' --output text 2>/dev/null || echo "ERROR")
    if [ "$transformer_status" = "Active" ]; then
        print_success "Data transformer Lambda is active"
    else
        print_error "Data transformer Lambda is not active (Status: $transformer_status)"
        return 1
    fi
}

# Function to run end-to-end test
run_e2e_test() {
    print_status "Running end-to-end test..."
    
    cd "$(dirname "$0")/../src/data-generator"
    source venv/bin/activate
    
    # Send multiple test records
    print_status "Sending test data through the pipeline..."
    python app.py --api-endpoint "$API_ENDPOINT/ingest" --rate 2 --duration 10 --batch-size 5
    
    print_success "End-to-end test data sent"
    
    # Wait a bit for processing
    print_status "Waiting 30 seconds for data processing..."
    sleep 30
    
    # Check if data appears in S3
    print_status "Checking for processed data in S3..."
    local data_count=$(aws s3 ls "s3://$S3_BUCKET/sensor-data/" --recursive | wc -l 2>/dev/null || echo "0")
    
    if [ "$data_count" -gt 0 ]; then
        print_success "Found $data_count processed files in S3"
    else
        print_warning "No processed files found in S3 yet (may take more time)"
    fi
    
    cd - >/dev/null
}

# Function to show test results summary
show_test_summary() {
    echo ""
    print_success "🎯 CloudPulse Test Summary"
    echo "=================================="
    echo ""
    
    if [ ${#FAILED_TESTS[@]} -eq 0 ]; then
        print_success "All tests passed! ✅"
        echo ""
        echo "🔍 Next Steps:"
        echo "  1. Monitor the CloudWatch dashboard"
        echo "  2. Check S3 for processed data"
        echo "  3. Run load tests with higher data rates"
        echo "  4. Set up alerts and monitoring"
    else
        print_error "Some tests failed! ❌"
        echo ""
        echo "Failed tests:"
        for test in "${FAILED_TESTS[@]}"; do
            echo "  - $test"
        done
        echo ""
        echo "🔧 Troubleshooting:"
        echo "  1. Check AWS CloudWatch logs"
        echo "  2. Verify IAM permissions"
        echo "  3. Check terraform outputs"
        echo "  4. Review infrastructure status"
    fi
    echo ""
}

# Function to run all tests
run_all_tests() {
    local start_time=$(date +%s)
    FAILED_TESTS=()
    
    print_status "🚀 Starting CloudPulse End-to-End Tests"
    echo "==========================================="
    echo ""
    
    # Test infrastructure components
    get_infrastructure_info || FAILED_TESTS+=("Infrastructure Info")
    test_data_generator || FAILED_TESTS+=("Data Generator")
    test_api_gateway || FAILED_TESTS+=("API Gateway")
    test_kinesis_stream || FAILED_TESTS+=("Kinesis Stream")
    test_s3_bucket || FAILED_TESTS+=("S3 Bucket")
    test_lambda_functions || FAILED_TESTS+=("Lambda Functions")
    
    # Run end-to-end test
    run_e2e_test || FAILED_TESTS+=("End-to-End Test")
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo ""
    print_status "Tests completed in ${duration} seconds"
    
    show_test_summary
    
    # Exit with error code if any tests failed
    [ ${#FAILED_TESTS[@]} -eq 0 ]
}

# Function to show help
show_help() {
    echo "CloudPulse Test Script"
    echo ""
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  --unit              Run unit tests only"
    echo "  --integration       Run integration tests only"
    echo "  --e2e               Run end-to-end test only"
    echo ""
    echo "Default: Run all tests"
}

# Parse command line arguments
UNIT_ONLY=false
INTEGRATION_ONLY=false
E2E_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --unit)
            UNIT_ONLY=true
            shift
            ;;
        --integration)
            INTEGRATION_ONLY=true
            shift
            ;;
        --e2e)
            E2E_ONLY=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main execution
main() {
    # Check dependencies
    if ! command_exists aws; then
        print_error "AWS CLI is required but not installed"
        exit 1
    fi
    
    if ! command_exists curl; then
        print_error "curl is required but not installed"
        exit 1
    fi
    
    if [ "$UNIT_ONLY" = true ]; then
        test_data_generator
    elif [ "$INTEGRATION_ONLY" = true ]; then
        get_infrastructure_info
        test_api_gateway
        test_kinesis_stream
        test_s3_bucket
        test_lambda_functions
    elif [ "$E2E_ONLY" = true ]; then
        get_infrastructure_info
        run_e2e_test
    else
        run_all_tests
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
