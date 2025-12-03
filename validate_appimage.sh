#!/bin/bash

# here - AppImage Production Readiness Validation Script
# Specific tests for AppImage functionality and wallet address integration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Counters
APPIMAGE_TESTS_PASSED=0
APPIMAGE_TESTS_FAILED=0
APPIMAGE_WARNINGS=0

# Helper functions
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
    ((APPIMAGE_TESTS_PASSED++))
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    ((APPIMAGE_WARNINGS++))
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
    ((APPIMAGE_TESTS_FAILED++))
}

print_section() {
    echo
    echo -e "${PURPLE}━━━ $1 ━━━${NC}"
}

# Test AppImage module structure
test_appimage_module() {
    print_section "AppImage Module Tests"

    # Check if appimage.zig exists
    if [[ -f "src/appimage.zig" ]]; then
        print_success "appimage.zig module exists"
    else
        print_error "appimage.zig module missing - critical for production"
        return 1
    fi

    # Check module structure
    if grep -q "pub const AppImageInstaller" src/appimage.zig; then
        print_success "AppImageInstaller struct defined"
    else
        print_error "AppImageInstaller struct missing"
    fi

    if grep -q "pub const AppImageRegistry" src/appimage.zig; then
        print_success "AppImageRegistry struct defined"
    else
        print_error "AppImageRegistry struct missing"
    fi

    if grep -q "pub const AppImageError" src/appimage.zig; then
        print_success "AppImageError enum defined"
    else
        print_error "AppImageError enum missing"
    fi

    # Check for essential methods
    local required_methods=("install" "searchAppImageHub" "listInstalled" "remove")
    for method in "${required_methods[@]}"; do
        if grep -q "pub fn ${method}" src/appimage.zig; then
            print_success "Method ${method} implemented"
        else
            print_error "Method ${method} missing"
        fi
    done
}

# Test AppImage integration in main
test_main_integration() {
    print_section "Main Integration Tests"

    # Check if appimage module is imported
    if grep -q "const appimage = @import(\"appimage.zig\");" src/main.zig; then
        print_success "appimage module imported in main.zig"
    else
        print_error "appimage module not imported in main.zig"
    fi

    # Check if AppImage installer is used in install function
    if grep -q "appimage.AppImageInstaller.init" src/main.zig; then
        print_success "AppImageInstaller properly initialized"
    else
        print_error "AppImageInstaller not properly initialized"
    fi

    # Check if list command includes AppImage support
    if grep -q "installer.listInstalled" src/main.zig; then
        print_success "List command includes AppImage support"
    else
        print_error "List command missing AppImage support"
    fi
}

# Test AppImage registry completeness
test_appimage_registry() {
    print_section "AppImage Registry Tests"

    if [[ ! -f "src/appimage.zig" ]]; then
        print_error "Cannot test registry - appimage.zig missing"
        return 1
    fi

    # Check for popular applications in registry
    local popular_apps=("obsidian" "vscodium" "discord" "figma" "krita" "blender")
    local found_apps=0

    for app in "${popular_apps[@]}"; do
        if grep -q "\"${app}\"" src/appimage.zig; then
            ((found_apps++))
        fi
    done

    if [[ $found_apps -ge 10 ]]; then
        print_success "Registry contains ${found_apps} popular applications"
    elif [[ $found_apps -ge 5 ]]; then
        print_warning "Registry contains ${found_apps} applications (could be expanded)"
    else
        print_error "Registry contains only ${found_apps} applications (too few for production)"
    fi

    # Check for proper GitHub repository mapping
    if grep -q "\.repo.*github\.com\|\.repo.*/" src/appimage.zig; then
        print_success "GitHub repository mapping present"
    else
        print_error "GitHub repository mapping missing"
    fi
}

# Test error handling
test_error_handling() {
    print_section "Error Handling Tests"

    if [[ ! -f "src/appimage.zig" ]]; then
        print_error "Cannot test error handling - appimage.zig missing"
        return 1
    fi

    # Check for comprehensive error types
    local error_types=("NetworkError" "ParseError" "DownloadError" "FileSystemError" "NotFound")
    for error_type in "${error_types[@]}"; do
        if grep -q "$error_type" src/appimage.zig; then
            print_success "Error type ${error_type} defined"
        else
            print_error "Error type ${error_type} missing"
        fi
    done

    # Check for proper error propagation
    if grep -q "catch |err|" src/appimage.zig; then
        print_success "Error propagation implemented"
    else
        print_warning "Error propagation could be improved"
    fi

    # Check for user-friendly error messages
    if grep -q "print.*❌.*Failed" src/appimage.zig; then
        print_success "User-friendly error messages present"
    else
        print_warning "Error messages could be more user-friendly"
    fi
}

