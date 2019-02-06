defmodule ExSaga.RetryWithExpoentialBackoff do
  @moduledoc """
  """

  use ExSaga.Retry
  require Logger

  @typedoc """
  """
  @type retry_opt ::
          {:retry_limit, pos_integer() | nil}
          | {:base_backoff, pos_integer() | nil}
          | {:min_backoff, non_neg_integer() | nil}
          | {:max_backoff, pos_integer()}
          | {:enable_jitter, boolean()}

  @typedoc """
  """
  @type retry_opts :: [retry_opt]

  @typedoc """
  """
  @type parsed_retry :: {pos_integer | nil, pos_integer | nil, pos_integer, boolean}

  @impl ExSaga.Retry
  def init(_) do
    {:ok, 1}
  end

  @impl ExSaga.Retry
  def handle_retry(count, opts) do
    parsed_opts = parse_opts(opts)

    case retry(count, parsed_opts) do
      {nil, state} -> {:noretry, state}
      {wait, state} -> {:retry, wait, state}
    end
  end

  @doc """
  """
  @spec retry(Retry.retry_state(), parsed_retry) :: {pos_integer | nil, Retry.retry_state()}
  def retry(count, {nil, _base, _max, _jitter?}),
    do: {nil, count + 1}

  def retry(count, {limit, base, max, jitter?})
      when limit > count do
    backoff = get_backoff(count, base, max, jitter?)
    {backoff, count + 1}
  end

  def retry(count, _parsed_opts),
    do: {nil, count + 1}

  @doc false
  @spec parse_opts(retry_opts) :: parsed_retry
  defp parse_opts(opts) do
    limit = Keyword.get(opts, :retry_limit)
    base_backoff = Keyword.get(opts, :base_backoff)
    max_backoff = Keyword.get(opts, :max_backoff, 5_000)
    jitter_enabled? = Keyword.get(opts, :enable_jitter, true)

    {limit, base_backoff, max_backoff, jitter_enabled?}
  end

  @doc false
  @spec get_backoff(pos_integer, pos_integer | nil, pos_integer, boolean) :: non_neg_integer
  defp get_backoff(_count, nil, _max_backoff, _jitter_enabled?), do: 0

  defp get_backoff(count, base_backoff, max_backoff, true)
       when is_integer(base_backoff) and base_backoff >= 1 and is_integer(max_backoff) and max_backoff >= 1,
       do: random(calculate_backoff(count, base_backoff, max_backoff))

  defp get_backoff(count, base_backoff, max_backoff, _jitter_enabled?)
       when is_integer(base_backoff) and base_backoff >= 1 and is_integer(max_backoff) and max_backoff >= 1,
       do: calculate_backoff(count, base_backoff, max_backoff)

  defp get_backoff(_count, base_backoff, max_backoff, _jitter_enabled?) do
    _ =
      Logger.warn(fn ->
        "Ignoring retry backoff options, expected base_backoff and max_backoff to be integer and >= 1, got: " <>
          "base_backoff: #{inspect(base_backoff)}, max_backoff: #{inspect(max_backoff)}"
      end)

    0
  end

  @doc false
  @spec calculate_backoff(pos_integer, pos_integer, pos_integer) :: pos_integer
  defp calculate_backoff(count, base_backoff, max_backoff),
    do: min(max_backoff, trunc(:math.pow(base_backoff * 2, count)))

  @doc false
  @spec random(integer) :: integer
  defp random(n) when is_integer(n) and n > 0, do: :rand.uniform(n) - 1
  defp random(n) when is_integer(n), do: 0
end
