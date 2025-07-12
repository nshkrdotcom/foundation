defmodule Foundation.CQRS do
  @moduledoc """
  Command Query Responsibility Segregation (CQRS) pattern for Foundation.

  This module provides abstractions for separating read and write operations,
  helping to clarify intent and optimize for different access patterns.

  ## Design Philosophy

  - **Commands**: Change state, don't return data (except IDs/status)
  - **Queries**: Return data, don't change state
  - **Clear Intent**: Operations explicitly marked as commands or queries
  - **Optimization**: Different strategies for reads vs writes

  ## Usage

      defmodule MyApp.Users do
        use Foundation.CQRS

        # Define a command
        defcommand CreateUser do
          @fields [:name, :email]
          @validations [
            name: [required: true, type: :string],
            email: [required: true, format: ~r/@/]
          ]

          def execute(params) do
            with {:ok, valid_params} <- validate(params),
                 {:ok, user} <- UserRepository.insert(valid_params) do
              {:ok, user.id}
            end
          end
        end

        # Define a query
        defquery GetUserByEmail do
          @fields [:email]
          
          def execute(%{email: email}) do
            UserRepository.find_by_email(email)
          end
        end
      end

      # Usage
      {:ok, user_id} = MyApp.Users.CreateUser.dispatch(%{name: "John", email: "john@example.com"})
      {:ok, user} = MyApp.Users.GetUserByEmail.fetch(%{email: "john@example.com"})
  """

  defmacro __using__(_opts) do
    quote do
      import Foundation.CQRS
    end
  end

  @doc """
  Defines a command module.

  Commands change state and typically return only success/failure
  with minimal data (like created IDs).
  """
  defmacro defcommand(name, do: block) do
    quote do
      defmodule unquote(name) do
        use Foundation.CQRS.Command
        unquote(block)
      end
    end
  end

  @doc """
  Defines a query module.

  Queries retrieve data without changing state.
  """
  defmacro defquery(name, do: block) do
    quote do
      defmodule unquote(name) do
        use Foundation.CQRS.Query
        unquote(block)
      end
    end
  end
end

defmodule Foundation.CQRS.Command do
  @moduledoc """
  Base behaviour for CQRS commands.

  Commands are responsible for changing system state.
  """

  @callback execute(params :: map()) :: {:ok, term()} | {:error, term()}

  defmacro __using__(_opts) do
    quote do
      @behaviour Foundation.CQRS.Command

      Module.register_attribute(__MODULE__, :fields, accumulate: false)
      Module.register_attribute(__MODULE__, :validations, accumulate: false)

      @doc """
      Dispatches the command with the given parameters.

      This is the main entry point for command execution.
      """
      @spec dispatch(map()) :: {:ok, term()} | {:error, term()}
      def dispatch(params) do
        start_time = System.monotonic_time(:microsecond)

        # Log command execution
        Foundation.EventSystem.emit(:metric, [:cqrs, :command, :started], %{
          command: __MODULE__,
          params: sanitize_params(params)
        })

        # Execute command
        result = execute(params)

        # Log result
        duration = System.monotonic_time(:microsecond) - start_time

        Foundation.EventSystem.emit(:metric, [:cqrs, :command, :completed], %{
          command: __MODULE__,
          duration: duration,
          success: match?({:ok, _}, result)
        })

        result
      end

      @doc """
      Validates command parameters.
      """
      @spec validate(map()) :: {:ok, map()} | {:error, term()}
      def validate(params) do
        validations = @validations || []

        Enum.reduce_while(validations, {:ok, params}, fn {field, rules}, {:ok, acc} ->
          case validate_field(params, field, rules) do
            :ok -> {:cont, {:ok, acc}}
            {:error, reason} -> {:halt, {:error, {field, reason}}}
          end
        end)
      end

      defp validate_field(params, field, rules) do
        value = Map.get(params, field)

        Enum.reduce_while(rules, :ok, fn
          {:required, true}, :ok when is_nil(value) ->
            {:halt, {:error, :required}}

          {:type, expected_type}, :ok ->
            if type_matches?(value, expected_type) do
              {:cont, :ok}
            else
              {:halt, {:error, {:invalid_type, expected_type}}}
            end

          {:format, regex}, :ok when is_binary(value) ->
            if Regex.match?(regex, value) do
              {:cont, :ok}
            else
              {:halt, {:error, {:invalid_format, inspect(regex)}}}
            end

          _, :ok ->
            {:cont, :ok}
        end)
      end

      defp type_matches?(value, :string), do: is_binary(value)
      defp type_matches?(value, :integer), do: is_integer(value)
      defp type_matches?(value, :float), do: is_float(value)
      defp type_matches?(value, :boolean), do: is_boolean(value)
      defp type_matches?(value, :atom), do: is_atom(value)
      defp type_matches?(value, :map), do: is_map(value)
      defp type_matches?(value, :list), do: is_list(value)
      defp type_matches?(_, _), do: false

      defp sanitize_params(params) do
        # Remove sensitive data from params for logging
        Map.drop(params, [:password, :token, :secret])
      end

      defoverridable validate: 1, sanitize_params: 1
    end
  end
end

defmodule Foundation.CQRS.Query do
  @moduledoc """
  Base behaviour for CQRS queries.

  Queries are responsible for retrieving data without side effects.
  """

  @callback execute(params :: map()) :: {:ok, term()} | {:error, term()}

  defmacro __using__(_opts) do
    quote do
      @behaviour Foundation.CQRS.Query

      Module.register_attribute(__MODULE__, :fields, accumulate: false)
      Module.register_attribute(__MODULE__, :cache_ttl, accumulate: false)

      @doc """
      Fetches data using the query with given parameters.

      This is the main entry point for query execution.
      """
      @spec fetch(map()) :: {:ok, term()} | {:error, term()}
      def fetch(params) do
        start_time = System.monotonic_time(:microsecond)

        # Check cache if enabled
        cache_key = cache_key(params)

        result =
          case get_from_cache(cache_key) do
            {:ok, cached} ->
              {:ok, cached}

            :miss ->
              # Execute query
              execute(params)
          end

        # Log query execution
        duration = System.monotonic_time(:microsecond) - start_time

        Foundation.EventSystem.emit(:metric, [:cqrs, :query, :executed], %{
          query: __MODULE__,
          duration: duration,
          cache_hit: match?({:ok, _}, get_from_cache(cache_key))
        })

        # Cache result if successful and caching is enabled
        case result do
          {:ok, data} ->
            maybe_cache(cache_key, data)
            {:ok, data}

          error ->
            error
        end
      end

      defp cache_key(params) do
        {@__MODULE__, params}
      end

      defp get_from_cache(_key) do
        # Override to implement caching
        :miss
      end

      defp maybe_cache(_key, _data) do
        # Override to implement caching
        :ok
      end

      defoverridable cache_key: 1, get_from_cache: 1, maybe_cache: 2
    end
  end
end