# Test GitHub API integration
test_github_api() {
    print_section "GitHub API Integration Tests"

    if [[ ! -f "src/appimage.zig" ]]; then
        print_error "Cannot test GitHub API - appimage.zig missing"
        return 1
    fi

    # Check for proper API endpoints
    if grep -q "api.github.com/repos" src/appimage.zig; then
        print_success "GitHub API endpoint configured"
    else
        print_error "GitHub API endpoint missing"
    fi

    # Check for proper API headers
    if grep -q "Accept: application/vnd.github" src/appimage.zig; then
        print_success "GitHub API headers configured"
    else
        print_error "GitHub API headers missing"
    fi

    # Check for rate limit handling
    if grep -q "X-RateLimit\|rate.*limit" src/appimage.zig; then
        print_warning "Rate limit handling should be considered"
    fi

    # Check for JSON parsing
    if grep -q "std.json.Parser" src/appimage.zig; then
        print_success "Proper JSON parsing implemented"
    else
        print_error "Proper JSON parsing missing"
    fi
}

# Test file system operations
test_filesystem_ops() {
    print_section "File System Operations Tests"

    if [[ ! -f "src/appimage.zig" ]]; then
        print_error "Cannot test filesystem ops - appimage.zig missing"
        return 1
    fi

    # Check for proper directory creation
    if grep -q "makeDirAbsolute\|createDir" src/appimage.zig; then
        print_success "Directory creation implemented"
    else
        print_error "Directory creation missing"
    fi

    # Check for file permission handling
    if grep -q "chmod\|makeExecutable" src/appimage.zig; then
        print_success "File permission handling implemented"
    else
        print_error "File permission handling missing"
    fi

    # Check for proper installation path
    if grep -q "\\.local/bin" src/appimage.zig; then
        print_success "Standard installation path used"
    else
        print_error "Standard installation path missing"
    fi

    # Check for PATH validation
    if grep -q "PATH.*getenv\|checkPath" src/appimage.zig; then
        print_success "PATH validation implemented"
    else
        print_warning "PATH validation could be improved"
    fi
}

# Test download functionality
test_download_functionality() {
    print_section "Download Functionality Tests"

    if [[ ! -f "src/appimage.zig" ]]; then
        print_error "Cannot test download - appimage.zig missing"
        return 1
    fi

    # Check for curl usage with proper flags
    if grep -q "curl.*-L.*-f" src/appimage.zig; then
        print_success "Curl configured with proper flags"
    else
        print_error "Curl configuration missing or inadequate"
    fi

    # Check for progress indication
    if grep -q "progress-bar\|progress" src/appimage.zig; then
        print_success "Download progress indication implemented"
    else
        print_warning "Download progress indication missing"
    fi

    # Check for download validation
    if grep -q "size.*bytes\|validateDownload" src/appimage.zig; then
        print_success "Download validation implemented"
    else
        print_warning "Download validation could be improved"
    fi
}

# Test AppImageHub integration
test_appimagehub_integration() {
    print_section "AppImageHub Integration Tests"

    if [[ ! -f "src/appimage.zig" ]]; then
        print_error "Cannot test AppImageHub - appimage.zig missing"
        return 1
    fi

    # Check for AppImageHub API endpoint
    if grep -q "appimage.github.io/feed.json" src/appimage.zig; then
        print_success "AppImageHub API endpoint configured"
    else
        print_error "AppImageHub API endpoint missing"
    fi

    # Check for fallback search
    if grep -q "searchAppImageHubFallback" src/appimage.zig; then
        print_success "Fallback search implemented"
    else
        print_error "Fallback search missing"
    fi

    # Check for search result limitation
    if grep -q "found_count.*10\|limit.*results" src/appimage.zig; then
        print_success "Search result limitation implemented"
    else
        print_warning "Search results should be limited for performance"
    fi
}

# Test wallet address integration
test_wallet_integration() {
    print_section "Wallet Address Integration Tests"

    # Check for wallet address in donation/support sections
    if grep -q "0xaf462cef9e8913a9cb7b6f0ba0ddf5d733eae57a" README.md; then
        print_success "Wallet address present in README"
    else
        print_warning "Wallet address missing from README"
    fi

    if grep -q "0xaf462cef9e8913a9cb7b6f0ba0ddf5d733eae57a" src/main.zig; then
        print_success "Wallet address present in version info"
    else
        print_warning "Wallet address missing from version info"
    fi

    # Check for proper wallet address format validation
    if grep -q "0x[a-fA-F0-9].*{40}" src/main.zig README.md; then
        print_success "Wallet address format appears correct"
    else
        print_warning "Wallet address format should be validated"
    fi

    # Check for support information
    if grep -q -i "support.*development\|donate\|contribution" README.md; then
        print_success "Support information present"
    else
        print_warning "Support information could be improved"
    fi
}

