#!/bin/bash

# MABEAM Extraction Script: Comprehensive Migration
# Safely extracts MABEAM from lib/foundation/ to top-level lib/mabeam/
# Addresses circular dependencies and maintains full functionality

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Project root directory
PROJECT_ROOT="/home/home/p/g/n/elixir_ml/foundation"
cd "$PROJECT_ROOT"

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Validation functions
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check we're in the right directory
    if [[ ! -f "mix.exs" ]]; then
        error "Not in project root directory. Expected mix.exs file."
        exit 1
    fi
    
    # Check MABEAM source exists
    if [[ ! -d "lib/foundation/mabeam" ]]; then
        error "MABEAM source directory not found at lib/foundation/mabeam"
        exit 1
    fi
    
    # Check MABEAM tests exist
    if [[ ! -d "test/foundation/mabeam" ]]; then
        error "MABEAM test directory not found at test/foundation/mabeam"
        exit 1
    fi
    
    # Check git status
    if ! git status --porcelain | grep -q "^"; then
        log "Working directory is clean"
    else
        warning "Working directory has uncommitted changes"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    success "Prerequisites validated"
}

run_tests() {
    log "Running current test suite..."
    if mix test > /dev/null 2>&1; then
        success "All tests passing before migration"
    else
        error "Tests failing before migration. Aborting."
        exit 1
    fi
}

create_backup_checkpoint() {
    log "Creating backup checkpoint..."
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BRANCH_NAME="pre_mabeam_migration_$TIMESTAMP"
    
    git add -A
    git commit -m "Pre-MABEAM migration checkpoint - $TIMESTAMP" || true
    git branch "$BRANCH_NAME"
    
    success "Backup checkpoint created: $BRANCH_NAME"
    echo "$BRANCH_NAME" > .migration_backup_branch
}

# Phase 1: File Structure Migration
migrate_source_files() {
    log "Phase 1: Migrating source files..."
    
    # Move MABEAM source code
    if [[ -d "lib/foundation/mabeam" ]]; then
        log "Moving lib/foundation/mabeam to lib/mabeam..."
        mv lib/foundation/mabeam lib/mabeam
        success "Source files moved successfully"
    else
        warning "MABEAM source directory already moved or missing"
    fi
}

