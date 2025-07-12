defmodule Foundation.Cache do
  @moduledoc """
  Convenience module for caching functionality.

  Delegates to Foundation.Infrastructure.Cache.
  """

  defdelegate get(key, default \\ nil, opts \\ []), to: Foundation.Infrastructure.Cache
  defdelegate put(key, value, opts \\ []), to: Foundation.Infrastructure.Cache
  defdelegate delete(key, opts \\ []), to: Foundation.Infrastructure.Cache
  defdelegate clear(opts \\ []), to: Foundation.Infrastructure.Cache
end
