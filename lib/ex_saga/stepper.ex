defmodule ExSaga.Stepper do
  @moduledoc """
  """

  alias ExSaga.{ErrorHandler, Event, Hook, Retry, Stage, State, Stepable}

  @doc """
  """
  @callback handle_sublevel_step(stepable :: Stepable.t(), event :: Event.t(), opts :: Stepable.opts()) ::
              Stepable.stage_result() | Stepable.step_result() | nil

  @doc """
  """
  @callback handle_step(stepable :: Stepable.t(), event :: Event.t(), opts :: Stepable.opts()) ::
              Stepable.stage_result() | Stepable.step_result() | nil

  @doc false
  defmacro __using__(opts) do
    quote do
      @behaviour ExSaga.Stepper
      alias ExSaga.{Event, Stage, Stepable, Stepper}

      @compensation_event_name Keyword.get(unquote(opts), :compensation_event_name, [])

      @doc """
      """
      @spec compensation_event_name() :: Stage.full_name()
      def compensation_event_name() do
        @compensation_event_name
      end

      @doc """
      """
      @spec step(Stepable.t(), Event.t(), Stepable.opts()) :: Stepable.stage_result() | Stepable.step_result()
      def step(stepable, event, opts \\ []) do
        Stepper.step(__MODULE__, stepable, event, opts)
      end

      @impl Stepper
      def handle_sublevel_step(stepable, event, opts) do
        step(%{stepable | state: %{stepable.state | sublevel?: false}}, event, opts)
      end

      defoverridable handle_sublevel_step: 3
    end
  end

  @doc """
  """
  @spec step(stepper :: module, Stepable.t(), Event.t(), Stepable.opts()) ::
          Stepable.stage_result() | Stepable.step_result()
  def step(stepper, stepable, event, opts \\ [])

  def step(stepper, stepable, %Event{name: [_, :hook, _]} = event, opts) do
    case Hook.step(event, stepable.state, opts) do
      {nil, new_state} ->
        case event.context do
          {%Event{} = inner, _} ->
            step(stepper, %{stepable | state: new_state}, inner, opts)

          %Event{} = e ->
            step(stepper, %{stepable | state: new_state}, e, opts)

          _ ->
            {:continue, nil, %{stepable | state: new_state}}
        end

      {%Event{name: nil} = e, new_state} ->
        event_name = stepper.compensation_event_name()
        {:continue, Event.update(e, name: event_name), %{stepable | state: new_state}}

      {next_event, new_state} ->
        {:continue, next_event, %{stepable | state: new_state}}
    end
  end

  def step(stepper, %{state: %State{sublevel?: true, hooks_left: []}} = stepable, event, opts) do
    case stepper.handle_sublevel_step(stepable, event, opts) do
      nil -> unknown_step(stepable, event, opts)
      otherwise -> otherwise
    end
  end

  def step(_stepper, %{state: %State{hooks_left: []}} = stepable, %Event{name: [_, :retry, _]} = event, opts) do
    case Retry.step(stepable.state, event, opts) do
      {:continue, event, state} ->
        {:continue, event, %{stepable | state: state}}

      {:noretry, _event, state} ->
        %{effects_so_far: effects_so_far, reason: reason} = state
        {:error, reason, effects_so_far}

      {:retry, event, state} ->
        %{effects_so_far: effects_so_far} = state

        event =
          Event.update(event,
            name: [:starting, :transaction],
            context: effects_so_far
          )

        {:continue, event, %{stepable | state: state}}
    end
  end

  def step(_stepper, %{state: %State{hooks_left: []}} = stepable, %Event{name: [_, :error_handler]} = event, opts) do
    {:continue, event, state} = ErrorHandler.step(stepable.state, event, opts)
    {:continue, event, %{stepable | state: state}}
  end

  def step(stepper, %{state: %State{hooks_left: []}} = stepable, event, opts) do
    case stepper.handle_step(stepable, event, opts) do
      nil -> unknown_step(stepable, event, opts)
      otherwise -> otherwise
    end
  end

  def step(_stepper, %{state: %State{hooks_left: [h | hs]}} = stepable, event, opts) do
    stepable = %{stepable | state: %{stepable.state | hooks_left: hs}}
    {:continue, Hook.maybe_execute_hook(h, event, stepable.state, opts), stepable}
  end

  @doc false
  @spec unknown_step(Stepable.t(), Event.t(), Stepable.opts()) :: Stepable.step_result()
  defp unknown_step(stepable, event, opts) do
    reason = {:unknown_event, event}
    %{state: %{effects_so_far: effects_so_far}} = stepable

    event =
      Event.update(event,
        name: [:starting, :error_handler],
        context: {reason, event, effects_so_far}
      )

    {:continue, event, %{stepable | state: %{stepable.state | hooks_left: Hook.merge_hooks(stepable.state, opts)}}}
  end
end
