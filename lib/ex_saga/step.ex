defmodule ExSaga.Step do
  @moduledoc """
  """

  alias ExSaga.{DryRun, Stepable}

  @typedoc """
  """
  @type breakpoint_fun :: (Event.t, Stepable.t -> boolean)

  @typedoc """
  """
  @type breakpoint :: breakpoint_fun | {:before | :after, breakpoint_fun}

  @typedoc """
  """
  @type opt ::
    Stepable.opt |
    {:subscribers, [Process.dest]} |
    {:breakpoints, breakpoint_fun | [breakpoint_fun]}

  @typedoc """
  """
  @type opts :: [opt]

  @typedoc """
  """
  @type mstep_result :: {Stepable.stage_result | Stepable.step_result, [Event.t]}

  @doc """
  """
  @spec step(Stepable.t, Event.t, Stepable.opts) :: Stepable.stage_result | Stepable.step_result
  def step(stepable, event, opts \\ []) do
    Stepable.step(stepable, event, opts)
  end

  @doc """
  """
  @spec step_from(Stepable.t, Stepable.stage_result, Stepable.opts) :: Stepable.step_result
  def step_from(stepable, stage_result, opts \\ []) do
    Stepable.step_from(stepable, stage_result, opts)
  end

  @doc """
  """
  @spec mstep_from(Stepable.t | module, Stepable.stage_result, opts) :: mstep_result
  def mstep_from(stepable, stage_result, opts \\ [])
  def mstep_from(stepable, stage_result, opts) when is_atom(stepable) do
    stepable.create()
    |> mstep_from(stage_result, opts)
  end
  def mstep_from(stepable, stage_result, opts) do
    result = step_from(stepable, stage_result, opts)
    mstep(result, opts)
  end

  @doc """
  """
  @spec mstep_at(Stepable.t, Event.t, opts) :: mstep_result
  def mstep_at(stepable, event, opts \\ []) do
    mstep({:continue, event, stepable}, opts)
  end

  @doc """
  """
  @spec mstep(Stepable.stage_result | Stepable.step_result, opts, [Event.t]) :: mstep_result
  def mstep(result, opts, events \\ [])
  def mstep({:continue, nil, _stepable} = result, _opts, events) do
    {result, Enum.reverse(events)}
  end
  def mstep({:continue, event, stepable} = result, opts, events) do
    if break?(stepable, event, opts) do
      {result, Enum.reverse([event|events])}
    else
      step_result = step(stepable, event, opts)
      _ = Keyword.get(opts, :subscribers, [])
      |> publish(step_result)

      mstep(step_result, opts, [event|events])
    end
  end
  def mstep(result, _opts, events) do
    {result, Enum.reverse(events)}
  end

  @doc """
  """
  @spec break?(Stepable.t, Event.t, opts) :: boolean
  def break?(stepable, event, opts) do
    timeout = Keyword.get(opts, :timeout, :infinity)
    breakpoints = Keyword.get(opts, :breakpoints, [])
    break?(breakpoints, stepable, event, timeout)
  end

  @doc """
  """
  @spec break?([breakpoint_fun] | breakpoint_fun, Steable.t, Event.t, timeout) :: boolean
  def break?([], _stepable, _event, _timeout), do: false
  def break?([bp|bps], stepable, event, timeout) do
    case DryRun.execute(bp, [], timeout) do
      true -> true
      _ -> break?(bps, stepable, event, timeout)
    end
  end
  def break?(breakpoint, stepable, event, timeout) do
    break?([breakpoint], stepable, event, timeout)
  end

  @doc false
  @spec publish([Process.dest], Stepable.stage_result | Stepable.step_result) :: :ok
  def publish([], _step_result), do: :ok
  def publish([sub|subs], step_result) do
    _ = send(sub, {:step, ExSaga, self(), step_result})
    publish(subs, step_result)
  end
end
