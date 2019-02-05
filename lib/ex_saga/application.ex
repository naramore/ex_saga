defmodule ExSaga.Application do
  @moduledoc false
  use Application

  @impl Application
  def start(_type, _args) do
    ExSaga.Supervisor.start_link()
  end
end

defmodule ExSaga.Supervisor do
  @moduledoc false
  use Supervisor

  @doc false
  @spec start_link(GenServer.options) :: Supervisor.on_start
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, :ok, Keyword.merge([name: __MODULE__], opts))
  end

  @impl Supervisor
  def init(_) do
    children = [
      {Task.Supervisor, name: ExSaga.TaskSupervisor},
    ]
    Supervisor.init(children, strategy: :one_for_one)
  end
end
