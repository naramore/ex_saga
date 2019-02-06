defmodule ExSaga.Saga do
  @moduledoc """
  """

  use ExSaga.Stepper, compensation_event_name: [:starting, :saga, :compensation]
  alias ExSaga.{DryRun, ErrorHandler, Event, Hook, Retry, Stage, State, Stepable}

  @typedoc """
  """
  @type compensation_result ::
          :ok
          | :abort
          | {:retry, Retry.retry_opts()}
          | {:continue, Stage.effects()}

  defstruct completed_stages: [],
            stages_left: [],
            effects_importer: nil,
            compensation: nil,
            state: %State{}

  @type t :: %__MODULE__{
          completed_stages: [Stepable.t()],
          stages_left: [Stepable.t()],
          effects_importer: (Stage.effects() -> {:ok, Stage.effects()} | {:error, reason :: term}) | nil,
          compensation: (reason :: term, effects_so_far :: Stage.effects() -> compensation_result),
          state: State.t()
        }

  @doc """
  """
  @spec update_opts(t, Stepable.opts()) :: Stepable.opts()
  def update_opts(saga, opts) do
    %{state: %{hooks: hooks, on_retry: on_retry}} = saga
    full_name = Stepable.get_name(saga, opts)
    retry_updates = Keyword.get(opts, :retry_updates, [])

    additional_hooks =
      (hooks ++ Keyword.get(opts, :extra_hooks, []))
      |> Enum.filter(fn
        {_, hopts} -> Keyword.get(hopts, :cascade_depth, 0) > 0
        _ -> false
      end)
      |> Enum.map(fn {h, hopts} ->
        {h, Keyword.update!(hopts, :cascade_depth, fn cd -> cd - 1 end)}
      end)

    Keyword.merge(opts,
      parent_full_name: full_name,
      extra_hooks: additional_hooks,
      retry_updates: [{full_name, on_retry} | retry_updates]
    )
  end

  @doc """
  """
  @spec execute_effects_import(t, Event.t(), Stepable.opts()) :: Event.t()
  def execute_effects_import(saga, event, opts \\ []) do
    %{state: %{effects_so_far: effects_so_far}} = saga
    opts = DryRun.from_stepable(event, opts, {:ok, %{}})

    result =
      case DryRun.maybe_execute(saga.effects_importer, [effects_so_far], opts) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
        otherwise -> {:error, {:unsupported_transaction_result_form, otherwise}}
      end

    Event.update(event,
      name: [:completed, :saga, :effects_import],
      context: result
    )
  end

  @doc """
  """
  @spec execute_compensation(t, Event.t(), Stepable.opts()) :: Event.t()
  def execute_compensation(saga, event, opts \\ []) do
    %{state: %{effects_so_far: effects_so_far, reason: reason}} = saga
    opts = DryRun.from_stepable(event, opts, :ok)

    result =
      case DryRun.maybe_execute(saga.compensation, [reason, effects_so_far], opts) do
        :ok -> :ok
        :abort -> :abort
        {:retry, retry_opts} -> {:retry, retry_opts}
        {:continue, effect} -> {:continue, effect}
        otherwise -> {:error, {:unsupported_compensation_result_form, otherwise}}
      end

    Event.update(event,
      name: [:completed, :saga, :compensation],
      context: result
    )
  end

  @impl ExSaga.Stepper
  def handle_sublevel_step(saga, event, opts) do
    %{stages_left: [stage | stages]} = saga
    opts = update_opts(saga, opts)

    case Stepable.step(stage, event, opts) do
      {:continue, event, new_stage} ->
        {:continue, event, %{saga | stages_left: [new_stage | stages]}}

      otherwise ->
        stage_name = Map.get(event, :stage_name, []) |> Enum.drop(-1)

        event =
          Event.update(event,
            name: [:completed, :saga, :stage],
            context: otherwise,
            stage_name: stage_name,
            stage: Saga
          )

        {:continue, event,
         %{saga | state: %{saga.state | hooks_left: Hook.merge_hooks(saga.state, opts), sublevel?: false}}}
    end
  end

  @impl ExSaga.Stepper
  def handle_step(
        %{state: %State{hooks_left: []}} = saga,
        %Event{name: [:starting, :saga, :effects_import]} = event,
        opts
      ) do
    event = execute_effects_import(saga, event, opts)
    {:continue, event, %{saga | state: %{saga.state | hooks_left: Hook.merge_hooks(saga.state, opts)}}}
  end

  def handle_step(
        %{state: %State{hooks_left: []}} = saga,
        %Event{name: [:completed, :saga, :effects_import]} = event,
        opts
      ) do
    case event.context do
      {:ok, %{} = effects} ->
        {:continue, event,
         %{saga | state: %{saga.state | hooks_left: Hook.merge_hooks(saga.state, opts), effects_so_far: effects}}}

      {:error, reason} ->
        ErrorHandler.error_step(reason, saga, event, opts)
    end
  end

  def handle_step(%{state: %State{hooks_left: []}} = saga, %Event{name: [:starting, :saga, :stage]} = event, opts) do
    %{stages_left: [stage | stages]} = saga
    opts = update_opts(saga, opts)
    {:continue, event, stage} = Stepable.step_from(stage, event.context, opts)
    {:continue, event, %{saga | stages_left: [stage | stages], state: %{saga.state | sublevel?: true}}}
  end

  def handle_step(%{state: %State{hooks_left: []}} = saga, %Event{name: [:completed, :saga, :stage]} = event, opts) do
    case {saga, event.context} do
      {%{stages_left: [_]}, {:ok, effects_so_far}} ->
        {:ok, effects_so_far}

      {%{completed_stages: completed, stages_left: [this | left]}, {:ok, effects_so_far}} ->
        event =
          Event.update(event,
            name: [:starting, :saga, :stage],
            context: {:ok, effects_so_far}
          )

        {:continue, event,
         %{
           saga
           | state: %{saga.state | hooks_left: Hook.merge_hooks(saga.state, opts), effects_so_far: effects_so_far},
             stages_left: left,
             completed_stages: [this | completed]
         }}

      {%{completed_stages: []}, {status, reason, effects_so_far}} when status in [:error, :abort] ->
        event =
          Event.update(event,
            name: [:starting, :saga, :compensation],
            context: {status, reason, effects_so_far}
          )

        {:continue, event,
         %{saga | state: %{saga.state | hooks_left: Hook.merge_hooks(saga.state, opts), effects_so_far: effects_so_far}}}

      {%{completed_stages: [last | completed], stages_left: left}, {status, reason, effects_so_far}}
      when status in [:error, :abort] ->
        event =
          Event.update(event,
            name: [:starting, :saga, :stage],
            context: {status, reason, effects_so_far}
          )

        {:continue, event,
         %{
           saga
           | state: %{saga.state | hooks_left: Hook.merge_hooks(saga.state, opts), effects_so_far: effects_so_far},
             stages_left: [last | left],
             completed_stages: completed
         }}

      _ ->
        ErrorHandler.error_step(nil, saga, event, opts)
    end
  end

  def handle_step(
        %{state: %State{hooks_left: []}} = saga,
        %Event{name: [:starting, :saga, :compensation]} = event,
        opts
      ) do
    {_, reason, _} = event.context
    event = execute_compensation(saga, event, opts)
    {:continue, event, %{saga | state: %{saga.state | hooks_left: Hook.merge_hooks(saga.state, opts), reason: reason}}}
  end

  def handle_step(
        %{state: %State{hooks_left: []}} = saga,
        %Event{name: [:completed, :saga, :compensation]} = event,
        opts
      ) do
    %{state: %{effects_so_far: effects_so_far, reason: reason}} = saga

    case event.context do
      :ok ->
        {:error, reason, effects_so_far}

      :abort ->
        {:abort, reason, effects_so_far}

      {:retry, retry_opts} ->
        case Retry.start_retry(saga.state, event, retry_opts) do
          %Event{} = event ->
            {:continue, event,
             %{saga | state: %{saga.state | hooks_left: Hook.merge_hooks(saga.state, opts), reason: nil}}}

          nil ->
            {:abort, reason, effects_so_far}
        end

      {:continue, effects} ->
        # TODO: maybe merge these effects with effects_so_far?
        {:ok, effects}

      {:error, reason} ->
        event =
          Event.update(event,
            name: [:starting, :error_handler],
            context: {reason, event, effects_so_far}
          )

        {:continue, event, %{saga | state: %{saga.state | hooks_left: Hook.merge_hooks(saga.state, opts)}}}
    end
  end

  def handle_step(_saga, _event, _opts) do
    nil
  end

  defimpl Stepable do
    alias ExSaga.Saga

    def get_name(%{state: %{name: name}}, opts) do
      parent_full_name = Keyword.get(opts, :parent_full_name, [])
      parent_full_name ++ [name]
    end

    def get_name(_stepable, _opts) do
      []
    end

    # TODO: add support for effects importer
    def step_from(saga, {:ok, effects_so_far}, opts) do
      full_name = Stepable.get_name(saga, opts)

      event =
        Event.create(
          id: Keyword.get(opts, :id),
          stage_name: full_name,
          name: [:starting, :saga, :stage],
          context: {:ok, effects_so_far},
          stage: Stage
        )

      saga = %{initialize_stages(:transaction, saga) | state: State.reset(saga.state)}

      {:continue, event,
       %{
         saga
         | state: %{
             saga.state
             | hooks_left: Hook.merge_hooks(saga.state, opts),
               effects_so_far: effects_so_far,
               abort?: false,
               reason: nil
           }
       }}
    end

    def step_from(saga, {status, reason, effects_so_far}, opts)
        when status in [:error, :abort] do
      abort? = if status == :abort, do: true, else: false
      full_name = Stepable.get_name(saga, opts)

      event =
        Event.create(
          id: Keyword.get(opts, :id),
          stage_name: full_name,
          name: [:starting, :saga, :compensation],
          context: {status, reason, effects_so_far},
          stage: Saga
        )

      saga = %{initialize_stages(:compensation, saga) | state: State.reset(saga.state)}

      {:continue, event,
       %{
         saga
         | state: %{
             saga.state
             | hooks_left: Hook.merge_hooks(saga.state, opts),
               effects_so_far: effects_so_far,
               abort?: abort?,
               reason: reason
           }
       }}
    end

    def step_from(saga, _stage_result, _opts) do
      # TODO: error handler
      {:continue, nil, saga}
    end

    def step(saga, event, opts) do
      Saga.step(saga, event, opts)
    end

    @doc false
    @spec initialize_stages(:transaction | :compensation, Saga.t()) :: Saga.t()
    defp initialize_stages(:transaction, saga) do
      %{completed_stages: completed, stages_left: left} = saga
      left = :lists.reverse(completed, left)
      %{saga | completed_stages: [], stages_left: left}
    end

    defp initialize_stages(:compensation, saga) do
      %{completed_stages: completed, stages_left: left} = saga
      completed = :lists.reverse(left, completed)
      %{saga | completed_stages: completed, stages_left: []}
    end
  end
end
