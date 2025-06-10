# Foundation.BEAM - Deep Runtime Integration
# lib/foundation/beam.ex
defmodule Foundation.BEAM do
  @moduledoc """
  Foundation 2.0 BEAM Primitives Layer
  
  Provides deep integration with BEAM runtime for optimal performance:
  - Process ecosystems that leverage isolation
  - Message optimization for zero-copy semantics  
  - Scheduler-aware operations
  - Memory management patterns
  """
  
  defdelegate spawn_ecosystem(config), to: Foundation.BEAM.Processes
  defdelegate send_optimized(pid, message, opts \\ []), to: Foundation.BEAM.Messages
  defdelegate cpu_intensive(data, fun), to: Foundation.BEAM.Schedulers
  defdelegate optimize_memory(strategy, opts \\ []), to: Foundation.BEAM.Memory
end

# Foundation.BEAM.Processes - Revolutionary Process Ecosystems
# lib/foundation/beam/processes.ex
defmodule Foundation.BEAM.Processes do
  @moduledoc """
  Process ecosystem patterns that leverage BEAM's isolation and fault tolerance.
  
  Instead of single large processes, create coordinated ecosystems of 
  specialized processes that communicate efficiently and fail gracefully.
  """
  
  require Logger

  @doc """
  Creates a process ecosystem with coordinator and worker processes.
  
  ## Examples
  
      # Basic ecosystem
      Foundation.BEAM.Processes.spawn_ecosystem(%{
        coordinator: MyCoordinator,
        workers: {MyWorker, count: 4}
      })
      
      # Advanced ecosystem with memory isolation
      Foundation.BEAM.Processes.spawn_ecosystem(%{
        coordinator: DataCoordinator,
        workers: {DataProcessor, count: :cpu_count},
        memory_strategy: :isolated_heaps,
        distribution: :cluster_wide,
        supervision: :one_for_all
      })
  """
  def spawn_ecosystem(config) do
    validate_ecosystem_config!(config)
    
    ecosystem_id = generate_ecosystem_id()
    Logger.info("Starting process ecosystem: #{ecosystem_id}")
    
    # Start coordinator first
    coordinator_spec = build_coordinator_spec(config, ecosystem_id)
    {:ok, coordinator_pid} = start_coordinator(coordinator_spec)
    
    # Start workers based on configuration
    worker_specs = build_worker_specs(config, ecosystem_id, coordinator_pid)
    worker_pids = start_workers(worker_specs)
    
    # Create ecosystem structure
    ecosystem = %{
      id: ecosystem_id,
      coordinator: coordinator_pid,
      workers: worker_pids,
      config: config,
      started_at: :os.system_time(:millisecond),
      health_status: :healthy
    }
    
    # Register ecosystem for monitoring
    register_ecosystem(ecosystem)
    
    # Return ecosystem reference
    {:ok, ecosystem}
  end

  @doc """
  Creates a distributed process society across cluster nodes.
  """
  def create_distributed_society(society_name, config) do
    case Foundation.Distributed.available?() do
      true ->
        create_cluster_wide_society(society_name, config)
      false ->
        Logger.warning("Distributed mode not available, creating local society")
        spawn_ecosystem(config)
    end
  end

  ## Ecosystem Configuration and Validation
  
  defp validate_ecosystem_config!(config) do
    required_keys = [:coordinator, :workers]
    
    Enum.each(required_keys, fn key ->
      unless Map.has_key?(config, key) do
        raise ArgumentError, "Ecosystem config missing required key: #{key}"
      end
    end)
    
    validate_coordinator_module!(config.coordinator)
    validate_worker_config!(config.workers)
  end
  
  defp validate_coordinator_module!(module) when is_atom(module) do
    unless function_exported?(module, :start_link, 1) do
      raise ArgumentError, "Coordinator module #{module} must export start_link/1"
    end
  end
  
  defp validate_worker_config!({module, opts}) when is_atom(module) and is_list(opts) do
    unless function_exported?(module, :start_link, 1) do
      raise ArgumentError, "Worker module #{module} must export start_link/1"
    end
    
    count = Keyword.get(opts, :count, 1)
    validate_worker_count!(count)
  end
  
  defp validate_worker_count!(:cpu_count), do: :ok
  defp validate_worker_count!(:auto_scale), do: :ok
  defp validate_worker_count!(count) when is_integer(count) and count > 0, do: :ok
  defp validate_worker_count!(invalid) do
    raise ArgumentError, "Invalid worker count: #{inspect(invalid)}"
  end

  ## Memory Strategy Implementation
  
  defp build_spawn_opts(memory_strategy, role) do
    base_opts = []
    
    strategy_opts = case memory_strategy do
      :isolated_heaps ->
        # Separate heap space to prevent GC interference
        [
          {:min_heap_size, calculate_min_heap_size(role)},
          {:fullsweep_after, 10}
        ]
      
      :shared_binaries ->
        # Optimize for sharing large binaries
        [
          {:min_bin_vheap_size, 46368}
        ]
      
      :frequent_gc ->
        # For short-lived, high-allocation processes
        [
          {:fullsweep_after, 5},
          {:min_heap_size, 100}
        ]
      
      :low_latency ->
        # Minimize GC pause times
        [
          {:fullsweep_after, 20},
          {:min_heap_size, 2000}
        ]
      
      :default ->
        []
    end
    
    base_opts ++ strategy_opts
  end
  
  defp calculate_min_heap_size(:coordinator), do: 1000
  defp calculate_min_heap_size(:worker), do: 500

  # Stub implementations
  defp build_coordinator_spec(config, ecosystem_id) do
    memory_strategy = Map.get(config, :memory_strategy, :default)
    spawn_opts = build_spawn_opts(memory_strategy, :coordinator)
    
    %{
      module: config.coordinator,
      ecosystem_id: ecosystem_id,
      spawn_opts: spawn_opts,
      config: config
    }
  end

  defp start_coordinator(_spec), do: {:ok, spawn(fn -> :timer.sleep(:infinity) end)}
  defp build_worker_specs(_config, _ecosystem_id, _coordinator_pid), do: []
  defp start_workers(_worker_specs), do: []
  defp register_ecosystem(_ecosystem), do: :ok
  defp generate_ecosystem_id(), do: "ecosystem_#{:crypto.strong_rand_bytes(8) |> Base.encode64()}"
  defp create_cluster_wide_society(_society_name, config), do: spawn_ecosystem(config)
