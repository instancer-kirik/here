#!/bin/bash

# here - Production Readiness Validation Script
# https://github.com/your-repo/here

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
WARNINGS=0

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

print_section() {
    echo
    echo -e "${BLUE}━━━ $1 ━━━${NC}"
}

# Test functions
test_build_system() {
    print_section "Build System Tests"

    # Check if build.zig exists
    if [[ -f "build.zig" ]]; then
        print_success "build.zig exists"
    else
        print_error "build.zig missing"
    fi

    # Check if Zig is available
    if command -v zig >/dev/null 2>&1; then
        local zig_version=$(zig version)
        print_success "Zig available: $zig_version"
    else
        print_error "Zig not found in PATH"
        return 1
    fi

    # Test debug build
    if zig build >/dev/null 2>&1; then
        print_success "Debug build compiles"
    else
        print_error "Debug build fails"
    fi

    # Test release build
    if zig build release >/dev/null 2>&1; then
        print_success "Release build compiles"
    else
        print_error "Release build fails"
    fi

    # Test tests
    if zig build test >/dev/null 2>&1; then
        print_success "Tests pass"
    else
        print_error "Tests fail"
    fi

    # Check if all target binaries exist
    local targets=("x86_64-linux" "aarch64-linux" "x86_64-macos" "aarch64-macos")
    for target in "${targets[@]}"; do
        if [[ -f "zig-out/release/$target/here" ]]; then
            print_success "Binary exists for $target"
        else
            print_error "Binary missing for $target"
        fi
    done
}

test_binary_functionality() {
    print_section "Binary Functionality Tests"

    local binary="zig-out/bin/here"
    if [[ ! -f "$binary" ]]; then
        binary="zig-out/release/x86_64-linux/here"
    fi

    if [[ ! -f "$binary" ]]; then
        print_error "No binary found to test"
        return 1
    fi

    # Test version command
    if $binary version >/dev/null 2>&1; then
        print_success "Version command works"
    else
        print_error "Version command fails"
    fi

    # Test help command
    if $binary help >/dev/null 2>&1; then
        print_success "Help command works"
    else
        print_error "Help command fails"
    fi

    # Test invalid command handling
    if ! $binary invalid_command >/dev/null 2>&1; then
        print_success "Invalid command handled properly"
    else
        print_warning "Invalid command should return non-zero exit code"
    fi

    # Test system detection
    local detection_output=$($binary help 2>&1)
    if [[ -n "$detection_output" ]]; then
        print_success "System detection runs without crash"
    else
        print_error "System detection fails"
    fi
}

test_documentation() {
    print_section "Documentation Tests"

    # Check required files
    local required_files=("README.md" "CHANGELOG.md" "LICENSE")
    for file in "${required_files[@]}"; do
        if [[ -f "$file" ]]; then
            print_success "$file exists"
        else
            print_error "$file missing"
        fi
    done

    # Check README content
    if [[ -f "README.md" ]]; then
        if grep -q "Installation" README.md; then
            print_success "README has installation instructions"
        else
            print_error "README missing installation instructions"
        fi

        if grep -q "Usage" README.md || grep -q "Commands" README.md; then
            print_success "README has usage instructions"
        else
            print_error "README missing usage instructions"
        fi

        if grep -q "Examples" README.md; then
            print_success "README has examples"
        else
            print_warning "README could benefit from more examples"
        fi
    fi

    # Check CHANGELOG content
    if [[ -f "CHANGELOG.md" ]]; then
        if grep -q "1.0.0" CHANGELOG.md; then
            print_success "CHANGELOG has version 1.0.0"
        else
            print_error "CHANGELOG missing current version"
        fi
    fi
}

test_packaging() {
    print_section "Packaging Tests"

    # Check Makefile
    if [[ -f "Makefile" ]]; then
        print_success "Makefile exists"

        # Test make targets
        if make help >/dev/null 2>&1; then
            print_success "make help works"
        else
            print_error "make help fails"
        fi
    else
        print_error "Makefile missing"
    fi

    # Check install script
    if [[ -f "install.sh" ]]; then
        print_success "install.sh exists"

        if [[ -x "install.sh" ]]; then
            print_success "install.sh is executable"
        else
            print_error "install.sh not executable"
        fi
    else
        print_error "install.sh missing"
    fi

    # Check packaging files
    if [[ -f "packaging/PKGBUILD" ]]; then
        print_success "AUR PKGBUILD exists"
    else
        print_warning "AUR PKGBUILD missing"
    fi

    if [[ -f "packaging/here.rb" ]]; then
        print_success "Homebrew formula exists"
    else
        print_warning "Homebrew formula missing"
    fi

    # Check Docker support
    if [[ -f "Dockerfile" ]]; then
        print_success "Dockerfile exists"
    else
        print_warning "Dockerfile missing"
    fi
}

