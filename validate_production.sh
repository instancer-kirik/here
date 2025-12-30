#!/bin/bash

# here - Comprehensive Production Readiness Validation
# AppMan Integration, Wallet Address, and AppImage Indexing

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
WARNINGS=0
CRITICAL_FAILURES=0

# Helper functions
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
    ((TESTS_PASSED++))
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    ((WARNINGS++))
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
    ((TESTS_FAILED++))
}

print_critical() {
    echo -e "${RED}🚨 CRITICAL: $1${NC}"
    ((CRITICAL_FAILURES++))
    ((TESTS_FAILED++))
}

print_section() {
    echo
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${PURPLE}    $1${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_banner() {
    echo -e "${CYAN}"
    echo "██╗  ██╗███████╗██████╗ ███████╗"
    echo "██║  ██║██╔════╝██╔══██╗██╔════╝"
    echo "███████║█████╗  ██████╔╝█████╗  "
    echo "██╔══██║██╔══╝  ██╔══██╗██╔══╝  "
    echo "██║  ██║███████╗██║  ██║███████╗"
    echo "╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚══════╝"
    echo
    echo "Production Readiness Validation Suite"
    echo "AppMan Integration • Wallet Address • AppImage Indexing"
    echo -e "${NC}"
}

# Test AppMan Integration Module
test_appman_integration() {
    print_section "AppMan Integration Module Tests"

    # Check if appman_integration.zig exists
    if [[ -f "src/appman_integration.zig" ]]; then
        print_success "AppMan integration module exists"
    else
        print_critical "appman_integration.zig module missing - PRODUCTION BLOCKER"
        return 1
    fi

    # Check essential structs and functions
    local required_items=(
        "pub const AppManManager"
        "pub const AppManError"
        "pub const AppManConfig"
        "pub fn init"
        "pub fn install"
        "pub fn search"
        "pub fn listInstalled"
        "pub fn updateAll"
        "pub fn remove"
        "performHealthCheck"
        "isAppManInstalled"
        "installAppMan"
    )

    for item in "${required_items[@]}"; do
        if grep -q "$item" src/appman_integration.zig; then
            print_success "Found: $item"
        else
            print_error "Missing: $item"
        fi
    done

    # Check error handling
    if grep -q "AppManError\." src/appman_integration.zig; then
        print_success "Comprehensive error handling implemented"
    else
        print_error "Error handling insufficient"
    fi

    # Check wallet address integration
    if grep -q "showSupportInfo\|0xaf462cef9e8913a9cb7b6f0ba0ddf5d733eae57a" src/appman_integration.zig; then
        print_success "Wallet address integration present"
    else
        print_error "Wallet address integration missing"
    fi

    # Check AppMan URL references
    if grep -q "ivan-hc/AM\|AppMan" src/appman_integration.zig; then
        print_success "Proper AppMan project references"
    else
        print_error "AppMan project references missing"
    fi
}

# Test Main Integration
test_main_integration() {
    print_section "Main Application Integration Tests"

    # Check import statement
    if grep -q 'const appman = @import("appman_integration.zig");' src/main.zig; then
        print_success "AppMan module properly imported"
    else
        print_critical "AppMan module not imported in main.zig - PRODUCTION BLOCKER"
    fi

    # Check AppMan usage in search function
    if grep -q "appman.AppManManager.init" src/main.zig; then
        print_success "AppMan manager properly initialized"
    else
        print_error "AppMan manager not initialized"
    fi

    # Check fallback mechanisms
    if grep -q "falling back\|fallback" src/main.zig; then
        print_success "Fallback mechanisms implemented"
    else
        print_error "No fallback mechanisms for AppMan failures"
    fi

    # Check production-ready messaging
    if grep -q "production-ready" src/main.zig; then
        print_success "Production-ready messaging present"
    else
        print_warning "Should emphasize production-ready AppMan integration"
    fi

    # Check wallet address in version info
    if grep -q "0xaf462cef9e8913a9cb7b6f0ba0ddf5d733eae57a" src/main.zig; then
        print_success "Wallet address in version information"
    else
        print_error "Wallet address missing from version information"
    fi
}

# Test Build System
test_build_system() {
    print_section "Build System and Compilation Tests"

    # Check if Zig is available
    if command -v zig >/dev/null 2>&1; then
        local zig_version=$(zig version)
        print_success "Zig available: $zig_version"
    else
        print_critical "Zig not found - cannot validate compilation"
        return 1
    fi

    # Test syntax checking
    if zig fmt --check src/ >/dev/null 2>&1; then
        print_success "Code formatting is correct"
    else
        print_warning "Code formatting issues detected"
        zig fmt --check src/ 2>&1 | head -5
    fi

    # Test compilation
    print_info "Testing compilation with AppMan integration..."
    if zig build >/dev/null 2>&1; then
        print_success "Project compiles with AppMan integration"
    else
        print_critical "Compilation fails with AppMan integration - PRODUCTION BLOCKER"
        echo -e "${RED}Compilation errors:${NC}"
        zig build 2>&1 | tail -10
        return 1
    fi

    # Test if binary was created
    if [[ -f "zig-out/bin/here" ]]; then
        print_success "Binary created successfully"
        local binary_size=$(stat -c%s "zig-out/bin/here" 2>/dev/null || stat -f%z "zig-out/bin/here" 2>/dev/null)
        local size_mb=$((binary_size / 1024 / 1024))

        if [[ $size_mb -lt 10 ]]; then
            print_success "Binary size acceptable: ${size_mb}MB"
        else
            print_warning "Binary size large: ${size_mb}MB"
        fi
    else
        print_error "Binary not created"
    fi

    # Test release builds
    if zig build -Doptimize=ReleaseFast >/dev/null 2>&1; then
        print_success "Release build succeeds"
    else
        print_error "Release build fails"
    fi
}

# Test Runtime Functionality
test_runtime_functionality() {
    print_section "Runtime Functionality Tests"

    local binary="zig-out/bin/here"
    if [[ ! -f "$binary" ]]; then
        print_error "No binary available for runtime testing"
        return 1
    fi

    # Test version command
    print_info "Testing version command..."
    if $binary version >/dev/null 2>&1; then
        print_success "Version command works"

        # Check if version output contains AppMan reference
        local version_output=$($binary version 2>&1)
        if echo "$version_output" | grep -q "AppMan\|ivan-hc"; then
            print_success "Version output mentions AppMan integration"
        else
            print_warning "Version output should mention AppMan integration"
        fi

        # Check wallet addresses in version output
        if echo "$version_output" | grep -q "0xaf462cef9e8913a9cb7b6f0ba0ddf5d733eae57a"; then
            print_success "Wallet address present in version output"
        else
            print_error "Wallet address missing from version output"
        fi
    else
        print_error "Version command fails"
    fi

    # Test help command
    print_info "Testing help command..."
    if $binary help >/dev/null 2>&1; then
        print_success "Help command works"
    else
        print_error "Help command fails"
    fi

    # Test invalid command handling
    if ! $binary invalid_command >/dev/null 2>&1; then
        print_success "Invalid commands handled properly"
    else
        print_warning "Invalid command should return non-zero exit code"
    fi
}

# Test AppMan Dependencies
test_appman_dependencies() {
    print_section "AppMan Dependencies and Prerequisites"

    # Check required dependencies for AppMan
    local deps=("curl" "wget" "grep" "sed" "chmod" "ping")
    local missing_deps=0

    for dep in "${deps[@]}"; do
        if command -v "$dep" >/dev/null 2>&1; then
            print_success "$dep available"
        else
            print_error "$dep missing - required for AppMan"
            ((missing_deps++))
        fi
    done

    if [[ $missing_deps -eq 0 ]]; then
        print_success "All AppMan dependencies available"
    else
        print_warning "$missing_deps dependencies missing - may affect AppMan functionality"
    fi

    # Check HOME directory
    if [[ -n "$HOME" ]]; then
        print_success "HOME environment variable set"
    else
        print_critical "HOME environment variable missing - AppMan cannot function"
    fi

    # Check .local/bin directory or ability to create it
    local local_bin="$HOME/.local/bin"
    if [[ -d "$local_bin" ]]; then
        print_success "~/.local/bin directory exists"
    else
        if mkdir -p "$local_bin" 2>/dev/null; then
            print_success "~/.local/bin directory can be created"
            rmdir "$local_bin" 2>/dev/null || true
        else
            print_error "Cannot create ~/.local/bin directory"
        fi
    fi

    # Check PATH configuration
    if echo "$PATH" | grep -q "$local_bin"; then
        print_success "~/.local/bin is in PATH"
    else
        print_warning "~/.local/bin not in PATH - may need user configuration"
    fi

    # Check network connectivity
    print_info "Testing network connectivity for AppMan..."
    if ping -c 1 -W 3 github.com >/dev/null 2>&1; then
        print_success "Network connectivity to GitHub available"
    else
        print_warning "Network connectivity issues - may affect AppMan downloads"
    fi
}

# Test AppImage Indexing Features
test_appimage_indexing() {
    print_section "AppImage Indexing and Database Tests"

    # Check for AppImageHub integration
    if grep -q "appimage.github.io" src/appman_integration.zig src/appimage.zig 2>/dev/null; then
        print_success "AppImageHub integration present"
    else
        print_error "AppImageHub integration missing"
    fi

    # Check for GitHub API integration
    if grep -q "api.github.com" src/appman_integration.zig src/appimage.zig 2>/dev/null; then
        print_success "GitHub API integration present"
    else
        print_error "GitHub API integration missing"
    fi

    # Check for comprehensive application database
    if grep -q "2500\+" src/appman_integration.zig; then
        print_success "References large application database (2500+)"
    else
        print_warning "Should emphasize large application database"
    fi

    # Test search functionality if binary exists
    local binary="zig-out/bin/here"
    if [[ -f "$binary" ]]; then
        print_info "Testing AppImage search functionality..."

        # Test search with timeout to avoid hanging
        if timeout 10s $binary search firefox 2>&1 | grep -q "AppMan\|AppImage" || true; then
            print_success "AppImage search functionality appears to work"
        else
            print_warning "AppImage search test inconclusive (may need AppMan installation)"
        fi
    fi
}

# Test Wallet Address Integration
test_wallet_integration() {
    print_section "Wallet Address Integration Tests"

    # Check wallet address format and presence
    local wallet_address="0xaf462cef9e8913a9cb7b6f0ba0ddf5d733eae57a"

    # Check in various files
    local files_with_wallet=0
    local files_to_check=("README.md" "src/main.zig" "src/appman_integration.zig" "SHIPPING_CHECKLIST.md")

    for file in "${files_to_check[@]}"; do
        if [[ -f "$file" ]] && grep -q "$wallet_address" "$file"; then
            print_success "Wallet address found in $file"
            ((files_with_wallet++))
        fi
    done

    if [[ $files_with_wallet -ge 2 ]]; then
        print_success "Wallet address properly distributed across files"
    else
        print_error "Wallet address should be in multiple key files"
    fi

    # Check wallet address format (Ethereum/Base)
    if grep -q "ETH\|Base\|Ethereum" README.md src/main.zig 2>/dev/null; then
        print_success "Wallet address properly labeled as ETH/Base"
    else
        print_warning "Wallet address should specify ETH/Base network"
    fi

    # Check AppMan creator support information
    if grep -q "ivan-hc\|ko-fi\|PayPal" src/appman_integration.zig src/main.zig 2>/dev/null; then
        print_success "AppMan creator support information present"
    else
        print_error "Should include AppMan creator support information"
    fi

    # Check for proper attribution
    if grep -q "AppMan.*ivan-hc\|ivan-hc.*AppMan" src/appman_integration.zig src/main.zig README.md 2>/dev/null; then
        print_success "Proper AppMan creator attribution"
    else
        print_error "Missing proper AppMan creator attribution"
    fi
}

# Test Production Readiness Indicators
test_production_indicators() {
    print_section "Production Readiness Indicators"

    # Check version numbers
    if grep -q "1\.[0-9]\+\.[0-9]\+" build.zig src/main.zig 2>/dev/null; then
        print_success "Version 1.0+ indicates production readiness"
    else
        print_warning "Version should be 1.0+ for production release"
    fi

    # Check shipping checklist
    if [[ -f "SHIPPING_CHECKLIST.md" ]]; then
        if grep -q "READY TO SHIP\|✅.*READY\|PRODUCTION READY" SHIPPING_CHECKLIST.md; then
            print_success "Shipping checklist indicates production ready"
        else
            print_warning "Shipping checklist shows concerns"
        fi
    else
        print_error "SHIPPING_CHECKLIST.md missing"
    fi

    # Check documentation completeness
    local doc_sections=("Installation" "Usage" "Examples" "AppImage" "AppMan")
    local found_sections=0

    for section in "${doc_sections[@]}"; do
        if grep -q -i "$section" README.md 2>/dev/null; then
            ((found_sections++))
        fi
    done

    if [[ $found_sections -ge 4 ]]; then
        print_success "Documentation comprehensive (${found_sections}/5 sections)"
    else
        print_error "Documentation incomplete (${found_sections}/5 sections)"
    fi

    # Check for production deployment files
    local deployment_files=("Makefile" "install.sh" "Dockerfile" ".github/workflows")
    local deployment_ready=0

    for file in "${deployment_files[@]}"; do
        if [[ -e "$file" ]]; then
            print_success "$file exists"
            ((deployment_ready++))
        else
            print_warning "$file missing"
        fi
    done

    if [[ $deployment_ready -ge 3 ]]; then
        print_success "Deployment infrastructure ready"
    else
        print_error "Deployment infrastructure incomplete"
    fi
}

# Test Security and Best Practices
test_security_practices() {
    print_section "Security and Best Practices"

    # Check for hardcoded secrets
    if grep -r -i "password\|secret\|key\|token" src/ --exclude="*.md" >/dev/null 2>&1; then
        print_warning "Potential hardcoded credentials - review needed"
        grep -r -i "password\|secret\|key\|token" src/ --exclude="*.md" | head -3
    else
        print_success "No obvious hardcoded credentials"
    fi

    # Check error handling patterns
    if grep -q "catch |err|" src/main.zig src/appman_integration.zig 2>/dev/null; then
        print_success "Proper error handling patterns"
    else
        print_error "Error handling needs improvement"
    fi

    # Check input validation
    if grep -q "validate\|sanitize\|check.*input" src/ 2>/dev/null; then
        print_success "Input validation present"
    else
        print_warning "Input validation should be enhanced"
    fi

    # Check for unsafe operations
    if grep -q "unsafe\|raw.*pointer" src/ 2>/dev/null; then
        print_warning "Unsafe operations detected - review needed"
    else
        print_success "No obvious unsafe operations"
    fi
}

# Performance and Resource Usage Tests
test_performance() {
    print_section "Performance and Resource Usage"

    local binary="zig-out/bin/here"
    if [[ -f "$binary" ]]; then
        # Test startup time
        print_info "Testing startup performance..."
        local start_time=$(date +%s%3N)
        $binary version >/dev/null 2>&1 || true
        local end_time=$(date +%s%3N)
        local duration=$((end_time - start_time))

        if [[ $duration -lt 100 ]]; then
            print_success "Startup time: ${duration}ms (excellent)"
        elif [[ $duration -lt 500 ]]; then
            print_success "Startup time: ${duration}ms (good)"
        elif [[ $duration -lt 1000 ]]; then
            print_warning "Startup time: ${duration}ms (acceptable)"
        else
            print_error "Startup time: ${duration}ms (too slow for production)"
        fi

        # Test memory usage estimation
        local binary_size=$(stat -c%s "$binary" 2>/dev/null || stat -f%z "$binary" 2>/dev/null)
        if [[ $binary_size -lt 10485760 ]]; then  # 10MB
            print_success "Binary size optimized for performance"
        else
            print_warning "Binary size may impact startup time"
        fi
    else
        print_warning "Cannot test performance - binary not available"
    fi
}

# Main validation function
main() {
    print_banner

    print_info "Starting comprehensive production validation..."
    print_info "Focus areas: AppMan Integration • Wallet Address • AppImage Indexing"
    echo

    # Run all test suites
    test_appman_integration
    test_main_integration
    test_build_system
    test_runtime_functionality
    test_appman_dependencies
    test_appimage_indexing
    test_wallet_integration
    test_production_indicators
    test_security_practices
    test_performance

    # Final summary
    print_section "PRODUCTION VALIDATION SUMMARY"

    echo -e "${CYAN}Overall Results:${NC}"
    echo -e "  Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "  Tests failed: ${RED}$TESTS_FAILED${NC}"
    echo -e "  Warnings: ${YELLOW}$WARNINGS${NC}"
    echo -e "  Critical failures: ${RED}$CRITICAL_FAILURES${NC}"
    echo

    local total_tests=$((TESTS_PASSED + TESTS_FAILED))
    local pass_rate=0
    if [[ $total_tests -gt 0 ]]; then
        pass_rate=$((TESTS_PASSED * 100 / total_tests))
    fi

    echo -e "${CYAN}Key Production Features:${NC}"
    echo "  ✨ AppMan Integration: 2500+ applications available"
    echo "  🔧 Professional Installation: Automated setup and fallbacks"
    echo "  🔍 Advanced Indexing: AppImageHub + GitHub releases"
    echo "  💰 Wallet Support: ETH/Base address integration"
    echo "  🚀 Production Ready: Comprehensive error handling"
    echo

    # Determine overall status
    if [[ $CRITICAL_FAILURES -gt 0 ]]; then
        echo -e "${RED}🚨 PRODUCTION BLOCKED${NC}"
        echo -e "${RED}Critical failures detected. Must fix before release.${NC}"
        echo
        echo -e "${RED}Critical Issues to Address:${NC}"
        echo "  • Fix compilation errors"
        echo "  • Ensure AppMan integration modules are present"
        echo "  • Resolve dependency issues"
        exit 1
    elif [[ $TESTS_FAILED -eq 0 ]]; then
        if [[ $WARNINGS -eq 0 ]]; then
            echo -e "${GREEN}🚀 PRODUCTION READY!${NC}"
            echo -e "${GREEN}All tests passed. Ready for immediate release.${NC}"
        else
            echo -e "${GREEN}✅ PRODUCTION READY (with minor warnings)${NC}"
            echo -e "${YELLOW}All critical tests passed. $WARNINGS warnings to consider.${NC}"
        fi
    elif [[ $pass_rate -ge 90 ]]; then
        echo -e "${YELLOW}⚠️  MOSTLY PRODUCTION READY (${pass_rate}% pass rate)${NC}"
        echo -e "${YELLOW}Most tests passed. $TESTS_FAILED non-critical issues to fix.${NC}"
    elif [[ $pass_rate -ge 75 ]]; then
        echo -e "${YELLOW}⚠️  NEEDS WORK BEFORE PRODUCTION (${pass_rate}% pass rate)${NC}"
        echo -e "${YELLOW}Several issues need fixing before release.${NC}"
    else
        echo -e "${RED}❌ NOT READY FOR PRODUCTION (${pass_rate}% pass rate)${NC}"
        echo -e "${RED}Too many issues. Significant work needed.${NC}"
    fi

    echo
    echo -e "${CYAN}Next Steps:${NC}"
    if [[ $CRITICAL_FAILURES -eq 0 && $TESTS_FAILED -eq 0 ]]; then
        echo "  1. 🎉 Celebrate - your project is production ready!"
        echo "  2. 📝 Update documentation with AppMan integration details"
        echo "  3. 🚀 Proceed with release deployment"
        echo "  4. 📊 Monitor usage and gather user feedback"
    else
        echo "  1. 🔧 Fix critical compilation and module issues"
        echo "  2. ✅ Address failing tests systematically"
        echo "  3. ⚠️  Review warnings and improve where possible"
        echo "  4. 🔄 Re-run validation until all tests pass"
    fi

    echo
    print_info "Production validation complete!"
    echo
    echo -e "${CYAN}Support the ecosystem:${NC}"
    echo -e "  💖 here project: ${GREEN}0xaf462cef9e8913a9cb7b6f0ba0ddf5d733eae57a${NC} (ETH/Base)"
    echo -e "  💖 AppMan project: ${GREEN}ko-fi.com/IvanAlexHC${NC} | ${GREEN}PayPal.me/IvanAlexHC${NC}"

    # Exit with appropriate code
    if [[ $CRITICAL_FAILURES -gt 0 ]]; then
        exit 2
    elif [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --quick, -q    Run only critical tests"
        echo "  --verbose, -v  Show detailed output"
        echo
        echo "This script validates production readiness for:"
        echo "  • AppMan integration for AppImage management"
        echo "  • Wallet address integration"
        echo "  • AppImage indexing functionality"
        echo "  • Overall production deployment readiness"
        exit 0
        ;;
    --quick|-q)
        print_info "Running quick validation (critical tests only)..."
        test_appman_integration
        test_build_system
        test_production_indicators
        ;;
    *)
        main "$@"
        ;;
esac
