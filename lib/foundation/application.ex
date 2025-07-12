defmodule Foundation.Application do
  @moduledoc """
  Foundation Application - Ground-up Jido-native distributed ML platform.
  """
  
  use Application
  require Logger
  
  @doc """
  Start the Foundation application with Jido-native architecture.
  """
  def start(_type, _args) do
    Logger.info("Starting Foundation with Jido-native architecture")
    
    children = [
      # Foundation agents - everything is an agent
      {Foundation.Supervisor, []}
    ]
    
    opts = [strategy: :one_for_one, name: Foundation.RootSupervisor]
    Supervisor.start_link(children, opts)
  end
end