defmodule ExSaga.AsyncStage.Supervisor do
  @moduledoc """
  """

  use DynamicSupervisor
  alias ExSaga.{AsyncStage, Stepable}

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
  @spec start_async_stage(
          Supervisor.supervisor(),
          Stepable.t(),
          Stepable.stage_result(),
          Stepable.opts(),
          AsyncStage.Server.options()
        ) :: DynamicSupervisor.on_start_child()
  def start_async_stage(supervisor, stepable, result, step_opts \\ [], opts \\ []) do
    DynamicSupervisor.start_child(supervisor, {AsyncStage.Server, [stepable, result, step_opts, opts]})
  end

  @doc """
  """
  @spec start_async_stages(Supervisor.supervisor(), [
          {Stepable.t(), Stepable.stage_result(), Stepable.opts(), AsyncStage.Server.options()}
        ]) :: [DynamicSupervisor.on_start_child()]
  def start_async_stages(_supervisor, []), do: []

  def start_async_stages(supervisor, [{stepable, result, step_opts, opts} | stages]) do
    resp = DynamicSupervisor.start_child(supervisor, {AsyncStage.Server, [stepable, result, step_opts, opts]})
    [resp | start_async_stages(supervisor, stages)]
  end
end