end

# Foundation.BEAM.Messages - Zero-Copy Message Optimization  
# lib/foundation/beam/messages.ex
defmodule Foundation.BEAM.Messages do
  @moduledoc """
  Optimized message passing that minimizes copying for large data structures.
  
  Leverages BEAM's binary reference counting and process heap isolation
  to achieve zero-copy semantics where possible.
  """
  
  require Logger

  @doc """
  Sends a message with optimal copying strategy based on data characteristics.
  
  ## Strategies:
  - `:direct` - Standard message passing (fastest for small data)
  - `:ets_reference` - Store in ETS, send reference (best for large data)
  - `:binary_sharing` - Convert to ref-counted binary (best for frequent sharing)
  - `:flow_controlled` - Use flow control with backpressure
  """
  def send_optimized(pid, data, opts \\ []) do
    strategy = determine_optimal_strategy(data, opts)
    
    case strategy do
      :direct ->
        send_direct(pid, data, opts)
      :ets_reference ->
        send_via_ets_reference(pid, data, opts)
      :binary_sharing ->
        send_via_binary_sharing(pid, data, opts)
      :flow_controlled ->
        send_with_flow_control(pid, data, opts)
    end
  end

  @doc """
  Sends a message with explicit flow control and backpressure handling.
  """
  def send_with_backpressure(pid, data, opts \\ []) do
    max_queue_size = Keyword.get(opts, :max_queue_size, 1000)
    
    case check_process_queue_size(pid) do
      queue_size when queue_size < max_queue_size ->
        send_optimized(pid, data, opts)
      queue_size ->
        Logger.warning("Process #{inspect(pid)} queue size #{queue_size} exceeds limit #{max_queue_size}")
        handle_backpressure(pid, data, opts)
    end
  end

  ## Strategy Determination
  
  defp determine_optimal_strategy(data, opts) do
    forced_strategy = Keyword.get(opts, :strategy)
    if forced_strategy, do: forced_strategy, else: analyze_data_for_strategy(data, opts)
  end
  
  defp analyze_data_for_strategy(data, opts) do
    data_size = estimate_data_size(data)
    frequency = Keyword.get(opts, :frequency, :once)
    priority = Keyword.get(opts, :priority, :normal)
    
    cond do
      data_size < 1024 and priority == :high ->
        :direct
      
      data_size > 10_240 ->
        :ets_reference
      
      frequency in [:frequent, :continuous] ->
        :binary_sharing
      
      Keyword.get(opts, :flow_control) ->
        :flow_controlled
      
      data_size > 1024 ->
        :binary_sharing
      
      true ->
        :direct
    end
  end

  ## Direct Message Passing
  
  defp send_direct(pid, data, opts) do
    priority = Keyword.get(opts, :priority, :normal)
    
    case priority do
      :high ->
        # Use erlang:send with higher priority
        :erlang.send(pid, data, [:noconnect, :nosuspend])
      _ ->
        send(pid, data)
    end
  end

  ## ETS Reference Strategy
  
  defp send_via_ets_reference(pid, data, opts) do
    table_name = get_or_create_message_table()
    ref = make_ref()
    ttl = Keyword.get(opts, :ttl, 60_000)  # 1 minute default
    
    # Store data in ETS with TTL
    :ets.insert(table_name, {ref, data, :os.system_time(:millisecond) + ttl})
    
    # Send reference instead of data
    send(pid, {:ets_ref, ref, table_name})
    
    # Schedule cleanup
    schedule_cleanup(ref, table_name, ttl)
    
    {:ok, ref}
  end

  ## Binary Sharing Strategy
  
  defp send_via_binary_sharing(pid, data, opts) do
    # Convert to binary for ref-counted sharing
    compression_level = Keyword.get(opts, :compression, :default)
    
    optimized_binary = case compression_level do
      :high ->
        :erlang.term_to_binary(data, [compressed, {:compressed, 9}])
      :low ->
        :erlang.term_to_binary(data, [compressed, {:compressed, 1}])
      :default ->
        :erlang.term_to_binary(data, [:compressed])
    end
    
    # Send binary instead of term (allows ref-counting)
    send(pid, {:shared_binary, optimized_binary})
    
    {:ok, byte_size(optimized_binary)}
  end

  ## Flow Control Implementation
  
  defp send_with_flow_control(pid, data, opts) do
    max_retries = Keyword.get(opts, :max_retries, 3)
    retry_delay = Keyword.get(opts, :retry_delay, 100)
    
    case attempt_send_with_retries(pid, data, opts, max_retries, retry_delay) do
      :ok ->
        {:ok, :sent}
      {:error, reason} ->
        {:error, {:flow_control_failed, reason}}
    end
  end
  
  defp attempt_send_with_retries(pid, data, opts, retries_left, retry_delay) do
    case check_process_queue_size(pid) do
      queue_size when queue_size < 1000 ->
        send_optimized(pid, data, Keyword.put(opts, :strategy, :direct))
        :ok
      
      _queue_size when retries_left > 0 ->
        :timer.sleep(retry_delay)
        attempt_send_with_retries(pid, data, opts, retries_left - 1, retry_delay * 2)
      
      queue_size ->
        {:error, {:queue_full, queue_size}}
    end
  end

  ## Utility Functions
  
  defp check_process_queue_size(pid) do
    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, size} -> size
      nil -> :infinity  # Process dead
    end
  end
  
  defp handle_backpressure(pid, _data, opts) do
    strategy = Keyword.get(opts, :backpressure_strategy, :drop)
    
    case strategy do
      :drop ->
        Logger.warning("Dropping message due to backpressure")
        {:dropped, :backpressure}
      
      :queue ->
        # Would queue in external buffer
        {:queued, :backpressure}
      
      :redirect ->
        # Would find alternative process
        {:dropped, :no_alternative}
    end
  end
  
  defp estimate_data_size(data) do
    case data do
      data when is_binary(data) ->
        byte_size(data)
      
      data when is_list(data) ->
        length = length(data)
        sample_size = if length > 0, do: estimate_data_size(hd(data)), else: 0
        length * sample_size
      
      data when is_map(data) ->
        map_size(data) * 100  # Rough estimate
      
      data when is_tuple(data) ->
        tuple_size(data) * 50  # Rough estimate
      
      _other ->
        1000  # Conservative estimate
    end
  end
  
  defp get_or_create_message_table() do
    table_name = :foundation_message_cache
    
    case :ets.whereis(table_name) do
      :undefined ->
        :ets.new(table_name, [:set, :public, :named_table])
        table_name
      _tid ->
        table_name
    end
  end
  
  defp schedule_cleanup(ref, table_name, ttl) do
    spawn(fn ->
      :timer.sleep(ttl)
      :ets.delete(table_name, ref)
    end)
  end
