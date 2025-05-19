defmodule Membrane.SRT.IntegrationTest do
  @moduledoc false
  use ExUnit.Case, async: true
  alias Membrane.Testing.Pipeline
  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  @ip "127.0.0.1"
  @port 12_000
  @stream_id "some_stream_id"

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

    assert File.read!(input) == File.read!(output)
  end

  defmodule DemuxingPipeline do
    use Membrane.Pipeline

    @impl true
    def handle_init(_ctx,
          output_audio: output_audio,
          output_video: output_video,
          port: port,
          stream_id: stream_id
        ) do
      spec = [
        child(:source, %Membrane.SRT.Source{port: port, stream_id: stream_id})
        |> child(:demuxer, Membrane.MPEG.TS.Demuxer),
        child(:connector_audio, Membrane.Connector)
        |> child(:sink_audio, %Membrane.File.Sink{location: output_audio}),
        child(:connector_video, Membrane.Connector)
        |> child(:sink_video, %Membrane.File.Sink{location: output_video})
      ]

      {[spec: spec], %{}}
    end

    @impl true
    def handle_child_notification({:mpeg_ts_pmt, pmt}, :demuxer, _ctx, state) do
      audio_id = get_pad_id(pmt, :AAC)
      video_id = get_pad_id(pmt, :H264)

      spec = [
        get_child(:demuxer) |> via_out(Pad.ref(:output, audio_id)) |> get_child(:connector_audio),
        get_child(:demuxer) |> via_out(Pad.ref(:output, video_id)) |> get_child(:connector_video)
      ]

      {[spec: spec], state}
    end

    defp get_pad_id(pmt, stream_type) do
      {id, _track} =
        Enum.find(pmt.streams, fn {_id, track} -> track.stream_type == stream_type end)

      {:stream_id, id}
    end
  end

  @tag :tmp_dir
  test "if the MPEGTS MuxerFilter muxes AAC and H264 streams into MPEGTS stream that can be sent via
    SRT received by the SRT Source",
       ctx do
    output_audio = Path.join(ctx.tmp_dir, "out.aac")
    output_video = Path.join(ctx.tmp_dir, "out.h264")
    input_audio = "test/fixtures/bbb.aac"
    input_video = "test/fixtures/bbb.h264"

    receiver =
      Pipeline.start_link_supervised!(
        module: DemuxingPipeline,
        custom_args: [
          output_audio: output_audio,
          output_video: output_video,
          port: @port,
          stream_id: @stream_id
        ]
      )

    assert_child_playing(receiver, :source)

    sender = Pipeline.start_link_supervised!()

    sender_spec = [
      child(:audio_source, %Membrane.File.Source{location: input_audio})
      |> child(:audio_parser, Membrane.AAC.Parser)
      |> via_in(:audio_input)
      |> child(:muxer, Membrane.MPEGTS.MuxerFilter)
      |> child(:realtimer, Membrane.Realtimer)
      |> child(:sink, %Membrane.SRT.Sink{ip: @ip, port: @port, stream_id: @stream_id}),
      child(:video_source, %Membrane.File.Source{location: input_video})
      |> child(:video_parser, %Membrane.H264.Parser{
        generate_best_effort_timestamps: %{framerate: {25, 1}, add_dts_offset: false}
      })
      |> via_in(:video_input)
      |> get_child(:muxer)
    ]

    Pipeline.execute_actions(sender, spec: sender_spec)

    assert_end_of_stream(receiver, :sink_audio, :input, 35_000)
    assert_end_of_stream(receiver, :sink_video, :input)
    Membrane.Pipeline.terminate(sender)
    Membrane.Pipeline.terminate(receiver)

    assert File.read!(input_audio) == File.read!(output_audio)
    assert File.read!(input_video) == File.read!(output_video)
  end
end
