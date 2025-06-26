# MABEAM Test Helper
# Sets up test environment for MABEAM modules

# Start Foundation services that MABEAM depends on
Application.ensure_all_started(:foundation)

# Configure test environment
ExUnit.start()