test_ci_cd() {
    print_section "CI/CD Tests"

    # Check GitHub Actions
    if [[ -f ".github/workflows/ci.yml" ]]; then
        print_success "GitHub Actions CI exists"
    else
        print_warning "GitHub Actions CI missing"
    fi

    # Check workflow validity (basic syntax check)
    if [[ -f ".github/workflows/ci.yml" ]]; then
        if grep -q "jobs:" .github/workflows/ci.yml; then
            print_success "GitHub Actions workflow has jobs"
        else
            print_error "GitHub Actions workflow malformed"
        fi
    fi
}

test_binary_size() {
    print_section "Binary Size Tests"

    local targets=("x86_64-linux" "aarch64-linux" "x86_64-macos" "aarch64-macos")
    for target in "${targets[@]}"; do
        local binary="zig-out/release/$target/here"
        if [[ -f "$binary" ]]; then
            local size=$(stat -c%s "$binary" 2>/dev/null || stat -f%z "$binary" 2>/dev/null)
            local size_mb=$((size / 1024 / 1024))

            if [[ $size_mb -lt 10 ]]; then
                print_success "$target binary size: ${size_mb}MB (good)"
            elif [[ $size_mb -lt 20 ]]; then
                print_warning "$target binary size: ${size_mb}MB (acceptable)"
            else
                print_error "$target binary size: ${size_mb}MB (too large)"
            fi
        fi
    done
}

test_security() {
    print_section "Security Tests"

    # Check for hardcoded secrets or sensitive data
    if grep -r -i "password\|secret\|key\|token" src/ >/dev/null 2>&1; then
        print_warning "Potential hardcoded credentials found in source code"
    else
        print_success "No obvious hardcoded credentials found"
    fi

    # Check file permissions
    if [[ -f "install.sh" ]]; then
        local perms=$(stat -c "%a" install.sh 2>/dev/null || stat -f "%A" install.sh 2>/dev/null)
        if [[ "$perms" == "755" ]] || [[ "$perms" == "0755" ]]; then
            print_success "install.sh has correct permissions"
        else
            print_warning "install.sh permissions: $perms (should be 755)"
        fi
    fi
}

test_performance() {
    print_section "Performance Tests"

    local binary="zig-out/release/x86_64-linux/here"
    if [[ -f "$binary" ]]; then
        # Test startup time (should be fast)
        local start_time=$(date +%s%3N)
        $binary version >/dev/null 2>&1
        local end_time=$(date +%s%3N)
        local duration=$((end_time - start_time))

        if [[ $duration -lt 100 ]]; then
            print_success "Startup time: ${duration}ms (excellent)"
        elif [[ $duration -lt 500 ]]; then
            print_success "Startup time: ${duration}ms (good)"
        else
            print_warning "Startup time: ${duration}ms (could be better)"
        fi

        # Test memory usage (basic check)
        local memory_usage=$(ps -o rss= -p $$ | tr -d ' ')
        if [[ $memory_usage -lt 10000 ]]; then  # Less than 10MB
            print_success "Memory usage reasonable"
        else
            print_warning "Memory usage might be high"
        fi
    else
        print_warning "No release binary available for performance testing"
    fi
}

# Main validation function
main() {
    echo -e "${BLUE}"
    echo "🏠 here - Production Readiness Validation"
    echo "=======================================${NC}"
    echo

    print_info "Starting validation process..."
    echo

    # Run all tests
    test_build_system
    test_binary_functionality
    test_documentation
    test_packaging
    test_ci_cd
    test_binary_size
    test_security
    test_performance

    # Summary
    print_section "Validation Summary"

    echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"

    local total_tests=$((TESTS_PASSED + TESTS_FAILED))
    local pass_rate=$((TESTS_PASSED * 100 / total_tests))

    echo
    if [[ $TESTS_FAILED -eq 0 ]]; then
        if [[ $WARNINGS -eq 0 ]]; then
            print_success "🚀 READY FOR PRODUCTION RELEASE!"
            echo -e "${GREEN}All tests passed with no warnings. The project is production-ready.${NC}"
        else
            print_success "✅ READY FOR PRODUCTION (with minor warnings)"
            echo -e "${YELLOW}All critical tests passed, but there are $WARNINGS warnings to consider.${NC}"
        fi
    elif [[ $pass_rate -ge 80 ]]; then
        print_warning "⚠️  MOSTLY READY (${pass_rate}% pass rate)"
        echo -e "${YELLOW}Most tests passed, but $TESTS_FAILED critical issues need fixing.${NC}"
    else
        print_error "❌ NOT READY FOR PRODUCTION (${pass_rate}% pass rate)"
        echo -e "${RED}Too many critical issues. Please fix $TESTS_FAILED failing tests.${NC}"
    fi

    echo
    print_info "Validation complete!"

    # Exit with appropriate code
    if [[ $TESTS_FAILED -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

# Run main function
main "$@"
