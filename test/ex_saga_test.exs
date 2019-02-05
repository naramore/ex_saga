defmodule ExSagaTest do
  @moduledoc false
  use ExUnit.Case, async: true
  doctest ExSaga
  doctest ExSaga.DryRun
  doctest ExSaga.Event
  doctest ExSaga.Utils
end
