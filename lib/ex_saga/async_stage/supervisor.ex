defmodule ExSaga.AsyncStage.Supervisor do
  @moduledoc """
  """

  use DynamicSupervisor

  @doc """
  """
  @spec start_link(Supervisor.options()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, :ok, opts)
  end

  @impl DynamicSupervisor
  def init(_args) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  """
  @spec start_async_stage(Supervisor.supervisor()) :: DynamicSupervisor.on_child_start()
  def start_async_stage(supervisor) do
    DynamicSupervisor.start_child(supervisor, nil)
  end

  @doc """
  """
  @spec start_async_stages(Supervisor.supervisor()) :: [DynamicSupervisor.on_child_start()]
  def start_async_stages(supervisor) do
    DynamicSupervisor.start_child(supervisor, nil)
  end
end
