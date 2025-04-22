defmodule Membrane.SRT.IntegrationTest do
  @moduledoc false
  use ExUnit.Case, async: true
  alias Membrane.Testing.Pipeline
  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  @ip "127.0.0.1"
  @port 12_000
  @stream_id "some_stream_id"

  @tag :tmp_dir
  test "if the sink sends SRT stream that can be received by the source", ctx do
    receiver = Pipeline.start_supervised!()

    output = Path.join(ctx.tmp_dir, "out.ts")
    input = "test/fixtures/bbb.ts"
    receiver_spec =
      child(:source, %Membrane.SRT.Source{port: @port})
      |> child(:sink, %Membrane.File.Sink{location: output})

    Pipeline.execute_actions(receiver, spec: receiver_spec)
    assert_child_playing(receiver, :source)
    sender = Pipeline.start_supervised!()

    sender_spec =
      child(:source, %Membrane.File.Source{location: input, chunk_size: 100})
      |> child(:sink, %Membrane.SRT.Sink{ip: @ip, port: @port, stream_id: @stream_id})

    Pipeline.execute_actions(sender, spec: sender_spec)

    assert_end_of_stream(receiver, :sink)
    Membrane.Pipeline.terminate(sender)
    Membrane.Pipeline.terminate(receiver)

    assert File.read!(input) == File.read!(output)
  end
end
