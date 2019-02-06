defmodule ExSaga.Stage do
  @moduledoc """
  """

  use ExSaga.Stepper, compensation_event_name: [:starting, :compensation]
  alias ExSaga.{DryRun, Event, Hook, Retry, State, Stepable, Utils}

  @typedoc """
  """
  @type id :: term

  @typedoc """
  """
  @type name :: atom

  @typedoc """
  """
  @type full_name :: [name, ...]

  @typedoc """
  """
  @type effect :: term

  @typedoc """
  """
  @type effects :: %{optional(name) => effect}

  @typedoc """
  """
  @type stage :: term

  @typedoc """
  """
  @type transaction_result ::
          {:ok, effect}
          | {:error, reason :: term}
          | {:abort, reason :: term}

  @typedoc """
  """
  @type compensation_result ::
          :ok
          | :abort
          | {:retry, Retry.retry_opts()}
          | {:continue, effect}

  defstruct transaction: nil,
            compensation: nil,
            state: %State{}

  @type t :: %__MODULE__{
          transaction: (effects_so_far :: effects -> transaction_result),
          compensation:
            (reason :: term, effect_to_compensate :: effect, effects_so_far :: effects -> compensation_result),
          state: State.t()
        }

  @doc """
  """
  @spec get_full_name(t, full_name) :: full_name
  def get_full_name(stage, parent_full_name) do
    %{state: %{name: name}} = stage
    parent_full_name ++ [name]
  end

  @doc """
  """
  @spec execute_transaction(t, Event.t(), Stepable.opts()) :: Event.t()
  def execute_transaction(stage, event, opts \\ []) do
    %{state: %{effects_so_far: effects_so_far}} = stage
    opts = DryRun.from_stepable(event, opts, {:ok, nil})

    result =
      case DryRun.maybe_execute(stage.transaction, [effects_so_far], opts) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
        {:abort, reason} -> {:abort, reason}
        otherwise -> {:error, {:unsupported_transaction_result_form, otherwise}}
      end

    Event.update(event,
      name: [:completed, :transaction],
      context: result
    )
  end

  @doc """
  """
  @spec execute_compensation(t, Event.t(), Stepable.opts()) :: Event.t()
  def execute_compensation(stage, event, opts \\ []) do
    %{state: %{effects_so_far: effects_so_far, reason: reason}} = stage
    effect = Event.get_effect(event, effects_so_far)
    opts = DryRun.from_stepable(event, opts, :ok)

    result =
      case DryRun.maybe_execute(stage.compensation, [reason, effect, effects_so_far], opts) do
        :ok -> :ok
        :abort -> :abort
        {:retry, retry_opts} -> {:retry, retry_opts}
        {:continue, effect} -> {:continue, effect}
        otherwise -> {:error, {:unsupported_compensation_result_form, otherwise}}
      end

    Event.update(event,
      name: [:completed, :compensation],
      context: result
    )
  end

  @impl ExSaga.Stepper
  def handle_step(%{state: %State{hooks_left: []}} = stage, %Event{name: [:starting, :transaction]} = event, opts) do
    event = execute_transaction(stage, event, opts)
    {:continue, event, %{stage | state: %{stage.state | hooks_left: Hook.merge_hooks(stage.state, opts)}}}
  end

  def handle_step(%{state: %State{hooks_left: []}} = stage, %Event{name: [:completed, :transaction]} = event, opts) do
    %{state: %{name: name, effects_so_far: effects_so_far}} = stage

    case event.context do
      {:ok, result} ->
        {:ok, Map.put(effects_so_far, name, result)}

      {status, reason} when status in [:error, :abort] ->
        event =
          Event.update(event,
            name: [:starting, :compensation],
            context: {status, reason, Event.get_effect(event, effects_so_far), effects_so_far}
          )

        stage = if status == :abort, do: %{stage | state: %{stage.state | abort?: true}}, else: stage

        {:continue, event,
         %{stage | state: %{stage.state | hooks_left: Hook.merge_hooks(stage.state, opts), reason: reason}}}
    end
  end

  def handle_step(%{state: %State{hooks_left: []}} = stage, %Event{name: [:starting, :compensation]} = event, opts) do
    {_, reason, _, _} = event.context
    event = execute_compensation(stage, event, opts)

    {:continue, event,
     %{stage | state: %{stage.state | hooks_left: Hook.merge_hooks(stage.state, opts), reason: reason}}}
  end

  def handle_step(%{state: %State{hooks_left: []}} = stage, %Event{name: [:completed, :compensation]} = event, opts) do
    %{state: %{name: name, effects_so_far: effects_so_far, reason: reason}} = stage

    case event.context do
      :ok ->
        {:error, reason, effects_so_far}

      :abort ->
        {:abort, reason, effects_so_far}

      {:retry, retry_opts} ->
        case Retry.start_retry(stage.state, event, retry_opts) do
          %Event{} = event ->
            {:continue, event,
             %{stage | state: %{stage.state | hooks_left: Hook.merge_hooks(stage.state, opts), reason: nil}}}

          nil ->
            {:abort, reason, effects_so_far}
        end

      {:continue, effect} ->
        {:ok, Map.put(effects_so_far, name, effect)}

      {:error, reason} ->
        event =
          Event.update(event,
            name: [:starting, :error_handler],
            context: {reason, event, effects_so_far}
          )

        {:continue, event, %{stage | state: %{stage.state | hooks_left: Hook.merge_hooks(stage.state, opts)}}}
    end
  end

  def handle_step(_stage, _event, _opts) do
    nil
  end

  defimpl Stepable do
    alias ExSaga.Stage

    def get_name(%{state: %{name: name}}, opts) do
      parent_full_name = Keyword.get(opts, :parent_full_name, [])
      parent_full_name ++ [name]
    end

    def get_name(_stepable, _opts) do
      []
    end

    def step_from(stage, {:ok, effects_so_far}, opts) do
      full_name = Stepable.get_name(stage, opts)

      event =
        Event.create(
          id: Keyword.get(opts, :id),
          stage_name: full_name,
          name: [:starting, :transaction],
          context: effects_so_far,
          stage: Stage
        )

      stage = %{stage | state: State.reset(stage.state)}

      {:continue, event,
       %{
         stage
         | state: %{
             stage.state
             | hooks_left: Hook.merge_hooks(stage.state, opts),
               effects_so_far: effects_so_far,
               abort?: false,
               reason: nil
           }
       }}
    end

    def step_from(stage, {status, reason, effects_so_far}, opts)
        when status in [:error, :abort] do
      abort? = if status == :abort, do: true, else: false
      full_name = Stepable.get_name(stage, opts)
      effect = Utils.get_in(effects_so_far, tl(full_name))

      event =
        Event.create(
          id: Keyword.get(opts, :id),
          stage_name: full_name,
          name: [:starting, :compensation],
          context: {status, reason, effect, effects_so_far},
          stage: Stage
        )

      stage = %{stage | state: State.reset(stage.state)}

      {:continue, event,
       %{
         stage
         | state: %{
             stage.state
             | hooks_left: Hook.merge_hooks(stage.state, opts),
               effects_so_far: effects_so_far,
               abort?: abort?,
               reason: reason
           }
       }}
    end

    def step_from(stage, _result, _opts) do
      # TODO: error handler
      {:continue, nil, stage}
    end

    def step(stage, event, opts) do
      Stage.step(stage, event, opts)
    end
  end
end
