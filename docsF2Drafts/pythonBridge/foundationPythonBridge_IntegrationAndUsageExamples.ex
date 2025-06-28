# ==============================================================================
# Python Bridge Integration with Foundation Application
# ==============================================================================

defmodule Foundation.Application do
  @moduledoc """
  Updated Foundation Application with Python Bridge integration.

  This shows how to integrate the Python Bridge into the existing Foundation
  supervision tree and configuration system.
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting Foundation application with Python Bridge...")

    base_children = [
      # Foundation Layer Services (existing)
      {Foundation.ProcessRegistry, []},
      {Foundation.Services.ConfigServer, [namespace: :production]},
      {Foundation.Services.EventStore, [namespace: :production]},
      {Foundation.Services.TelemetryService, [namespace: :production]},

      # Infrastructure protection components (existing)
      {Foundation.Infrastructure.ConnectionManager, []},
      {Foundation.Infrastructure.RateLimiter.HammerBackend, []},

      # NEW: Python Bridge components
      {Foundation.Bridge.Python.Config, []},
      {Foundation.Bridge.Python.Supervisor, [
        python_path: get_python_path(),
        pool_size: 5,
        script_dir: get_script_directory(),
        circuit_breaker_enabled: true,
        debug_mode: Application.get_env(:foundation, :debug_python_bridge, false)
      ]},

      # Task supervisor for dynamic tasks (existing)
      {Task.Supervisor, name: Foundation.TaskSupervisor}
    ]

    children = base_children ++ test_children()

    opts = [strategy: :one_for_one, name: Foundation.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("Foundation application with Python Bridge started successfully")
        initialize_python_pools()
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start Foundation application: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private helper functions

  defp get_python_path do
    Application.get_env(:foundation, :python_path, "python3")
  end

  defp get_script_directory do
    Application.get_env(:foundation, :python_script_dir, "./priv/python")
  end

  defp initialize_python_pools do
    # Initialize specialized Python pools for different workloads
    Task.start(fn ->
      # Wait for Python bridge to be ready
      Process.sleep(1000)

      # Create data science pool
      Foundation.Bridge.Python.create_pool(:data_science,
        size: 3,
        preload_modules: ["pandas", "numpy", "matplotlib", "seaborn"]
      )

      # Create machine learning pool
      Foundation.Bridge.Python.create_pool(:machine_learning,
        size: 2,
        preload_modules: ["sklearn", "tensorflow", "torch"]
      )

      # Create general computation pool
      Foundation.Bridge.Python.create_pool(:computation,
        size: 4,
        preload_modules: ["math", "statistics", "itertools"]
      )

      Logger.info("Python Bridge pools initialized")
    end)
  end

  defp test_children do
    if Application.get_env(:foundation, :test_mode, false) do
      [{Foundation.TestSupport.TestSupervisor, []}]
    else
      []
    end
  end
end

# ==============================================================================
# Python Bridge Usage Examples and Patterns
# ==============================================================================

defmodule Foundation.Examples.PythonBridge do
  @moduledoc """
  Comprehensive examples showing how to use the Foundation Python Bridge
  for various real-world scenarios.
  """

  require Logger
  alias Foundation.Bridge.Python
  alias Foundation.Bridge.Python.API

  # ==============================================================================
  # Basic Python Execution Examples
  # ==============================================================================

  @doc """
  Basic Python code execution example.
  """
  def basic_execution_example do
    # Simple calculation
    case Python.execute("return 2 + 2") do
      {:ok, 4} ->
        Logger.info("Basic calculation successful")

      {:error, error} ->
        Logger.error("Basic calculation failed: #{inspect(error)}")
    end

    # String manipulation
    case Python.execute(~s(return "hello world".title())) do
      {:ok, "Hello World"} ->
        Logger.info("String manipulation successful")

      {:error, error} ->
        Logger.error("String manipulation failed: #{inspect(error)}")
    end
  end

  @doc """
  Python function calls with arguments.
  """
  def function_call_examples do
    # Mathematical functions
    {:ok, result} = Python.call("math.sqrt", [16])
    Logger.info("Square root of 16: #{result}")

    # List operations
    {:ok, sorted_list} = Python.call("sorted", [[3, 1, 4, 1, 5, 9]])
    Logger.info("Sorted list: #{inspect(sorted_list)}")

    # JSON operations
    data = %{name: "Alice", age: 30, city: "New York"}
    {:ok, json_string} = Python.call("json.dumps", [data])
    Logger.info("JSON encoded: #{json_string}")
  end

  # ==============================================================================
  # Data Science Examples
  # ==============================================================================

  @doc """
  Data analysis with pandas and numpy.
  """
  def data_analysis_example do
    # Sample dataset
    sales_data = [
      %{product: "Widget A", sales: 100, month: "Jan"},
      %{product: "Widget B", sales: 150, month: "Jan"},
      %{product: "Widget A", sales: 120, month: "Feb"},
      %{product: "Widget B", sales: 180, month: "Feb"},
      %{product: "Widget A", sales: 90, month: "Mar"},
      %{product: "Widget B", sales: 200, month: "Mar"}
    ]

    analysis_code = """
    import pandas as pd
    import numpy as np

    # Create DataFrame from input data
    df = pd.DataFrame(input_data['sales_data'])

    # Perform analysis
    monthly_totals = df.groupby('month')['sales'].sum().to_dict()
    product_averages = df.groupby('product')['sales'].mean().to_dict()
    total_sales = df['sales'].sum()

    # Calculate growth rates
    monthly_sorted = df.groupby('month')['sales'].sum().sort_index()
    growth_rates = monthly_sorted.pct_change().fillna(0).to_dict()

    return {
        'monthly_totals': monthly_totals,
        'product_averages': product_averages,
        'total_sales': int(total_sales),
        'growth_rates': growth_rates,
        'top_month': monthly_sorted.idxmax(),
        'summary_stats': df['sales'].describe().to_dict()
    }
    """

    case API.data_pipeline(analysis_code, input_data: %{sales_data: sales_data}) do
      {:ok, results} ->
        Logger.info("Data analysis completed:")
        Logger.info("  Total sales: #{results["total_sales"]}")
        Logger.info("  Monthly totals: #{inspect(results["monthly_totals"])}")
        Logger.info("  Product averages: #{inspect(results["product_averages"])}")
        Logger.info("  Best month: #{results["top_month"]}")

      {:error, error} ->
        Logger.error("Data analysis failed: #{inspect(error)}")
    end
  end

  @doc """
  Machine learning example with scikit-learn.
  """
  def machine_learning_example do
    # Training data for a simple classification problem
    training_data = %{
      features: [
        [1, 2], [2, 3], [3, 4], [4, 5], [5, 6],  # Class A
        [6, 1], [7, 2], [8, 3], [9, 4], [10, 5]  # Class B
      ],
      targets: [0, 0, 0, 0, 0, 1, 1, 1, 1, 1]
    }

    test_data = [[2.5, 3.5], [7.5, 2.5], [1, 1], [9, 4]]

    ml_code = """
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.metrics import accuracy_score
    import numpy as np

    # Prepare data
    X_train = np.array(training_data['features'])
    y_train = np.array(training_data['targets'])
    X_test = np.array(test_data)

    # Train model
    model = RandomForestClassifier(n_estimators=10, random_state=42)
    model.fit(X_train, y_train)

    # Make predictions
    predictions = model.predict(X_test).tolist()
    probabilities = model.predict_proba(X_test).tolist()

    # Calculate training accuracy
    train_predictions = model.predict(X_train)
    training_accuracy = accuracy_score(y_train, train_predictions)

    # Feature importance
    feature_importance = model.feature_importances_.tolist()

    return {
        'predictions': predictions,
        'probabilities': probabilities,
        'training_accuracy': float(training_accuracy),
        'feature_importance': feature_importance,
        'model_info': {
            'n_estimators': model.n_estimators,
            'n_features': model.n_features_in_
        }
    }
    """

    case API.ml_execute(ml_code,
      training_data: training_data,
      test_data: test_data,
      timeout: 60_000) do
      {:ok, results} ->
        Logger.info("Machine learning model trained successfully:")
        Logger.info("  Training accuracy: #{Float.round(results["training_accuracy"], 3)}")
        Logger.info("  Predictions: #{inspect(results["predictions"])}")
        Logger.info("  Feature importance: #{inspect(results["feature_importance"])}")

      {:error, error} ->
        Logger.error("Machine learning training failed: #{inspect(error)}")
    end
  end

  # ==============================================================================
  # Image Processing Example
  # ==============================================================================

  @doc """
  Image processing with PIL/Pillow.
  """
  def image_processing_example do
    # This example assumes you have an image file available
    image_processing_code = """
    from PIL import Image, ImageFilter, ImageEnhance
    import base64
    import io

    # Open image (replace with actual image path)
    try:
        img = Image.open('sample_image.jpg')

        # Get original dimensions
        original_size = img.size

        # Apply various transformations
        # 1. Resize to thumbnail
        thumbnail = img.copy()
        thumbnail.thumbnail((200, 200))

        # 2. Apply blur filter
        blurred = img.filter(ImageFilter.BLUR)

        # 3. Enhance contrast
        enhancer = ImageEnhance.Contrast(img)
        high_contrast = enhancer.enhance(2.0)

        # 4. Convert to grayscale
        grayscale = img.convert('L')

        # Convert processed images to base64 for transmission
        def img_to_base64(image):
            buffer = io.BytesIO()
            image.save(buffer, format='JPEG')
            return base64.b64encode(buffer.getvalue()).decode()

        return {
            'original_size': original_size,
            'thumbnail_size': thumbnail.size,
            'processing_completed': True,
            'transformations': ['resize', 'blur', 'contrast', 'grayscale'],
            'thumbnail_data': img_to_base64(thumbnail),
            'metadata': {
                'format': img.format,
                'mode': img.mode,
                'has_transparency': 'transparency' in img.info
            }
        }

    except FileNotFoundError:
        return {
            'error': 'Image file not found',
            'processing_completed': False
        }
    except Exception as e:
        return {
            'error': str(e),
            'processing_completed': False
        }
    """

    case Python.execute(image_processing_code, pool: :computation, timeout: 30_000) do
      {:ok, %{"processing_completed" => true} = results} ->
        Logger.info("Image processing completed:")
        Logger.info("  Original size: #{inspect(results["original_size"])}")
        Logger.info("  Thumbnail size: #{inspect(results["thumbnail_size"])}")
        Logger.info("  Transformations: #{inspect(results["transformations"])}")

      {:ok, %{"error" => error}} ->
        Logger.warning("Image processing failed: #{error}")

      {:error, error} ->
        Logger.error("Image processing execution failed: #{inspect(error)}")
    end
  end

  # ==============================================================================
  # Web Scraping Example
  # ==============================================================================

  @doc """
  Web scraping with requests and BeautifulSoup.
  """
  def web_scraping_example do
    scraping_code = """
    import requests
    from bs4 import BeautifulSoup
    import re

    def scrape_website(url):
        try:
            # Make request with timeout
            response = requests.get(url, timeout=10)
            response.raise_for_status()

            # Parse HTML
            soup = BeautifulSoup(response.content, 'html.parser')

            # Extract information
            title = soup.find('title')
            title_text = title.get_text().strip() if title else 'No title found'

            # Find all links
            links = []
            for link in soup.find_all('a', href=True):
                href = link['href']
                text = link.get_text().strip()
                if href and text:
                    links.append({'url': href, 'text': text[:100]})  # Limit text length

            # Find all headings
            headings = []
            for heading in soup.find_all(['h1', 'h2', 'h3', 'h4', 'h5', 'h6']):
                headings.append({
                    'tag': heading.name,
                    'text': heading.get_text().strip()[:200]  # Limit text length
                })

            # Extract meta information
            meta_info = {}
            for meta in soup.find_all('meta'):
                name = meta.get('name') or meta.get('property')
                content = meta.get('content')
                if name and content:
                    meta_info[name] = content[:200]  # Limit content length

            return {
                'success': True,
                'url': url,
                'title': title_text,
                'links_count': len(links),
                'links': links[:10],  # Return first 10 links
                'headings': headings[:20],  # Return first 20 headings
                'meta_info': meta_info,
                'content_length': len(response.content),
                'status_code': response.status_code
            }

        except requests.RequestException as e:
            return {
                'success': False,
                'error': f'Request failed: {str(e)}',
                'error_type': 'request_error'
            }
        except Exception as e:
            return {
                'success': False,
                'error': f'Parsing failed: {str(e)}',
                'error_type': 'parsing_error'
            }

    # Example: Scrape a website (replace with actual URL)
    url = input_data.get('url', 'https://httpbin.org/html')
    return scrape_website(url)
    """

    case API.execute_with_data(scraping_code,
      data: %{url: "https://httpbin.org/html"},
      timeout: 30_000) do
      {:ok, %{"success" => true} = results} ->
        Logger.info("Web scraping completed:")
        Logger.info("  Title: #{results["title"]}")
        Logger.info("  Links found: #{results["links_count"]}")
        Logger.info("  Content length: #{results["content_length"]} bytes")

      {:ok, %{"success" => false, "error" => error}} ->
        Logger.warning("Web scraping failed: #{error}")

      {:error, error} ->
        Logger.error("Web scraping execution failed: #{inspect(error)}")
    end
  end

  # ==============================================================================
  # Async Processing Examples
  # ==============================================================================

  @doc """
  Asynchronous Python execution with callbacks.
  """
  def async_processing_example do
    # Start multiple async Python tasks
    tasks = [
      API.execute_async("import time; time.sleep(2); return 'Task 1 completed'",
        callback: fn result -> Logger.info("Callback 1: #{inspect(result)}") end),

      API.execute_async("import time; time.sleep(1); return 'Task 2 completed'",
        callback: fn result -> Logger.info("Callback 2: #{inspect(result)}") end),

      API.execute_async("return sum(range(1000000))",
        callback: fn result -> Logger.info("Callback 3: #{inspect(result)}") end)
    ]

    # Wait for all tasks to complete
    results = Task.await_many(tasks, 10_000)

    Logger.info("All async tasks completed:")
    Enum.with_index(results, 1)
    |> Enum.each(fn {result, index} ->
      Logger.info("  Task #{index}: #{inspect(result)}")
    end)
  end

  # ==============================================================================
  # Error Handling and Recovery Examples
  # ==============================================================================

  @doc """
  Demonstrate error handling and recovery patterns.
  """
  def error_handling_examples do
    # Example 1: Syntax error
    case Python.execute("invalid python syntax here") do
      {:ok, result} ->
        Logger.info("Unexpected success: #{inspect(result)}")

      {:error, error} ->
        Logger.info("Expected syntax error caught: #{error.message}")
    end

    # Example 2: Runtime error
    case Python.execute("return 1 / 0") do
      {:ok, result} ->
        Logger.info("Unexpected success: #{inspect(result)}")

      {:error, error} ->
        Logger.info("Expected division by zero error: #{error.message}")
    end

    # Example 3: Timeout handling
    case Python.execute("import time; time.sleep(10); return 'done'", timeout: 2000) do
      {:ok, result} ->
        Logger.info("Unexpected success: #{inspect(result)}")

      {:error, error} ->
        Logger.info("Expected timeout error: #{error.message}")
    end

    # Example 4: Circuit breaker demonstration
    # Deliberately cause multiple failures to trigger circuit breaker
    Enum.each(1..10, fn i ->
      case Python.execute("raise Exception('Deliberate failure #{i}')") do
        {:error, %{error_type: :circuit_breaker_blown}} ->
          Logger.info("Circuit breaker triggered at attempt #{i}")

        {:error, error} ->
          Logger.info("Failure #{i}: #{error.message}")
      end
    end)
  end

  # ==============================================================================
  # Performance Monitoring Example
  # ==============================================================================

  @doc """
  Monitor Python bridge performance and health.
  """
  def performance_monitoring_example do
    # Get bridge status
    case Python.status() do
      {:ok, status} ->
        Logger.info("Python Bridge Status:")
        Logger.info("  Status: #{status.status}")
        Logger.info("  Pools: #{map_size(status.pools)}")
        Logger.info("  Uptime: #{status.uptime_ms}ms")
        Logger.info("  Successful executions: #{status.metrics.successful_executions}")
        Logger.info("  Failed executions: #{status.metrics.failed_executions}")

      {:error, error} ->
        Logger.error("Failed to get status: #{inspect(error)}")
    end

    # Perform health check
    case Python.health_check() do
      {:ok, health_report} ->
        Logger.info("Health Check Results:")
        Logger.info("  Overall status: #{health_report.overall_status}")

        Enum.each(health_report.pools, fn {pool_name, pool_health} ->
          Logger.info("  Pool #{pool_name}: #{inspect(pool_health)}")
        end)

      {:error, error} ->
        Logger.error("Health check failed: #{inspect(error)}")
    end
  end

  # ==============================================================================
  # Configuration Management Example
  # ==============================================================================

  @doc """
  Demonstrate dynamic configuration management.
  """
  def configuration_example do
    alias Foundation.Bridge.Python.Config

    # Get current configuration
    case Config.get_config() do
      {:ok, config} ->
        Logger.info("Current Python Bridge Configuration:")
        Logger.info("  Enabled: #{config.enabled}")
        Logger.info("  Python path: #{config.python_path}")
        Logger.info("  Pool configs: #{inspect(Map.keys(config.pool_configs))}")

      {:error, error} ->
        Logger.error("Failed to get config: #{inspect(error)}")
    end

    # Create custom pool configuration
    custom_pool_config = %{
      size: 2,
      max_overflow: 3,
      preload_modules: ["requests", "json", "datetime"]
    }

    case Config.update_pool_config(:web_scraping, custom_pool_config) do
      :ok ->
        Logger.info("Custom pool configuration updated")

        # Create the pool with new configuration
        case Python.create_pool(:web_scraping, custom_pool_config) do
          :ok ->
            Logger.info("Custom web scraping pool created")

          {:error, error} ->
            Logger.error("Failed to create pool: #{inspect(error)}")
        end

      {:error, error} ->
        Logger.error("Failed to update pool config: #{inspect(error)}")
    end
  end

  # ==============================================================================
  # Integration Testing Helper
  # ==============================================================================

  @doc """
  Run comprehensive integration tests for Python bridge.
  """
  def run_integration_tests do
    Logger.info("Starting Python Bridge Integration Tests...")

    tests = [
      {"Basic Execution", &basic_execution_example/0},
      {"Function Calls", &function_call_examples/0},
      {"Data Analysis", &data_analysis_example/0},
      {"Machine Learning", &machine_learning_example/0},
      {"Image Processing", &image_processing_example/0},
      {"Web Scraping", &web_scraping_example/0},
      {"Async Processing", &async_processing_example/0},
      {"Error Handling", &error_handling_examples/0},
      {"Performance Monitoring", &performance_monitoring_example/0},
      {"Configuration", &configuration_example/0}
    ]

    results = Enum.map(tests, fn {test_name, test_func} ->
      Logger.info("Running test: #{test_name}")

      try do
        test_func.()
        {test_name, :passed}
      rescue
        error ->
          Logger.error("Test #{test_name} failed: #{inspect(error)}")
          {test_name, :failed}
      end
    end)

    passed = Enum.count(results, fn {_, status} -> status == :passed end)
    total = length(results)

    Logger.info("Integration Tests Completed: #{passed}/#{total} passed")

    results
  end
end

# ==============================================================================
# Production Ready Configuration
# ==============================================================================

defmodule Foundation.Bridge.Python.ProductionConfig do
  @moduledoc """
  Production-ready configuration and deployment helpers for Python Bridge.
  """

  @doc """
  Get production configuration for Python Bridge.
  """
  def production_config do
    %{
      python_path: System.get_env("PYTHON_PATH", "/usr/bin/python3"),
      pool_size: String.to_integer(System.get_env("PYTHON_POOL_SIZE", "10")),
      max_overflow: String.to_integer(System.get_env("PYTHON_MAX_OVERFLOW", "20")),
      script_dir: System.get_env("PYTHON_SCRIPT_DIR", "/app/priv/python"),
      venv_path: System.get_env("PYTHON_VENV_PATH"),
      circuit_breaker_enabled: true,
      circuit_breaker: %{
        failure_threshold: String.to_integer(System.get_env("CB_FAILURE_THRESHOLD", "10")),
        recovery_time: String.to_integer(System.get_env("CB_RECOVERY_TIME", "60000"))
      },
      health_check_interval: String.to_integer(System.get_env("HEALTH_CHECK_INTERVAL", "30000")),
      auto_restart: true,
      debug_mode: System.get_env("PYTHON_DEBUG") == "true"
    }
  end

  @doc """
  Setup Python environment for production deployment.
  """
  def setup_production_environment do
    # Ensure required directories exist
    script_dir = System.get_env("PYTHON_SCRIPT_DIR", "/app/priv/python")
    File.mkdir_p!(script_dir)

    # Validate Python installation
    python_path = System.get_env("PYTHON_PATH", "/usr/bin/python3")

    case System.cmd(python_path, ["--version"]) do
      {version_output, 0} ->
        Logger.info("Python environment ready: #{String.trim(version_output)}")
        :ok

      {error, _} ->
        Logger.error("Python not available: #{error}")
        {:error, :python_not_available}
    end
  end

  @doc """
  Generate deployment checklist for Python Bridge.
  """
  def deployment_checklist do
    [
      "✓ Python 3.8+ installed and accessible",
      "✓ Required Python packages installed (pandas, numpy, etc.)",
      "✓ Script directory configured and writable",
      "✓ Environment variables set (PYTHON_PATH, etc.)",
      "✓ Virtual environment configured (if using)",
      "✓ Circuit breaker thresholds tuned for load",
      "✓ Pool sizes configured for expected workload",
      "✓ Health check intervals appropriate for monitoring",
      "✓ Logging levels configured",
      "✓ Error tracking configured",
      "✓ Resource limits set (memory, CPU)",
      "✓ Backup/fallback procedures documented"
    ]
  end
end