end

# Foundation.BEAM.Schedulers - Reduction-Aware Operations
# lib/foundation/beam/schedulers.ex
defmodule Foundation.BEAM.Schedulers do
  @moduledoc """
  Scheduler-aware operations that cooperate with BEAM's preemptive scheduling.
  
  Provides utilities for CPU-intensive operations that yield appropriately
  to maintain system responsiveness.
  """
  
  require Logger

  @doc """
  Executes CPU-intensive operations while yielding to scheduler.
  
  ## Examples
  
      # Process large dataset cooperatively
      Foundation.BEAM.Schedulers.cpu_intensive(large_dataset, fn data ->
        Enum.map(data, &complex_transformation/1)
      end)
      
      # With custom reduction limit
      Foundation.BEAM.Schedulers.cpu_intensive(data, fn data ->
        process_data(data)
      end, reduction_limit: 4000)
  """
  def cpu_intensive(data, fun, opts \\ []) do
    reduction_limit = Keyword.get(opts, :reduction_limit, 2000)
    chunk_size = Keyword.get(opts, :chunk_size, :auto)
    
    case chunk_size do
      :auto ->
        auto_chunked_processing(data, fun, reduction_limit)
      size when is_integer(size) ->
        manual_chunked_processing(data, fun, size, reduction_limit)
    end
  end

  @doc """
  Monitors scheduler utilization across all schedulers.
  """
  def get_scheduler_utilization() do
    scheduler_count = :erlang.system_info(:schedulers_online)
    
    utilizations = for scheduler_id <- 1..scheduler_count do
      {scheduler_id, get_single_scheduler_utilization(scheduler_id)}
    end
    
    average_utilization = 
      utilizations
      |> Enum.map(fn {_id, util} -> util end)
      |> Enum.sum()
      |> Kernel./(scheduler_count)
    
    %{
      individual: utilizations,
      average: average_utilization,
      scheduler_count: scheduler_count
    }
  end

  @doc """
  Balances work across schedulers by pinning processes appropriately.
  """
  def balance_work_across_schedulers(work_items, worker_fun) do
    scheduler_count = :erlang.system_info(:schedulers_online)
    chunks = chunk_work_by_schedulers(work_items, scheduler_count)
    
    tasks = for {chunk, scheduler_id} <- Enum.with_index(chunks, 1) do
      Task.async(fn ->
        # Pin this process to specific scheduler
        :erlang.process_flag(:scheduler, scheduler_id)
        
        Enum.map(chunk, fn item ->
          worker_fun.(item)
        end)
      end)
    end
    
    # Collect results
    results = Task.await_many(tasks, 60_000)
    List.flatten(results)
  end

  ## Auto-Chunked Processing
  
  defp auto_chunked_processing(data, fun, reduction_limit) when is_list(data) do
    chunk_size = calculate_optimal_chunk_size(data, reduction_limit)
    manual_chunked_processing(data, fun, chunk_size, reduction_limit)
  end
  
  defp auto_chunked_processing(data, fun, reduction_limit) do
    # For non-list data, process with periodic yielding
    process_with_periodic_yielding(data, fun, reduction_limit)
  end

  ## Manual Chunked Processing
  
  defp manual_chunked_processing(data, fun, chunk_size, reduction_limit) when is_list(data) do
    data
    |> Enum.chunk_every(chunk_size)
    |> Enum.reduce([], fn chunk, acc ->
      # Process chunk
      chunk_result = fun.(chunk)
      
      # Check if we should yield
      case should_yield?(reduction_limit) do
        true ->
          :erlang.yield()
        false ->
          :ok
      end
      
      [chunk_result | acc]
    end)
    |> Enum.reverse()
    |> List.flatten()
  end

  ## Reduction Management
  
  defp should_yield?(reduction_limit) do
    get_current_reductions() > reduction_limit
  end
  
  defp get_current_reductions() do
    case Process.info(self(), :reductions) do
      {:reductions, count} -> count
      nil -> 0
    end
  end
  
  defp calculate_optimal_chunk_size(data, reduction_limit) do
    data_size = length(data)
    estimated_reductions_per_item = 10  # Conservative estimate
    
    max(1, div(reduction_limit, estimated_reductions_per_item))
  end

  # Utility functions
  defp process_with_periodic_yielding(data, fun, _reduction_limit) do
    fun.(data)
  end
  
  defp get_single_scheduler_utilization(_scheduler_id) do
    # Simplified implementation - would use actual scheduler stats
    :rand.uniform(100) / 100
  end
  
  defp chunk_work_by_schedulers(work_items, scheduler_count) do
    chunk_size = div(length(work_items), scheduler_count)
    Enum.chunk_every(work_items, max(1, chunk_size))
  end
