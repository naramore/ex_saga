defmodule ExSaga.ErrorHandler do
  @moduledoc """
  """

  alias ExSaga.{DryRun, Event, Hook, Stage, State, Stepable}

  @typedoc """
  """
  @type accumulator :: %{
          hooks: [Hook.t()],
          hooks_left: [Hook.t()],
          on_error: module,
          effects_so_far: Stage.effects(),
          reason: term
        }

  @typedoc """
  """
  @type error_reason ::
          {:raise, Exception.t(), Exception.stacktrace()}
          | {:exit, reason :: term}
          | {:throw, value :: term}

  @doc """
  """
  @callback handle_error(error_reason, event :: Event.t(), effects_so_far :: Stage.effects()) ::
              error_reason | {:ok, valid_result :: term}

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour ExSaga.ErrorHandler

      @impl ExSaga.ErrorHandler
      def handle_error(reason, _event, _effects_so_far) do
        reason
      end

      defoverridable handle_error: 3
    end
  end

  @doc """
  """
  @spec error_step(reason :: term, Stepable.t(), Event.t(), Stepable.opts()) :: Stepable.step_result()
  def error_step(nil, stepable, event, opts) do
    %{state: %State{reason: reason}} = stepable
    reason = if is_nil(reason), do: :unspecified, else: reason
    error_step(reason, stepable, event, opts)
  end

  def error_step(reason, stepable, event, opts) do
    %{state: %{effects_so_far: effects_so_far}} = stepable

    event =
      Event.update(event,
        name: [:starting, :error_handler],
        context: {reason, event, effects_so_far}
      )

    {:continue, event, %{stepable | state: %{stepable.state | hooks_left: Hook.merge_hooks(stepable.state, opts)}}}
  end

  @doc """
  """
  @spec step(accumulator, Event.t(), Stepable.opts()) :: {:continue, Event.t() | nil, accumulator} | no_return
  def step(acc, event, opts \\ [])

  def step(acc, %Event{name: [:starting, :error_handler]} = e, opts) do
    {_reason, originating_event, _effects_so_far} = e.context
    event = execute_error_handler(acc, originating_event, opts)
    {:continue, event, %{acc | hooks_left: Hook.merge_hooks(acc, opts)}}
  end

  def step(acc, %Event{name: [:completed, :error_handler]} = e, opts) do
    case e.context do
      {origin, {:ok, result}} ->
        {:continue, Event.update(origin, context: result),
         %{acc | hooks_left: Hook.merge_hooks(acc, opts), reason: nil}}

      {_, {:raise, error, stacktrace}} ->
        filter_and_reraise(error, stacktrace)

      {_, {:throw, value}} ->
        throw(value)

      {_, {:exit, reason}} ->
        exit(reason)
    end
  end

  @doc """
  """
  @spec execute_error_handler(accumulator, Event.t(), Stepable.opts()) :: Event.t() | no_return
  def execute_error_handler(acc, event, opts \\ []) do
    %{effects_so_far: effects_so_far, reason: reason} = acc
    error_handler = Map.get(acc, :on_error, ExSaga.RaiseErrorHandler)
    opts = DryRun.from_stepable(event, opts, nil)

    result =
      case DryRun.maybe_execute(&error_handler.handle_error/3, [reason, event, effects_so_far], opts) do
        {:error, {:raise, error, stacktrace}} -> {:raise, error, stacktrace}
        {:raise, error, stacktrace} -> {:raise, error, stacktrace}
        {:error, {:throw, value}} -> {:throw, value}
        {:throw, value} -> {:throw, value}
        {:error, {:exit, reason}} -> {:exit, reason}
        {:ok, result} -> {:ok, result}
        otherwise -> {:throw, {:unsupported_error_handler_result_form, otherwise}}
      end

    Event.update(event,
      name: [:completed, :error_handler],
      context: {event, result}
    )
  end

  @doc false
  @spec filter_and_reraise(Exception.t(), Exception.stacktrace()) :: no_return
  defp filter_and_reraise(exception, stacktrace) do
    # TODO: implement filtering for stacktraces...
    reraise(exception, stacktrace)
  end
end

defmodule ExSaga.RaiseErrorHandler do
  @moduledoc """
  """

  use ExSaga.ErrorHandler
end
