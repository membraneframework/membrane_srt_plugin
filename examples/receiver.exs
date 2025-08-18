Mix.install([
  {:membrane_srt_plugin, path: "./"},
  :membrane_mp4_plugin,
  :membrane_file_plugin,
  :membrane_aac_plugin,
  :membrane_h26x_plugin,
  :membrane_mpeg_ts_plugin
])

defmodule ReceivingPipeline do
  use Membrane.Pipeline

  @impl true
  def handle_init(_ctx, opts) do
    spec =
      child(%Membrane.SRT.Source{ip: opts[:ip], port: opts[:port], stream_id: opts[:stream_id]})
      |> child(:demuxer, Membrane.MPEG.TS.Demuxer)

    {[spec: spec], %{}}
  end

  @impl true
  def handle_child_notification({:mpeg_ts_pmt, pmt}, :demuxer, _context, state) do
    streams_spec =
      Enum.map(pmt.streams, fn {id, %{stream_type: type}} ->
        get_child(:demuxer)
        |> via_out(Pad.ref(:output, {:stream_id, id}))
        |> then(
          &case type do
            :H264 ->
              child(&1, %Membrane.H264.Parser{output_stream_structure: :avc1})

            :AAC ->
              &1 |> child(%Membrane.AAC.Parser{out_encapsulation: :none, output_config: :esds})
          end
        )
        |> get_child(:mp4)
      end)

    spec =
      [
        child(:mp4, Membrane.MP4.Muxer.ISOM)
        |> child(:file_sink, %Membrane.File.Sink{location: "output.mp4"})
      ] ++ streams_spec

    {[spec: spec], state}
  end

  @impl true
  def handle_element_end_of_stream(:file_sink, _pad, _ctx, state) do
    {[terminate: :normal], state}
  end

  @impl true
  def handle_element_end_of_stream(_element, _pad, _ctx, state) do
    {[], state}
  end
end

{:ok, receiving_supervisor, _pipeline} =
  Membrane.Pipeline.start_link(ReceivingPipeline,
    ip: "0.0.0.0",
    port: 1234,
    stream_id: "some_stream_id"
  )

Process.monitor(receiving_supervisor)

receive do
  {:DOWN, _ref, _type, ^receiving_supervisor, _reason} -> :ok
end
