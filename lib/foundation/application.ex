defmodule Foundation.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link([Foundation.Internal.RegistryOwner],
      strategy: :one_for_one,
      name: Foundation.Supervisor
    )
  end
end
