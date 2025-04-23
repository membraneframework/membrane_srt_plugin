defmodule SendingPipeline do
  use Membrane.Pipeline

  @impl true
  def handle_init(_ctx, opts) do
    spec =
      child(%Membrane.File.Source{location: opts[:input], chunk_size: 100})
      |> child(:srt_sink, %Membrane.SRT.Sink{
        address: opts[:address],
        port: opts[:port],
        stream_id: opts[:stream_id]
      })

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
    address: "127.0.0.1",
    port: 1234,
    stream_id: "some_stream_id",
    input: "test/fixtures/bbb.ts"
  )

Process.monitor(sending_supervisor)

receive do
  {:DOWN, _ref, _type, ^sending_supervisor, _reason} -> :ok
end
