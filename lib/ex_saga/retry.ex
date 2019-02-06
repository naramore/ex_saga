defmodule ExSaga.Retry do
  @moduledoc """
  """

  alias ExSaga.{DryRun, Event, Hook, Stage, Step, Stepable}

  @typedoc """
  """
  @type accumulator :: %{
          :on_retry => module,
          :hooks_left => [Hook.t()],
          :retry_updates_left => [{Stage.full_name(), module}],
          :update => retry_result | nil,
          :effects_so_far => Stage.effects(),
          :abort? => boolean,
          optional(term) => term
        }

  @typedoc """
  """
  @type retry_opts :: Keyword.t()

  @typedoc """
  """
  @type retry_state :: term

  @typedoc """
  """
  @type wait :: {non_neg_integer, System.time_unit()}

  @typedoc """
  """
  @type retry_result ::
          {:retry, wait, retry_state}
          | {:noretry, retry_state}

  @typedoc """
  """
  @type update_result :: :ok | {:ok, retry_state}

  @doc """
  """
  @callback init(retry_opts) :: {:ok, retry_state, retry_opts}

  @doc """
  """
  @callback handle_retry(retry_state, retry_opts) :: retry_result

  @doc """
  """
  @callback update(retry_state, origin_full_name :: Stage.full_name(), retry_result) :: update_result

  defmacro __using__(opts) do
    shared_state? = Keyword.get(opts, :shared_state?, true)

    quote do
      @behaviour ExSaga.Retry
      @shared_state? unquote(shared_state?)
      alias ExSaga.Retry

      @doc false
      @spec shared_state?() :: boolean
      def shared_state?(), do: @shared_state?

      @impl Retry
      def update(_retry_state, _stage_name, _retry_opts) do
        :ok
      end

      defoverridable update: 3
    end
  end

  @doc """
  """
  @spec start_retry(accumulator, Event.t(), retry_opts) :: Event.t() | nil
  def start_retry(%{abort?: true}, _event, _retry_opts),
    do: nil

  def start_retry(acc, event, retry_opts) do
    %{effects_so_far: effects_so_far} = acc
    retry_state = get_retry_state(effects_so_far, acc.on_retry, event.stage_name)

    if is_nil(retry_state) do
      Event.update(event,
        name: [:starting, :retry, :init],
        context: retry_opts
      )
    else
      Event.update(event,
        name: [:starting, :retry, :handler],
        context: {retry_state, retry_opts}
      )
    end
  end

  @doc false
  @spec get_retry_state(Stage.effects(), module, Stage.full_name()) :: retry_state
  defp get_retry_state(effects_so_far, mod, name) do
    get_in(effects_so_far, get_retry_state_path(mod, name))
  end

  @doc false
  @spec update_retry_state(Stage.effects(), module, Stage.full_name(), retry_state) :: Stage.effects()
  defp update_retry_state(%{__retry__: retry_states} = effects_so_far, mod, name, retry_state)
       when is_map(retry_states) do
    put_in(effects_so_far, get_retry_state_path(mod, name), retry_state)
  end

  defp update_retry_state(effects_so_far, mod, name, retry_state) do
    [_, key] = get_retry_state_path(mod, name)
    Map.merge(effects_so_far, %{__retry__: %{key => retry_state}})
  end

  @doc false
  @spec get_retry_state_path(module, Stage.full_name()) :: retry_state
  defp get_retry_state_path(mod, name) do
    if mod.shared_state?() do
      [:__retry__, mod]
    else
      [:__retry__, name]
    end
  end

  @doc """
  """
  @spec step(accumulator, Event.t(), Step.opts()) :: {:retry | :noretry | :continue, Event.t(), accumulator}
  def step(acc, event, opts \\ [])

  def step(%{retry_updates_left: []} = acc, %Event{name: [:starting, :retry, :init]} = event, opts) do
    event = execute_retry_init(acc, event, opts)
    {:continue, event, %{acc | hooks_left: Hook.merge_hooks(acc, opts)}}
  end

  def step(%{retry_updates_left: []} = acc, %Event{name: [:completed, :retry, :init]} = event, opts) do
    case event.context do
      {:ok, retry_state, retry_opts} ->
        event =
          Event.update(event,
            name: [:starting, :retry, :handler],
            context: {retry_state, retry_opts}
          )

        {:continue, event, %{acc | hooks_left: Hook.merge_hooks(acc, opts)}}

      {:error, reason} ->
        %{effects_so_far: effects_so_far} = acc

        event =
          Event.update(event,
            name: [:starting, :error_handler],
            context: {reason, event, effects_so_far}
          )

        {:continue, event, %{acc | hooks_left: Hook.merge_hooks(acc, opts)}}
    end
  end

  def step(%{retry_updates_left: []} = acc, %Event{name: [:starting, :retry, :handler]} = event, opts) do
    event = execute_retry_handler(acc, event, opts)
    {:continue, event, %{acc | hooks_left: Hook.merge_hooks(acc, opts)}}
  end

  def step(%{retry_updates_left: [], update: nil} = acc, %Event{name: [:completed, :retry, :handler]} = event, opts) do
    %{effects_so_far: effects_so_far} = acc

    case event.context do
      {:retry, _wait, retry_state} ->
        # TODO: implement the actual wait...
        %{
          acc
          | effects_so_far: update_retry_state(effects_so_far, acc.on_retry, event.stage_name, retry_state),
            hooks_left: Hook.merge_hooks(acc, opts),
            retry_updates_left: Keyword.get(opts, :retry_updates, []),
            update: event.context
        }
        |> step(event, opts)

      {:noretry, retry_state} ->
        %{
          acc
          | effects_so_far: update_retry_state(effects_so_far, acc.on_retry, event.stage_name, retry_state),
            hooks_left: Hook.merge_hooks(acc, opts),
            retry_updates_left: Keyword.get(opts, :retry_updates, []),
            update: event.context
        }
        |> step(event, opts)

      {:error, reason} ->
        event =
          Event.update(event,
            name: [:starting, :error_handler],
            context: {reason, event, effects_so_far}
          )

        {:continue, event, %{acc | hooks_left: Hook.merge_hooks(acc, opts)}}
    end
  end

  def step(%{retry_updates_left: []} = acc, %Event{name: [:completed, :retry, n]} = event, _opts)
      when n in [:handler, :update] do
    case Map.get(acc, :update, {:noretry, nil}) do
      {:retry, _wait, _retry_state} -> {:retry, event, %{acc | update: nil}}
      {:noretry, _retry_state} -> {:noretry, event, %{acc | update: nil}}
    end
  end

  def step(
        %{retry_updates_left: [{path, retry} | us]} = acc,
        %Event{name: [:completed, :retry, :handler]} = event,
        opts
      ) do
    %{update: update} = acc

    event =
      Event.update(event,
        name: [:starting, :retry, :update],
        context: {path, retry, update}
      )

    {:continue, event, %{acc | hooks_left: Hook.merge_hooks(acc, opts), retry_updates_left: us}}
  end

  def step(%{retry_updates_left: [_ | _]} = acc, %Event{name: [:completed, :retry, :update]} = event, opts) do
    %{effects_so_far: effects_so_far} = acc

    case event.context do
      :ok ->
        step(acc, %{event | name: [:completed, :retry, :handler]}, opts)

      {:ok, retry_state} ->
        %{acc | effects_so_far: update_retry_state(effects_so_far, acc.on_retry, event.stage_name, retry_state)}
        |> step(%{event | name: [:completed, :retry, :handler]}, opts)

      {:error, reason} ->
        event =
          Event.update(event,
            name: [:starting, :error_handler],
            context: {reason, event, effects_so_far}
          )

        {:continue, event, %{acc | hooks_left: Hook.merge_hooks(acc, opts)}}
    end
  end

  def step(acc, %Event{name: [:starting, :retry, :update]} = event, opts) do
    event = execute_retry_update(acc, event, opts)
    {:continue, event, %{acc | hooks_left: Hook.merge_hooks(acc, opts)}}
  end

  def step(acc, event, opts) do
    reason = {:unknown_event, event}
    %{effects_so_far: effects_so_far} = acc

    event =
      Event.update(event,
        name: [:starting, :error_handler],
        context: {reason, event, effects_so_far}
      )

    {:continue, event, %{acc | hooks_left: Hook.merge_hooks(acc, opts)}}
  end

  @doc false
  @spec execute_retry_init(accumulator, Event.t(), Stepable.opts()) :: Event.t()
  defp execute_retry_init(acc, event, opts) do
    retry_handler = Map.get(acc, :on_retry)
    opts = DryRun.from_stepable(event, opts, {:ok, nil})

    result =
      case DryRun.maybe_execute(&retry_handler.init/1, [event.context], opts) do
        {:ok, retry_state, retry_opts} -> {:ok, retry_state, retry_opts}
        otherwise -> {:error, {:unsupported_retry_init_result_form, otherwise}}
      end

    Event.update(event,
      name: [:completed, :retry, :init],
      context: result
    )
  end

  @doc false
  @spec execute_retry_handler(accumulator, Event.t(), Stepable.opts()) :: Event.t()
  defp execute_retry_handler(acc, event, opts) do
    {retry_state, retry_opts} = event.context
    retry_handler = Map.get(acc, :on_retry)
    opts = DryRun.from_stepable(event, opts, {:ok, nil})

    result =
      case DryRun.maybe_execute(&retry_handler.handle_retry/2, [retry_state, retry_opts], opts) do
        {:retry, wait, retry_state} -> {:retry, wait, retry_state}
        {:noretry, retry_state} -> {:noretry, retry_state}
        otherwise -> {:error, {:unsupported_retry_handler_result_form, otherwise}}
      end

    Event.update(event,
      name: [:completed, :retry, :handler],
      context: result
    )
  end

  @doc false
  @spec execute_retry_update(accumulator, Event.t(), Stepable.opts()) :: Event.t()
  defp execute_retry_update(acc, event, opts) do
    {path, retry, retry_result} = event.context
    %{effects_so_far: effects_so_far} = acc
    retry_state = get_retry_state(effects_so_far, retry, path)
    opts = DryRun.from_stepable(event, opts, {:ok, nil})

    result =
      case DryRun.maybe_execute(&retry.update/3, [retry_state, path, retry_result], opts) do
        :ok -> :ok
        {:ok, retry_state} -> {:ok, retry_state}
        otherwise -> {:error, {:unsupported_retry_handler_result_form, otherwise}}
      end

    Event.update(event,
      name: [:completed, :retry, :update],
      context: result
    )
  end
end
