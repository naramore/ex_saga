defmodule ExSaga.AsyncStage.Server do
  @moduledoc """
  """

  use GenServer
  alias ExSaga.{Event, Step, Stepable}
  alias ExSaga.AsyncStage.Breaker

  @typedoc """
  """
  @type stepper :: :step | :mstep

  @typedoc """
  """
  @type options :: [
          GenServer.option()
          | {:stepper, stepper}
        ]

  @doc """
  """
  @spec start_link(Stepable.t(), Stepable.stage_result(), Step.opts(), options) :: GenServer.on_start()
  def start_link(stepable, stage_result, step_opts \\ [], opts \\ []) do
    {stepper, opts} = Keyword.get(opts, :stepper, :mstep)
    GenServer.start_link(__MODULE__, {stepper, stepable, stage_result, step_opts}, opts)
  end

  @doc """
  """
  @spec stop(GenServer.server(), reason :: term, timeout) :: :ok
  def stop(server, reason \\ :normal, timeout \\ :infinity) do
    GenServer.stop(server, reason, timeout)
  end

  @doc """
  """
  @spec pause(Stage.full_name(), timeout) :: :ok
  def pause(name, timeout \\ 5000) do
    Breaker.break(Breaker, name, timeout)
  end

  @doc """
  """
  @spec resume(GenServer.server(), stepper | nil) :: :ok
  def resume(server, stepper \\ nil) do
    GenServer.cast(server, {:resume, stepper})
  end

  @doc """
  """
  @spec step(GenServer.server(), Stepable.t(), Event.t(), Stepable.opts()) :: :ok
  def step(server, event, stepable, opts \\ []) do
    GenServer.cast(server, {:step, stepable, event, opts})
  end

  @doc """
  """
  @spec mstep(GenServer.server(), Stepable.t(), Event.t(), Step.opts()) :: :ok
  def mstep(server, stepable, event, opts \\ []) do
    GenServer.cast(server, {:mstep, stepable, event, opts})
  end

  @doc """
  """
  @spec yield(GenServer.server(), timeout) :: Stepable.stage_result() | Stepable.step_result()
  def yield(server, timeout \\ 5000) do
    GenServer.call(server, :yield, timeout)
  end

  @impl GenServer
  def init({stepper, stepable, stage_result, opts}) do
    state = %{
      stepper: stepper,
      opts: opts,
      result: nil
    }

    {:ok, state, {:continue, {stepable, stage_result, opts}}}
  end

  @impl GenServer
  def handle_continue({stepable, result, opts}, %{stepper: :mstep} = state) do
    result = Step.mstep_from(stepable, result, add_async_breakpoint(opts))
    {:noreply, %{state | result: result}}
  end

  def handle_continue({stepable, result, opts}, %{stepper: :step} = state) do
    result = Step.step_from(stepable, result, opts)
    {:noreply, %{state | result: result}}
  end

  @impl GenServer
  def handle_cast({:resume, nil}, state) do
    %{stepper: stepper} = state
    handle_cast({:resume, stepper}, state)
  end

  def handle_cast({:resume, stepper}, %{result: {:continue, event, stepable}} = state) do
    opts = Map.get(state, :opts, [])
    _ = Breaker.reset(Breaker, Keyword.get(opts, :parent_full_name, []))
    result = run(stepper, stepable, event, opts)
    {:noreply, {:noreply, %{state | result: result, stepper: :mstep}}}
  end

  def handle_cast({stepper, stepable, event, opts}, state) do
    result = run(stepper, stepable, event, opts)
    {:noreply, %{state | result: result, opts: opts, stepper: stepper}}
  end

  def handle_cast(_request, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:yield, _from, state) do
    {:reply, Map.get(state, :result), state}
  end

  def handle_call(_request, _from, state) do
    {:reply, {:error, :unhandled}, state}
  end

  @impl GenServer
  def handle_info(_request, state) do
    {:noreply, state}
  end

  @doc false
  @spec run(stepper, Stepable.t(), Event.t(), Step.opts()) :: Stepable.step_result() | Stepable.stage_result()
  defp run(:mstep, stepable, event, opts) do
    Step.mstep(stepable, event, add_async_breakpoint(opts))
  end

  defp run(:step, stepable, event, opts) do
    Step.step(stepable, event, opts)
  end

  @doc false
  @spec add_async_breakpoint(Step.opts()) :: Step.opts()
  defp add_async_breakpoint(opts) do
    breakpoints = Keyword.get(opts, :breakpoints, [])
    async_breakpoint = Breaker.breakpoint(Breaker, Keyword.get(opts, :parent_full_name, []))
    Keyword.put(opts, :breakpoints, [async_breakpoint | breakpoints])
  end
end
