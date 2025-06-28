# MABEAM Test Helper
# Sets up test environment for MABEAM modules

# Load the main test helper which loads all support files
Code.require_file("../test_helper.exs", __DIR__)

# The main test helper already handles:
# - Starting Foundation services
# - Starting MABEAM services for MABEAM tests
# - Loading all test support modules (TestWorker, etc.)
# - Configuring ExUnit

# Nothing else needed here - main test helper handles everything
