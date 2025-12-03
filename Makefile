# Makefile for here - Universal Package Manager
# https://github.com/your-repo/here

.PHONY: all build build-release clean test install uninstall help dev-setup format lint check-fmt validate validate-appimage validate-production

# Default target
all: build

# Configuration
VERSION = 1.0.0
APP_NAME = here
BUILD_DIR = zig-out
RELEASE_DIR = $(BUILD_DIR)/release
INSTALL_PREFIX = /usr/local
INSTALL_DIR = $(INSTALL_PREFIX)/bin

# Zig build settings
ZIG_FLAGS =
RELEASE_FLAGS = -Doptimize=ReleaseFast

# Colors for output
GREEN = \033[0;32m
YELLOW = \033[1;33m
RED = \033[0;31m
NC = \033[0m # No Color

# Build targets
build:
	@echo "$(GREEN)Building $(APP_NAME) (debug)...$(NC)"
	zig build $(ZIG_FLAGS)
	@echo "$(GREEN)Build complete: $(BUILD_DIR)/bin/$(APP_NAME)$(NC)"

build-release:
	@echo "$(GREEN)Building $(APP_NAME) release binaries...$(NC)"
	zig build release $(RELEASE_FLAGS)
	@echo "$(GREEN)Release builds complete:$(NC)"
	@ls -la $(RELEASE_DIR)/*/$(APP_NAME) 2>/dev/null || echo "$(RED)No release binaries found$(NC)"

# Clean build artifacts
clean:
	@echo "$(YELLOW)Cleaning build artifacts...$(NC)"
	rm -rf $(BUILD_DIR) .zig-cache
	@echo "$(GREEN)Clean complete$(NC)"

# Run tests
test:
	@echo "$(GREEN)Running tests...$(NC)"
	zig build test
	@echo "$(GREEN)All tests passed$(NC)"

# Validation targets
validate:
	@echo "$(GREEN)Running full production validation...$(NC)"
	./validate.sh
	@echo "$(GREEN)Validation complete$(NC)"

validate-appimage:
	@echo "$(GREEN)Running AppImage-specific validation...$(NC)"
	chmod +x validate_appimage.sh
	./validate_appimage.sh
	@echo "$(GREEN)AppImage validation complete$(NC)"

validate-production:
	@echo "$(GREEN)Running comprehensive production validation...$(NC)"
	@echo "$(YELLOW)Testing: AppMan Integration • Wallet Address • AppImage Indexing$(NC)"
	chmod +x validate_production.sh
	./validate_production.sh
	@echo "$(GREEN)Production validation complete$(NC)"

# Format code
format:
	@echo "$(GREEN)Formatting code...$(NC)"
	zig fmt src/

# Check if code is formatted
check-fmt:
	@echo "$(GREEN)Checking code formatting...$(NC)"
	zig fmt --check src/

# Lint and validate
lint: check-fmt
	@echo "$(GREEN)Linting complete$(NC)"

# Development checks
check: test lint
	@echo "$(GREEN)All checks passed$(NC)"

# Install locally (requires sudo for system installation)
install: build-release
	@echo "$(GREEN)Installing $(APP_NAME) to $(INSTALL_DIR)...$(NC)"
	@if [ "$(INSTALL_DIR)" = "/usr/local/bin" ] && [ "$$(id -u)" -ne 0 ]; then \
		echo "$(YELLOW)Installing to system directory requires sudo$(NC)"; \
		sudo cp $(RELEASE_DIR)/x86_64-linux/$(APP_NAME) $(INSTALL_DIR)/$(APP_NAME); \
	else \
		mkdir -p $(INSTALL_DIR); \
		cp $(RELEASE_DIR)/x86_64-linux/$(APP_NAME) $(INSTALL_DIR)/$(APP_NAME); \
	fi
	@echo "$(GREEN)Installation complete: $(INSTALL_DIR)/$(APP_NAME)$(NC)"
	@$(INSTALL_DIR)/$(APP_NAME) version

# Uninstall
uninstall:
	@echo "$(YELLOW)Uninstalling $(APP_NAME) from $(INSTALL_DIR)...$(NC)"
	@if [ "$(INSTALL_DIR)" = "/usr/local/bin" ] && [ "$$(id -u)" -ne 0 ]; then \
		sudo rm -f $(INSTALL_DIR)/$(APP_NAME); \
	else \
		rm -f $(INSTALL_DIR)/$(APP_NAME); \
	fi
	@echo "$(GREEN)Uninstall complete$(NC)"

# Install to user directory
install-user: build-release
	@echo "$(GREEN)Installing $(APP_NAME) to ~/.local/bin...$(NC)"
	@mkdir -p ~/.local/bin
	@cp $(RELEASE_DIR)/x86_64-linux/$(APP_NAME) ~/.local/bin/$(APP_NAME)
	@echo "$(GREEN)Installation complete: ~/.local/bin/$(APP_NAME)$(NC)"
	@echo "$(YELLOW)Make sure ~/.local/bin is in your PATH$(NC)"
	@~/.local/bin/$(APP_NAME) version

# Development setup
dev-setup:
	@echo "$(GREEN)Setting up development environment...$(NC)"
	@if ! command -v zig >/dev/null 2>&1; then \
		echo "$(RED)Zig is not installed. Please install Zig 0.12.1 or later$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Zig version:$(NC)"
	@zig version
	@echo "$(GREEN)Development setup complete$(NC)"

# Run the application
run:
	@zig build run

# Run with arguments
run-args:
	@echo "$(GREEN)Usage: make run-args ARGS='help'$(NC)"
	@zig build run -- $(ARGS)

# Package releases
package: build-release
	@echo "$(GREEN)Packaging release binaries...$(NC)"
	@mkdir -p dist
	@for target in x86_64-linux aarch64-linux x86_64-macos aarch64-macos; do \
		if [ -f "$(RELEASE_DIR)/$$target/$(APP_NAME)" ]; then \
			cp "$(RELEASE_DIR)/$$target/$(APP_NAME)" "dist/$(APP_NAME)-$$target"; \
			echo "Created: dist/$(APP_NAME)-$$target"; \
		fi; \
	done
	@echo "$(GREEN)Packaging complete$(NC)"

# Create distribution archive
dist: package
	@echo "$(GREEN)Creating distribution archive...$(NC)"
	@tar -czf "dist/$(APP_NAME)-$(VERSION).tar.gz" \
		-C dist $(shell ls dist/$(APP_NAME)-* | sed 's|dist/||g') \
		-C .. README.md CHANGELOG.md LICENSE install.sh
	@echo "$(GREEN)Distribution archive created: dist/$(APP_NAME)-$(VERSION).tar.gz$(NC)"

# Benchmark
benchmark: build-release
	@echo "$(GREEN)Running benchmarks...$(NC)"
	@echo "Binary size:"
	@ls -lh $(RELEASE_DIR)/x86_64-linux/$(APP_NAME)
	@echo "\nStartup time (average of 10 runs):"
	@time -f "%E real" bash -c 'for i in {1..10}; do $(RELEASE_DIR)/x86_64-linux/$(APP_NAME) version >/dev/null; done'

# Show binary information
info: build-release
	@echo "$(GREEN)Binary information:$(NC)"
	@echo "Version: $(VERSION)"
	@echo "Binaries:"
	@ls -la $(RELEASE_DIR)/*/$(APP_NAME) 2>/dev/null || echo "No binaries found"
	@echo "\nSizes:"
	@du -h $(RELEASE_DIR)/*/$(APP_NAME) 2>/dev/null || echo "No binaries found"

# Docker build (if Dockerfile exists)
docker-build:
	@if [ -f Dockerfile ]; then \
		echo "$(GREEN)Building Docker image...$(NC)"; \
		docker build -t $(APP_NAME):$(VERSION) .; \
	else \
		echo "$(YELLOW)Dockerfile not found$(NC)"; \
	fi

# Help
help:
	@echo "$(GREEN)here - Universal Package Manager$(NC)"
	@echo ""
	@echo "Available targets:"
	@echo "  $(GREEN)build$(NC)         Build debug version"
	@echo "  $(GREEN)build-release$(NC) Build optimized release binaries for all platforms"
	@echo "  $(GREEN)clean$(NC)         Remove build artifacts"
	@echo "  $(GREEN)test$(NC)          Run tests"
	@echo "  $(GREEN)format$(NC)        Format source code"
	@echo "  $(GREEN)check-fmt$(NC)     Check code formatting"
	@echo "  $(GREEN)lint$(NC)          Run linter"
	@echo "  $(GREEN)check$(NC)         Run tests and linting"
	@echo "  $(GREEN)install$(NC)       Install to $(INSTALL_DIR) (requires sudo)"
	@echo "  $(GREEN)install-user$(NC)  Install to ~/.local/bin"
	@echo "  $(GREEN)uninstall$(NC)     Remove from $(INSTALL_DIR)"
	@echo "  $(GREEN)dev-setup$(NC)     Setup development environment"
	@echo "  $(GREEN)run$(NC)           Run the application"
	@echo "  $(GREEN)run-args$(NC)      Run with arguments (use ARGS='...')"
	@echo "  $(GREEN)package$(NC)       Package release binaries"
	@echo "  $(GREEN)dist$(NC)          Create distribution archive"
	@echo "  $(GREEN)benchmark$(NC)     Run performance benchmarks"
	@echo "  $(GREEN)info$(NC)          Show binary information"
	@echo "  $(GREEN)help$(NC)          Show this help message"
	@echo ""
	@echo "Examples:"
	@echo "  make build"
	@echo "  make test"
	@echo "  make install-user"
	@echo "  make run-args ARGS='search vim'"
	@echo "  make check"
	@echo ""
	@echo "For more information, visit: https://github.com/your-repo/here"
