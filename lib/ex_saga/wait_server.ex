defmodule ExSaga.WaitServer do
  @moduledoc """
  """
  use GenServer

  alias ExSaga.{Retry, Stage}

  @time_unit :millisecond

  @doc """
  """
  @spec start_link(GenServer.options()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @doc """
  """
  @spec wait(GenServer.server(), Stage.full_name(), Retry.wait(), DateTime.t()) :: :ok
  def wait(server, id, wait, datetime \\ DateTime.utc_now()) do
    GenServer.cast(server, {:wait, id, wait, datetime})
  end

  @doc """
  """
  @spec maybe_wait(GenServer.server(), Stage.full_name(), timeout) :: :ok | {:error, reason :: term}
  def maybe_wait(server, id, timeout \\ 5000) do
    GenServer.call(server, {:maybe_wait, id}, timeout)
  end

  @impl GenServer
  def init(_) do
    table = :ets.new(:wait_table, [:protected, :set])
    {:ok, table}
  end

  @impl GenServer
  def handle_call({:maybe_wait, id}, _from, table) do
    case get_wait(table, id) do
      nil ->
        {:reply, {:error, {:id_not_found, id}}, table}

      0 ->
        _ = :ets.delete(table, id)
        {:reply, :ok, table}

      wait_ms ->
        _ = :timer.sleep(wait_ms)
        _ = :ets.delete(table, id)
        {:reply, :ok, table}
    end
  end

  def handle_call(_request, _from, state) do
    {:reply, {:error, :unhandled}, state}
  end

  @impl GenServer
  def handle_cast({:wait, id, wait, datetime}, table) do
    _ = :ets.insert(table, {id, wait, datetime})
    {:noreply, table}
  end

  def handle_cast(_request, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(_request, state) do
    {:noreply, state}
  end

  @doc false
  @spec get_wait(atom | :ets.tid, Stage.full_name(), DateTime.t()) :: non_neg_integer | nil
  defp get_wait(table, id, now \\ DateTime.utc_now()) do
    case :ets.lookup(table, id) do
      [{^id, {time, unit}, %DateTime{} = then} | _] ->
        wait_ms = System.convert_time_unit(time, unit, @time_unit)
        diff = DateTime.diff(now, then, @time_unit)
        diff_to_wait(wait_ms - diff)

      _ ->
        nil
    end
  end

  @doc false
  @spec diff_to_wait(integer) :: non_neg_integer
  defp diff_to_wait(diff) when diff <= 0, do: 0
  defp diff_to_wait(diff), do: diff
end
