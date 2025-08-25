Mix.install([
  {:membrane_srt_plugin, path: "./"},
  :membrane_file_plugin,
  :membrane_realtimer_plugin,
  :membrane_h26x_plugin,
  :membrane_aac_plugin
])

defmodule SendingPipeline do
  use Membrane.Pipeline

  @impl true
  def handle_init(_ctx, opts) do
    spec = [
      child(:video_source, %Membrane.File.Source{location: opts[:video_input]})
      |> child(:video_parser, %Membrane.H264.Parser{
        generate_best_effort_timestamps: %{framerate: {25, 1}, add_dts_offset: false}
      })
      |> via_in(:video_input)
      |> child(:muxer, Membrane.MPEGTS.Muxer)
      |> child(:realtimer, Membrane.Realtimer)
      |> child(:srt_sink, %Membrane.SRT.Sink{
        ip: opts[:ip],
        port: opts[:port],
        stream_id: opts[:stream_id]
      }),
      child(:audio_source, %Membrane.File.Source{location: opts[:audio_input]})
      |> child(Membrane.AAC.Parser)
      |> via_in(:audio_input)
      |> get_child(:muxer)
    ]

    {[spec: spec], %{}}
  end

  @impl true
  def handle_element_end_of_stream(:srt_sink, _pad, _ctx, state) do
    {[terminate: :normal], state}
  end

  @impl true
  def handle_element_end_of_stream(_element, _pad, _ctx, state) do
    {[], state}
  end
end

{:ok, sending_supervisor, _pipeline} =
  Membrane.Pipeline.start_link(SendingPipeline,
    ip: "127.0.0.1",
    port: 1234,
    stream_id: "some_stream_id",
    video_input: "test/fixtures/bbb.h264",
    audio_input: "test/fixtures/bbb.aac"
  )

Process.monitor(sending_supervisor)

receive do
  {:DOWN, _ref, _type, ^sending_supervisor, _reason} -> :ok
end