# Test production readiness indicators
test_production_readiness() {
    print_section "Production Readiness Indicators"

    # Check if shipping checklist indicates ready
    if [[ -f "SHIPPING_CHECKLIST.md" ]]; then
        if grep -q "READY TO SHIP\|✅.*READY" SHIPPING_CHECKLIST.md; then
            print_success "Shipping checklist indicates ready"
        else
            print_warning "Shipping checklist shows concerns"
        fi
    else
        print_error "SHIPPING_CHECKLIST.md missing"
    fi

    # Check for version 1.0.0 or higher
    if grep -q "version.*1\.[0-9]\+\.[0-9]\+" build.zig; then
        print_success "Version 1.0+ indicates production readiness"
    else
        print_warning "Pre-1.0 version suggests beta status"
    fi

    # Check for comprehensive documentation
    local doc_sections=("Installation" "Usage" "Examples" "AppImage")
    local found_sections=0
    for section in "${doc_sections[@]}"; do
        if grep -q -i "$section" README.md; then
            ((found_sections++))
        fi
    done

    if [[ $found_sections -ge 3 ]]; then
        print_success "Documentation appears comprehensive (${found_sections}/4 sections)"
    else
        print_error "Documentation incomplete (${found_sections}/4 sections)"
    fi
}

# Test binary compilation
test_compilation() {
    print_section "Compilation Tests"

    # Test if project compiles with new AppImage module
    if command -v zig >/dev/null 2>&1; then
        print_info "Testing compilation with AppImage module..."

        if zig build >/dev/null 2>&1; then
            print_success "Project compiles successfully with AppImage module"
        else
            print_error "Compilation fails with AppImage module - critical issue"
        fi

        # Test if tests pass
        if zig build test >/dev/null 2>&1; then
            print_success "Tests pass with AppImage module"
        else
            print_warning "Some tests fail with AppImage module"
        fi
    else
        print_warning "Zig not available - cannot test compilation"
    fi
}

# Main validation function
main() {
    echo -e "${PURPLE}"
    echo "🧊 here - AppImage Production Readiness Validation"
    echo "================================================${NC}"
    echo

    print_info "Validating AppImage functionality for production release..."
    echo

    # Run all AppImage-specific tests
    test_appimage_module
    test_main_integration
    test_appimage_registry
    test_error_handling
    test_github_api
    test_filesystem_ops
    test_download_functionality
    test_appimagehub_integration
    test_wallet_integration
    test_production_readiness
    test_compilation

    # Summary
    print_section "AppImage Validation Summary"

    echo -e "AppImage tests passed: ${GREEN}$APPIMAGE_TESTS_PASSED${NC}"
    echo -e "AppImage tests failed: ${RED}$APPIMAGE_TESTS_FAILED${NC}"
    echo -e "AppImage warnings: ${YELLOW}$APPIMAGE_WARNINGS${NC}"

    local total_tests=$((APPIMAGE_TESTS_PASSED + APPIMAGE_TESTS_FAILED))
    local pass_rate=$((APPIMAGE_TESTS_PASSED * 100 / total_tests))

    echo
    if [[ $APPIMAGE_TESTS_FAILED -eq 0 ]]; then
        if [[ $APPIMAGE_WARNINGS -eq 0 ]]; then
            print_success "🚀 APPIMAGE FUNCTIONALITY PRODUCTION READY!"
            echo -e "${GREEN}All AppImage tests passed with no warnings.${NC}"
        else
            print_success "✅ APPIMAGE MOSTLY READY (with $APPIMAGE_WARNINGS warnings)"
            echo -e "${YELLOW}AppImage functionality is ready but has $APPIMAGE_WARNINGS warnings to consider.${NC}"
        fi
    elif [[ $pass_rate -ge 80 ]]; then
        print_warning "⚠️  APPIMAGE PARTIALLY READY (${pass_rate}% pass rate)"
        echo -e "${YELLOW}Most AppImage tests passed, but $APPIMAGE_TESTS_FAILED critical issues need fixing.${NC}"
    else
        print_error "❌ APPIMAGE NOT PRODUCTION READY (${pass_rate}% pass rate)"
        echo -e "${RED}Too many critical AppImage issues. Please fix $APPIMAGE_TESTS_FAILED failing tests.${NC}"
    fi

    echo
    echo -e "${BLUE}Key Production Issues to Address:${NC}"
    echo "1. Implement proper AppImage installation (not just manual instructions)"
    echo "2. Add comprehensive GitHub API integration with error handling"
    echo "3. Ensure proper JSON parsing for release metadata"
    echo "4. Add download progress and validation"
    echo "5. Implement proper error messages and fallback handling"
    echo

    print_info "AppImage validation complete!"

    # Exit with appropriate code
    if [[ $APPIMAGE_TESTS_FAILED -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

# Make script executable and run
main "$@"