end

# Foundation.BEAM.Memory - Intelligent Memory Management
# lib/foundation/beam/memory.ex
defmodule Foundation.BEAM.Memory do
  @moduledoc """
  Memory management patterns optimized for BEAM's garbage collector.
  
  Provides utilities for:
  - Binary optimization and ref-counting
  - Atom table safety
  - GC isolation patterns
  - Memory pressure monitoring
  """
  
  require Logger

  @doc """
  Optimizes binary data handling to minimize copying and maximize ref-counting.
  """
  def optimize_binary(binary_data, strategy \\ :automatic) when is_binary(binary_data) do
    case strategy do
      :automatic ->
        choose_binary_strategy(binary_data)
      :sharing ->
        optimize_for_sharing(binary_data)
      :storage ->
        optimize_for_storage(binary_data)
      :transmission ->
        optimize_for_transmission(binary_data)
    end
  end

  @doc """
  Safely creates atoms with table exhaustion protection.
  """
  def safe_atom(string, opts \\ []) when is_binary(string) do
    max_atoms = Keyword.get(opts, :max_atoms, 800_000)  # Conservative limit
    current_atom_count = :erlang.system_info(:atom_count)
    
    if current_atom_count < max_atoms do
      try do
        {:ok, String.to_atom(string)}
      rescue
        ArgumentError ->
          {:error, :invalid_atom}
        SystemLimitError ->
          {:error, :atom_table_full}
      end
    else
      Logger.warning("Atom table approaching limit: #{current_atom_count}/#{max_atoms}")
      {:error, :atom_table_nearly_full}
    end
  end

  @doc """
  Monitors memory usage and provides recommendations.
  """
  def analyze_memory_usage() do
    memory_info = :erlang.memory()
    
    analysis = %{
      total_memory: memory_info[:total],
      process_memory: memory_info[:processes],
      atom_memory: memory_info[:atom],
      binary_memory: memory_info[:binary],
      code_memory: memory_info[:code],
      ets_memory: memory_info[:ets],
      
      # Calculated metrics
      process_memory_percentage: memory_info[:processes] / memory_info[:total] * 100,
      binary_memory_percentage: memory_info[:binary] / memory_info[:total] * 100,
      atom_count: :erlang.system_info(:atom_count),
      atom_limit: :erlang.system_info(:atom_limit),
      
      # Process-specific info
      process_count: :erlang.system_info(:process_count),
      process_limit: :erlang.system_info(:process_limit),
      
      # Recommendations
      recommendations: generate_memory_recommendations(memory_info)
    }
    
    analysis
  end

  ## Binary Optimization Strategies
  
  defp choose_binary_strategy(binary_data) do
    size = byte_size(binary_data)
    
    cond do
      size < 64 ->
        # Small binaries - keep as heap binaries
        {:heap_binary, binary_data}
      
      size < 65536 ->
        # Medium binaries - optimize for ref-counting
        optimize_for_sharing(binary_data)
      
      true ->
        # Large binaries - optimize for storage/transmission
        optimize_for_storage(binary_data)
    end
  end
  
  defp optimize_for_sharing(binary_data) do
    # Ensure binary is refc (not heap) for sharing
    if :erlang.binary_part(binary_data, 0, 0) == <<>> do
      {:refc_binary, binary_data}
    else
      # Convert to refc binary
      refc_binary = :binary.copy(binary_data)
      {:refc_binary, refc_binary}
    end
  end
  
  defp optimize_for_storage(binary_data) do
    # Compress for storage
    compressed = :zlib.compress(binary_data)
    compression_ratio = byte_size(compressed) / byte_size(binary_data)
    
    if compression_ratio < 0.9 do
      {:compressed_binary, compressed}
    else
      # Compression not beneficial
      optimize_for_sharing(binary_data)
    end
  end
  
  defp optimize_for_transmission(binary_data) do
    # Optimize for network transmission
    compressed = :zlib.compress(binary_data)
    {:transmission_ready, compressed}
  end

  ## Memory Analysis and Recommendations
  
  defp generate_memory_recommendations(memory_info) do
    recommendations = []
    
    # Check atom usage
    atom_percentage = :erlang.system_info(:atom_count) / :erlang.system_info(:atom_limit) * 100
    recommendations = if atom_percentage > 80 do
      ["Atom table usage high (#{trunc(atom_percentage)}%) - review dynamic atom creation" | recommendations]
    else
      recommendations
    end
    
    # Check binary memory
    binary_percentage = memory_info[:binary] / memory_info[:total] * 100
    recommendations = if binary_percentage > 40 do
      ["Binary memory high (#{trunc(binary_percentage)}%) - consider binary optimization" | recommendations]
    else
      recommendations
    end
    
    # Check process memory
    process_percentage = memory_info[:processes] / memory_info[:total] * 100
    recommendations = if process_percentage > 60 do
      ["Process memory high (#{trunc(process_percentage)}%) - review process count and heap sizes" | recommendations]
    else
      recommendations
    end
    
    recommendations
  end
end
