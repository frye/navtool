#!/bin/bash

# Test runner script for NavTool dual testing strategy
# This script helps run different types of tests based on the scenario

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

# Function to show usage
show_help() {
    echo "NavTool Test Runner"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  unit              Run fast mock-based unit tests only"
    echo "  integration       Run real network integration tests"
    echo "  all               Run all tests (unit + integration)"
    echo "  ci                Run CI-appropriate tests (unit tests only)"
    echo "  dev               Run development tests (unit tests with coverage)"
    echo "  validate          Run pre-commit validation (all unit tests)"
    echo "  help              Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  SKIP_INTEGRATION_TESTS=true   Skip network-dependent tests"
    echo "  CI=true                       Automatically detected in CI environments"
    echo ""
    echo "Examples:"
    echo "  $0 unit                      # Fast development feedback"
    echo "  $0 integration               # Test against real NOAA APIs"
    echo "  $0 ci                        # Run in CI environment"
    echo "  SKIP_INTEGRATION_TESTS=true $0 all  # Run all but skip integration"
}

# Function to run unit tests
run_unit_tests() {
    print_status "Running mock-based unit tests..."
    flutter test --tags=unit --reporter=expanded
    if [ $? -eq 0 ]; then
        print_success "Unit tests passed!"
    else
        print_error "Unit tests failed!"
        exit 1
    fi
}

# Function to run integration tests
run_integration_tests() {
    print_status "Running real network integration tests..."
    print_warning "Note: These tests require network connectivity to NOAA APIs"
    
    if [ "$SKIP_INTEGRATION_TESTS" = "true" ] || [ "$CI" = "true" ]; then
        print_warning "Integration tests skipped (SKIP_INTEGRATION_TESTS=true or CI=true)"
        return 0
    fi
    
    flutter test integration_test/ --reporter=expanded
    if [ $? -eq 0 ]; then
        print_success "Integration tests passed!"
    else
        print_error "Integration tests failed!"
        exit 1
    fi
}

# Function to run all standard tests (including unit tests)
run_standard_tests() {
    print_status "Running all standard tests..."
    flutter test test/ --reporter=expanded
    if [ $? -eq 0 ]; then
        print_success "Standard tests passed!"
    else
        print_error "Standard tests failed!"
        exit 1
    fi
}

# Function to run development tests with coverage
run_dev_tests() {
    print_status "Running development tests with coverage..."
    flutter test --tags=unit --coverage --reporter=expanded
    if [ $? -eq 0 ]; then
        print_success "Development tests passed!"
        if [ -f "coverage/lcov.info" ]; then
            print_status "Coverage report generated at coverage/lcov.info"
        fi
    else
        print_error "Development tests failed!"
        exit 1
    fi
}

# Main script logic
case "${1:-help}" in
    "unit")
        run_unit_tests
        ;;
    "integration")
        run_integration_tests
        ;;
    "all")
        run_standard_tests
        run_integration_tests
        ;;
    "ci")
        print_status "Running CI tests (unit tests only)..."
        export SKIP_INTEGRATION_TESTS=true
        run_standard_tests
        ;;
    "dev")
        run_dev_tests
        ;;
    "validate")
        print_status "Running pre-commit validation..."
        run_standard_tests
        print_success "Pre-commit validation passed!"
        ;;
    "help")
        show_help
        ;;
    *)
        print_error "Unknown command: $1"
        echo ""
        show_help
        exit 1
        ;;
esac

print_success "Test execution completed successfully!"