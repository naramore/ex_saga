defmodule ExSaga.AsyncStage.Breaker do
  @moduledoc """
  """

  use GenServer
  alias ExSaga.{Stage, Step}

  @doc """
  """
  @spec breakpoint(GenServer.server(), Stage.full_name(), timeout) :: Step.breakpoint_fun()
  def breakpoint(server, name, timeout \\ 5000) do
    fn _event, _stepable ->
      break?(server, name, timeout)
    end
  end

  @doc """
  """
  @spec start_link(GenServer.options()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @doc """
  """
  @spec remove(GenServer.server(), Stage.full_name(), timeout) :: :ok
  def remove(server, name, timeout \\ 5000) do
    GenServer.call(server, {:remove, name}, timeout)
  end

  @doc """
  """
  @spec reset(GenServer.server(), Stage.full_name(), timeout) :: :ok
  def reset(server, name, timeout \\ 5000) do
    GenServer.call(server, {:reset, name}, timeout)
  end

  @doc """
  """
  @spec break(GenServer.server(), Stage.full_name(), timeout) :: :ok
  def break(server, name, timeout \\ 5000) do
    GenServer.call(server, {:break, name}, timeout)
  end

  @doc """
  """
  @spec break?(GenServer.server(), Stage.full_name(), timeout) :: boolean
  def break?(server, name, timeout \\ 5000) do
    GenServer.call(server, {:break?, name}, timeout)
  end

  @impl GenServer
  def init(_) do
    table = :ets.new(:break_table, [:protected, :set])
    {:ok, table}
  end

  @impl GenServer
  def handle_call({:break?, name}, _from, table) do
    case :ets.lookup(table, name) do
      [{^name, break?} | _] -> {:reply, break?, table}
      _ -> {:reply, false, table}
    end
  end

  def handle_call({:break, name}, _from, table) do
    _ = update(table, name, true)
    {:reply, :ok, table}
  end

  def handle_call({:reset, name}, _from, table) do
    _ = update(table, name, false)
    {:reply, :ok, table}
  end

  def handle_call({:remove, name}, _from, table) do
    _ = :ets.delete(table, name)
    {:reply, :ok, table}
  end

  def handle_call(_request, _from, state) do
    {:reply, {:error, :unhandled}, state}
  end

  @impl GenServer
  def handle_cast(_request, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(_request, state) do
    {:noreply, state}
  end

  @doc false
  @spec update(reference, name :: term, boolean) :: :ok
  defp update(table, name, value) do
    _ =
      unless :ets.update_element(table, name, [{1, value}]) do
        :ets.insert(table, {name, value})
      end

    :ok
  end
end
