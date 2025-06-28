defmodule Foundation.ConfigValidator do
  @moduledoc """
  Configuration validation for Foundation Protocol Platform.

  Validates that required implementations are properly configured and
  meet protocol requirements before application startup.
  """

  require Logger

  @doc """
  Validates the current Foundation configuration.

  ## Returns
  - `:ok` if configuration is valid
  - `{:error, reasons}` if configuration has issues

  ## Examples
      case Foundation.ConfigValidator.validate() do
        :ok -> :continue_startup
        {:error, reasons} -> {:halt_startup, reasons}
      end
  """
  @spec validate() :: :ok | {:error, list()}
  def validate do
    validations = [
      &validate_registry_impl/0,
      &validate_coordination_impl/0,
      &validate_infrastructure_impl/0,
      &validate_protocol_versions/0
    ]

    errors =
      validations
      |> Enum.map(& &1.())
      |> Enum.filter(&(&1 != :ok))
      |> Enum.map(fn {:error, reason} -> reason end)

    if Enum.empty?(errors) do
      :ok
    else
      {:error, errors}
    end
  end

  @doc """
  Validates and logs configuration issues at application startup.

  Returns `:ok` always but logs warnings for configuration issues.
  """
  @spec validate_and_log() :: :ok
  def validate_and_log do
    case validate() do
      :ok ->
        Logger.info("Foundation configuration validation passed")
        :ok

      {:error, errors} ->
        Logger.warning("Foundation configuration has issues:")

        Enum.each(errors, fn error ->
          Logger.warning("  - #{error}")
        end)

        :ok
    end
  end

  # --- Private Validation Functions ---

  defp validate_registry_impl do
    case Application.get_env(:foundation, :registry_impl) do
      nil ->
        {:error, "No registry implementation configured"}

      impl when is_atom(impl) ->
        validate_implementation_exists(impl, Foundation.Registry)

      impl ->
        {:error, "Registry implementation must be an atom, got: #{inspect(impl)}"}
    end
  end

  defp validate_coordination_impl do
    case Application.get_env(:foundation, :coordination_impl) do
      nil ->
        # Coordination is optional
        :ok

      impl when is_atom(impl) ->
        validate_implementation_exists(impl, Foundation.Coordination)

      impl ->
        {:error, "Coordination implementation must be an atom, got: #{inspect(impl)}"}
    end
  end

  defp validate_infrastructure_impl do
    case Application.get_env(:foundation, :infrastructure_impl) do
      nil ->
        # Infrastructure is optional
        :ok

      impl when is_atom(impl) ->
        validate_implementation_exists(impl, Foundation.Infrastructure)

      impl ->
        {:error, "Infrastructure implementation must be an atom, got: #{inspect(impl)}"}
    end
  end

  defp validate_implementation_exists(impl_module, protocol) do
    if Code.ensure_loaded?(impl_module) do
      # Check if the module implements the protocol
      if protocol_implemented?(impl_module, protocol) do
        :ok
      else
        {:error, "Module #{impl_module} does not implement #{protocol} protocol"}
      end
    else
      {:error, "Implementation module #{impl_module} cannot be loaded"}
    end
  end

  defp protocol_implemented?(module, protocol) do
    # Check if the protocol implementation exists
    impl_module = Module.concat([protocol, module])
    Code.ensure_loaded?(impl_module)
  end

  defp validate_protocol_versions do
    case Foundation.protocol_versions() do
      %{registry: {:ok, _version}} ->
        :ok

      %{registry: {:error, reason}} ->
        {:error, "Registry protocol version check failed: #{inspect(reason)}"}
    end
  rescue
    error ->
      {:error, "Protocol version validation failed: #{Exception.message(error)}"}
  end
end
