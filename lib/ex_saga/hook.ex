defmodule ExSaga.Hook do
  @moduledoc """
  """

  alias ExSaga.{DryRun, Event, Stage, Stepable}

  @typedoc """
  """
  @type opt ::
          {:override, boolean}
          | {:cascade_depth, non_neg_integer}

  @typedoc """
  """
  @type opts :: [opt]

  @typedoc """
  """
  @type hook_state :: term

  @typedoc """
  """
  @type hook_result ::
          :ok
          | {:ok, hook_state}
          | {:error, reason :: term}
          | {:error, reason :: term, hook_state}

  @typedoc """
  """
  @type hook_context :: {Event.t(), Hook.hook_result()} | Event.t()

  @typedoc """
  """
  @type accumulator :: %{
          hooks: [t],
          hooks_left: [t],
          effects_so_far: Stage.effects()
        }

  defstruct name: nil,
            filter: nil,
            fun: nil

  @type t :: %__MODULE__{
          name: Stage.name(),
          filter: (Event.t(), hook_state -> boolean),
          fun: (Event.t(), hook_state -> hook_result)
        }

  @doc """
  """
  @spec merge_hooks(accumulator, Stepable.opts()) :: [t]
  def merge_hooks(acc, opts \\ []) do
    acc
    |> Map.get(:hooks, [])
    |> Enum.map(fn
      {h, _} -> h
      h -> h
    end)
    |> reduce_hooks(opts)
  end

  @doc false
  @spec reduce_hooks([t], Stepable.opts()) :: [t]
  defp reduce_hooks(stage_hooks, opts) do
    opts
    |> Keyword.get(:extra_hooks, [])
    |> Enum.reduce(stage_hooks, fn
      {h, hopts}, hs -> add_hook(h, hs, hopts)
      h, hs -> add_hook(h, hs)
    end)
  end

  @doc false
  @spec add_hook(t, [t], opts) :: [t]
  defp add_hook(new_hook, hooks, opts \\ []) do
    with %__MODULE__{} <- Enum.find(hooks, fn h -> h.name == new_hook.name end),
         {false, _} <- Keyword.pop(opts, :override?, false) do
      hooks
    else
      _ -> [new_hook | hooks]
    end
  end

  @doc """
  """
  @spec step(Event.t(), accumulator, Stepable.opts()) :: {Event.t() | nil, accumulator}
  def step(event, acc, opts \\ [])

  def step(event, %{hooks_left: []} = acc, opts) do
    case maybe_update_hook_state(event.context, acc) do
      {:ok, new_state} ->
        {nil, new_state}

      {:error, _reason, new_state} ->
        handle_hook_error(event.context, new_state, opts)
    end
  end

  def step(event, %{hooks_left: [h | hs]} = acc, opts) do
    case maybe_update_hook_state(event.context, acc) do
      {:ok, new_state} ->
        {maybe_execute_hook(h, event, new_state, opts), %{new_state | hooks_left: hs}}

      {:error, _reason, new_state} ->
        handle_hook_error(event.context, new_state, opts)
    end
  end

  def step(_event, acc, _opts), do: {nil, acc}

  @doc false
  @spec maybe_update_hook_state(hook_context, accumulator) ::
          {:ok, accumulator}
          | {:error, reason :: term, accumulator}
  defp maybe_update_hook_state({_, hook_result}, acc) do
    update_hook_state(hook_result, acc)
  end

  defp maybe_update_hook_state(_, acc), do: {:ok, acc}

  @doc false
  @spec update_hook_state(hook_result, accumulator) ::
          {:ok, accumulator}
          | {:error, reason :: term, accumulator}
  defp update_hook_state(:ok, acc), do: {:ok, acc}

  defp update_hook_state({:ok, hook_state}, acc) do
    {:ok, put_in(acc, [Access.key(:effects_so_far), :__hookstate__], hook_state)}
  end

  defp update_hook_state({:error, reason}, acc),
    do: {:error, reason, acc}

  defp update_hook_state({:error, reason, hook_state}, acc) do
    {:error, reason, put_in(acc, [Access.key(:effects_so_far), :__hookstate__], hook_state)}
  end

  defp update_hook_state(hook_result, acc) do
    {:error, {:invalid_hook_result, hook_result}, acc}
  end

  @doc false
  @spec handle_hook_error(hook_context, accumulator, Stepable.opts()) :: {Event.t() | nil, accumulator}
  defp handle_hook_error({event, {:error, reason, _}}, acc, opts),
    do: handle_hook_error({event, {:error, reason}}, acc, opts)

  defp handle_hook_error({%Event{name: [_, _, :compensation]}, _}, %{hooks_left: []} = acc, _opts) do
    {nil, acc}
  end

  defp handle_hook_error({%Event{name: [_, _, :compensation]} = e, _}, %{hooks_left: [h | hs]} = s, opts) do
    {maybe_execute_hook(h, e, s, opts), %{s | hooks_left: hs}}
  end

  defp handle_hook_error({event, {:error, reason}}, acc, _opts) do
    # TODO: compensation or error handler after error w/ hooks
    %{effects_so_far: effects_so_far} = acc

    {
      Event.update(event,
        context: {:error, reason, Event.get_effect(event, effects_so_far), effects_so_far},
        name: nil
      ),
      acc
    }
  end

  @doc """
  """
  @spec maybe_execute_hook(t, Event.t(), accumulator, Stepable.opts()) :: Event.t()
  def maybe_execute_hook(hook, %Event{name: [:completed, :hook, _]} = event, acc, opts) do
    {inner_event, _} = event.context
    maybe_execute_hook(hook, inner_event, acc, opts)
  end

  def maybe_execute_hook(hook, %Event{name: [:skipped, :hook, _]} = event, acc, opts) do
    maybe_execute_hook(hook, event.context, acc, opts)
  end

  def maybe_execute_hook(hook, event, acc, opts) do
    hook_state = get_in(acc, [Access.key(:effects_so_far), :__hookstate__])
    opts = DryRun.from_stepable(event, opts, false)

    case DryRun.maybe_execute(hook.filter, [event, hook_state], opts ++ [hook: :filter]) do
      true ->
        result = execute_hook(hook, event, hook_state, opts)

        Event.update(event,
          name: [:completed, :hook, hook.name],
          context: {event, result}
        )

      _ ->
        Event.update(event,
          name: [:skipped, :hook, hook.name],
          context: event
        )
    end
  end

  @doc false
  @spec execute_hook(t, Event.t(), hook_state, DryRun.execution_opts()) :: hook_result
  defp execute_hook(hook, event, state, opts) do
    opts = Keyword.put(opts, :dry_run_result_default, :ok)

    case DryRun.maybe_execute(hook.fun, [event, state], opts ++ [hook: :hook]) do
      :ok -> :ok
      {:ok, hook_state} -> {:ok, hook_state}
      {:error, reason} -> {:error, reason}
      {:error, reason, hook_state} -> {:error, reason, hook_state}
      otherwise -> {:error, {:unsupported_hook_result_form, otherwise}}
    end
  end
end
