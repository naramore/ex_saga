defmodule ExSaga.WaitServer do
  @moduledoc """
  """
  use GenServer

  alias ExSaga.{Retry, Stage}

  @time_unit :millisecond

  @doc """
  """
  @spec start_link(GenServer.opts) :: GenServer.on_start
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @doc """
  """
  @spec wait(GenServer.server, Stage.full_name, Retry.wait, DateTime.t) :: :ok
  def wait(server, id, wait, datetime \\ DateTime.utc_now()) do
    GenServer.cast(server, {:wait, id, wait, datetime})
  end

  @doc """
  """
  @spec maybe_wait(GenServer.server, Stage.full_name, timeout) :: :ok | {:error, reason :: term}
  def maybe_wait(server, id, timeout \\ 5000) do
    GenServer.call(server, {:maybe_wait, id}, timeout)
  end

  @impl GenServer
  def init(_) do
    {:ok, %{}}
  end

  @impl GenServer
  def handle_call({:maybe_wait, id}, _from, state) do
    case get_wait(state, id) do
      nil -> {:reply, {:error, {:id_not_found, id}}, state}
      0 -> {:reply, :ok, Map.delete(state, id)}
      wait_ms ->
        _ = :timer.sleep(wait_ms)
        {:reply, :ok, Map.delete(state, id)}
    end
  end
  def handle_call(_request, _from, state) do
    {:reply, {:error, :unhandled}, state}
  end

  @impl GenServer
  def handle_cast({:wait, id, wait, datetime}, state) do
    {:noreply, Map.put(state, id, {wait, datetime})}
  end
  def handle_cast(_request, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(_request, state) do
    {:noreply, state}
  end

  @doc false
  @spec get_wait(map, Stage.full_name, DateTime.t) :: non_neg_integer | nil
  defp get_wait(state, id, now \\ DateTime.utc_now()) do
    case Map.get(state, id) do
      {{time, unit}, %DateTime{} = then} ->
        wait_ms = System.convert_time_unit(time, unit, @time_unit)
        diff = DateTime.diff(now, then, @time_unit)
        diff_to_wait(wait_ms - diff)
      _ -> nil
    end
  end

  @doc false
  @spec diff_to_wait(integer) :: non_neg_integer
  defp diff_to_wait(diff) when diff <= 0, do: 0
  defp diff_to_wait(diff), do: diff
end
