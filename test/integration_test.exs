defmodule Membrane.SRT.IntegrationTest do
  @moduledoc false
  use ExUnit.Case, async: true
  alias Membrane.Testing.Pipeline
  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  @ip "127.0.0.1"
  @port 12_000
  @stream_id "some_stream_id"
  @tolerance_factor 0.1

  defmodule TimestampsGenerator do
    use Membrane.Filter

    def_input_pad :input, accepted_format: _any
    def_output_pad :output, accepted_format: _any

    @impl true
    def handle_init(_ctx, _opts) do
      {[], %{i: 0}}
    end

    @impl true
    def handle_buffer(:input, buffer, _ctx, state) do
      buffer = %Membrane.Buffer{buffer | pts: Membrane.Time.milliseconds(state.i)}
      {[buffer: {:output, buffer}], %{state | i: state.i + 1}}
    end
  end

  @tag :tmp_dir
  test "if the sink sends SRT stream that can be received by the source", ctx do
    receiver = Pipeline.start_link_supervised!()

    output = Path.join(ctx.tmp_dir, "out.ts")
    input = "test/fixtures/bbb.ts"

    receiver_spec =
      child(:source, %Membrane.SRT.Source{port: @port, stream_id: @stream_id})
      |> child(:sink, %Membrane.File.Sink{location: output})

    Pipeline.execute_actions(receiver, spec: receiver_spec)
    assert_child_playing(receiver, :source)
    sender = Pipeline.start_link_supervised!()

    sender_spec =
      child(:source, %Membrane.File.Source{location: input})
      |> child(:timestamps_generator, TimestampsGenerator)
      |> child(:realtimer, Membrane.Realtimer)
      |> child(:sink, %Membrane.SRT.Sink{ip: @ip, port: @port, stream_id: @stream_id})

    Pipeline.execute_actions(sender, spec: sender_spec)

    assert_end_of_stream(receiver, :sink, :input, 5000)
    Membrane.Pipeline.terminate(sender)
    Membrane.Pipeline.terminate(receiver)

    assert abs(File.lstat!(input).size - File.lstat!(output).size) <
             @tolerance_factor * File.lstat!(input).size

    assert File.read!(input) == File.read!(output)
  end
end