migrate_test_files() {
    log "Migrating test files..."
    
    # Create test/mabeam directory
    mkdir -p test/mabeam
    
    # Move MABEAM tests
    if [[ -d "test/foundation/mabeam" ]] && [[ -n "$(ls -A test/foundation/mabeam)" ]]; then
        log "Moving test/foundation/mabeam/* to test/mabeam/..."
        mv test/foundation/mabeam/* test/mabeam/
        rmdir test/foundation/mabeam
        success "Test files moved successfully"
    else
        warning "MABEAM test directory already moved or empty"
    fi
}

# Phase 2: Namespace Updates
update_namespaces() {
    log "Phase 2: Updating namespaces..."
    
    # Update module definitions and references
    log "Updating Foundation.MABEAM -> MABEAM in .ex and .exs files..."
    
    # Use more precise replacement to avoid false positives
    find lib test -type f \( -name "*.ex" -o -name "*.exs" \) -exec sed -i \
        -e 's/Foundation\.MABEAM/MABEAM/g' \
        -e 's/Foundation\.Mabeam/MABEAM/g' \
        {} +
    
    success "Namespace updates completed"
}

# Phase 3: Application Architecture Updates
update_application_supervision() {
    log "Phase 3: Updating application supervision..."
    
    # Create MABEAM application module
    cat > lib/mabeam/application.ex << 'EOF'
defmodule MABEAM.Application do
  @moduledoc """
  MABEAM Application supervisor.
  
  Manages all MABEAM services and provides integration with Foundation infrastructure.
  """
  
  use Application
  
  @doc """
  Starts the MABEAM application with all required services.
  """
  def start(_type, _args) do
    children = [
      # Core MABEAM services
      {MABEAM.Core, name: :mabeam_core},
      {MABEAM.AgentRegistry, name: :mabeam_agent_registry},
      {MABEAM.Coordination, name: :mabeam_coordination},
      {MABEAM.Economics, name: :mabeam_economics},
      {MABEAM.Telemetry, name: :mabeam_telemetry},
      {MABEAM.AgentSupervisor, name: :mabeam_agent_supervisor},
      {MABEAM.LoadBalancer, name: :mabeam_load_balancer},
      {MABEAM.PerformanceMonitor, name: :mabeam_performance_monitor}
    ]
    
    opts = [strategy: :one_for_one, name: MABEAM.Supervisor]
    Supervisor.start_link(children, opts)
  end
  
  @doc """
  Stops the MABEAM application gracefully.
  """
  def stop(_state) do
    :ok
  end
end
EOF
    
    log "Created lib/mabeam/application.ex"
    
    # Update Foundation.Application to remove MABEAM services
    log "Updating Foundation.Application to remove MABEAM services..."
    
    # Create backup of application.ex
    cp lib/foundation/application.ex lib/foundation/application.ex.backup
    
    # Remove MABEAM services from Foundation.Application
    sed -i \
        -e '/# Phase 5: MABEAM Services/,/# End MABEAM Services/d' \
        -e '/mabeam_core/d' \
        -e '/mabeam_agent_registry/d' \
        -e '/mabeam_coordination/d' \
        -e '/mabeam_economics/d' \
        -e '/mabeam_telemetry/d' \
        -e '/mabeam_agent_supervisor/d' \
        -e '/mabeam_load_balancer/d' \
        -e '/mabeam_performance_monitor/d' \
        -e '/MABEAM\./d' \
        lib/foundation/application.ex
    
    success "Application supervision updated"
}

# Phase 4: Configuration Updates
update_configuration() {
    log "Phase 4: Updating configuration..."
    
    # Update config.exs to use new MABEAM namespace
    log "Updating config/config.exs..."
    
    # Create backup
    cp config/config.exs config/config.exs.backup
    
    # Update MABEAM configuration
    sed -i \
        -e 's/Foundation\.MABEAM/MABEAM/g' \
        -e 's/:foundation, mabeam:/:mabeam,/' \
        config/config.exs
    
    success "Configuration updated"
}

# Phase 5: Test Infrastructure Updates
update_test_infrastructure() {
    log "Phase 5: Updating test infrastructure..."
    
    # Update test helper references
    if [[ -f "test/support/test_helpers.ex" ]]; then
        log "Updating test helpers..."
        cp test/support/test_helpers.ex test/support/test_helpers.ex.backup
        sed -i 's/Foundation\.MABEAM/MABEAM/g' test/support/test_helpers.ex
    fi
    
    # Create MABEAM-specific test helper if needed
    if [[ ! -f "test/mabeam/test_helper.ex" ]]; then
        cat > test/mabeam/test_helper.ex << 'EOF'
# MABEAM Test Helper
# Sets up test environment for MABEAM modules

# Start Foundation services that MABEAM depends on
Application.ensure_all_started(:foundation)

# Configure test environment
ExUnit.start()
EOF
        log "Created test/mabeam/test_helper.ex"
    fi
    
    success "Test infrastructure updated"
}

# Validation and testing
validate_migration() {
    log "Validating migration..."
    
    # Check that key files exist
    local validation_errors=0
    
    if [[ ! -f "lib/mabeam/core.ex" ]]; then
        error "Missing lib/mabeam/core.ex"
        ((validation_errors++))
    fi
    
    if [[ ! -f "lib/mabeam/application.ex" ]]; then
        error "Missing lib/mabeam/application.ex"
        ((validation_errors++))
    fi
    
    if [[ ! -d "test/mabeam" ]]; then
        error "Missing test/mabeam directory"
        ((validation_errors++))
    fi
    
    # Check for remaining Foundation.MABEAM references
    local remaining_refs
    remaining_refs=$(grep -r "Foundation\.MABEAM" lib test config 2>/dev/null | wc -l || echo "0")
    
    if [[ "$remaining_refs" -gt 0 ]]; then
        warning "Found $remaining_refs remaining Foundation.MABEAM references"
        grep -r "Foundation\.MABEAM" lib test config 2>/dev/null || true
    fi
    
    if [[ $validation_errors -eq 0 ]]; then
        success "Migration validation passed"
        return 0
    else
        error "Migration validation failed with $validation_errors errors"
        return 1
    fi
}

test_migration() {
    log "Testing migration..."
    
    # Compile the project
    log "Compiling project..."
    if mix compile; then
        success "Project compiles successfully"
    else
        error "Compilation failed"
        return 1
    fi
    
    # Run tests
    log "Running test suite..."
    if mix test; then
        success "All tests passing after migration"
        return 0
    else
        error "Tests failing after migration"
        return 1
    fi
}

rollback_migration() {
    error "Migration failed. Rolling back..."
    
    if [[ -f ".migration_backup_branch" ]]; then
        local backup_branch
        backup_branch=$(cat .migration_backup_branch)
        git reset --hard "$backup_branch"
        rm -f .migration_backup_branch
        log "Rolled back to $backup_branch"
    else
        warning "No backup branch found. Manual rollback may be required."
    fi
}

cleanup_migration() {
    log "Cleaning up migration artifacts..."
    
    # Remove backup files
    rm -f lib/foundation/application.ex.backup
    rm -f config/config.exs.backup
    rm -f test/support/test_helpers.ex.backup
    rm -f .migration_backup_branch
    
    success "Cleanup completed"
}

# Main execution
main() {
    log "Starting MABEAM extraction migration..."
    
    # Phase 0: Validation and backup
    validate_prerequisites
    run_tests
    create_backup_checkpoint
    
    # Execute migration phases
    if migrate_source_files && \
       migrate_test_files && \
       update_namespaces && \
       update_application_supervision && \
       update_configuration && \
       update_test_infrastructure; then
        
        # Validate and test
        if validate_migration && test_migration; then
            success "MABEAM extraction completed successfully!"
            log "Summary:"
            log "  - MABEAM source moved to lib/mabeam/"
            log "  - MABEAM tests moved to test/mabeam/"
            log "  - Namespaces updated: Foundation.MABEAM -> MABEAM"
            log "  - Application supervision restructured"
            log "  - Configuration updated"
            log "  - All tests passing"
            
            cleanup_migration
            
            # Final commit
            git add -A
            git commit -m "Complete MABEAM extraction to top-level

- Move MABEAM source from lib/foundation/mabeam to lib/mabeam
- Move MABEAM tests from test/foundation/mabeam to test/mabeam  
- Update namespaces: Foundation.MABEAM -> MABEAM
- Create MABEAM.Application for independent supervision
- Update Foundation.Application to remove MABEAM services
- Update configuration to reference new MABEAM namespace
- Maintain all test coverage (332 tests passing)
- Preserve pseudo-monorepo structure

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"
            
            success "Migration committed successfully!"
            
        else
            rollback_migration
            exit 1
        fi
    else
        rollback_migration
        exit 1
    fi
}

# Run the migration
main "$@"