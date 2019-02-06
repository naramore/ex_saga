defmodule ExSaga.DryRun do
  @moduledoc """
  """

  import ExSaga.Utils, only: [get_stacktrace: 0]
  alias ExSaga.{Event, Stage, Stepable}

  @typedoc """
  """
  @type dry_run_results :: %{
          optional(Stage.name()) => dry_run_results | term,
          optional(Event.name()) => dry_run_results | term
        }

  @typedoc """
  """
  @type f :: function | mfa | {module, atom}

  @typedoc """
  """
  @type execute_error_reason ::
          {:raise, Exception.t(), Exception.stacktrace()}
          | {:throw, value :: term}
          | {:exit, reason :: term}
          | reason :: term

  @typedoc """
  """
  @type execution_opt ::
          {:timeout, timeout}
          | {:dry_run?, boolean}
          | {:dry_run_result, dry_run_results | term}
          | {:dry_run_result_default, term}
          | {:full_name, Stage.full_name()}
          | {:event_name, Event.name()}
          | {:hook, :hook | :filter}

  @typedoc """
  """
  @type execution_opts :: [execution_opt]

  @doc """
  """
  @spec from_stepable(Event.t(), Stepable.opts(), default :: term) :: execution_opts
  def from_stepable(event, opts, default \\ nil) do
    {options, _} = Keyword.split(opts, [:timeout, :dry_run?, :dry_run_result])
    %Event{stage_name: full_name, name: event_name} = event

    Keyword.merge(options,
      full_name: full_name,
      event_name: event_name,
      dry_run_result_default: default
    )
  end

  @doc """
  """
  @spec execute(f(), args :: [term], execution_opts) :: {:error, execute_error_reason} | result :: term
  def maybe_execute(fun, args, opts \\ []) do
    if Keyword.get(opts, :dry_run?, false) do
      find_dry_run_result(opts)
    else
      timeout = Keyword.get(opts, :timeout, :infinity)
      execute(fun, args, timeout)
    end
  end

  @doc """
  """
  @spec find_dry_run_result(execution_opts) :: term
  def find_dry_run_result(opts) do
    Keyword.get(opts, :dry_run_result)
    |> find_dry_run_result_impl(opts)
  end

  @doc """
  """
  @spec find_dry_run_result_impl([Event.t()] | map | term, execution_opts) :: term
  def find_dry_run_result_impl(events, opts) when is_list(events) do
    with name when is_list(name) <- Keyword.get(opts, :full_name),
         event when is_list(event) <- Keyword.get(opts, :event_name) do
      case Keyword.get(opts, :hook) do
        nil ->
          Enum.find(events, &match?(%Event{name: ^event, stage_name: ^name}, &1))
          |> case do
            %Event{name: [_, :error_handler], context: {_, result}} -> result
            %Event{} = event -> event.context
            _ -> nil
          end

        {:hook, hook_name} ->
          Enum.find(events, &match?(%Event{name: [:completed, :hook, ^hook_name], stage_name: ^name}, &1))
          |> case do
            %Event{context: {_, result}} -> result
            _ -> nil
          end

        {:filter, hook_name} ->
          Enum.find(events, &match?(%Event{name: [_, :hook, ^hook_name], stage_name: ^name}, &1))
          |> case do
            %Event{name: [:completed | _]} -> true
            %Event{name: [:skipped | _]} -> true
            _ -> nil
          end
      end
    else
      _ -> Keyword.get(opts, :dry_run_result)
    end
  end

  def find_dry_run_result_impl(result, opts) when is_map(result) do
    with name when is_list(name) <- Keyword.get(opts, :full_name),
         event when is_list(event) <- Keyword.get(opts, :event_name) do
      case Keyword.get(opts, :hook) do
        nil -> get_in(result, name ++ [event])
        {:hook, hook_name} -> get_in(result, name ++ [[:hook, hook_name]])
        {:filter, hook_name} -> get_in(result, name ++ [[:hook_filter, hook_name]])
        _ -> result
      end
    else
      _ -> Keyword.get(opts, :dry_run_result)
    end
  end

  def find_dry_run_result_impl(result, _opts), do: result

  @doc """
  """
  @spec execute(f, [term], timeout) ::
          {:error, execute_error_reason}
          | result :: term
  def execute(fun, args, timeout \\ :infinity) do
    try do
      Task.Supervisor.async_nolink(
        ExSaga.TaskSupervisor,
        fn -> execute!(fun, args) end
      )
      |> Task.yield(timeout)
      |> case do
        nil -> {:error, {:timeout, timeout}}
        {:exit, reason} -> {:error, {:exit, reason}}
        {:ok, result} -> result
      end
    rescue
      error -> {:error, {:raise, error, get_stacktrace()}}
    catch
      value -> {:error, {:throw, value}}
    end
  end

  @doc """
  """
  @spec execute!(function | mfa | {module, atom}, [term]) :: term | no_return
  def execute!(fun, args) when is_function(fun), do: apply(fun, args)
  def execute!({mod, fun, _}, args), do: apply(mod, fun, args)
  def execute!({mod, fun}, args), do: apply(mod, fun, args)
end
