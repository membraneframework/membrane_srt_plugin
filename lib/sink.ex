defmodule Membrane.SRT.Sink do
  use Membrane.Sink

  require Membrane.Logger

  def_input_pad(:input, accepted_format: Membrane.RemoteStream)

  def_options address: [], port: [], stream_id: []

  @impl true
  def handle_init(_ctx, opts) do
    {[], %{address: opts.address, port: opts.port, stream_id: opts.stream_id}}
  end

  @impl true
  def handle_setup(_ctx, state) do
    {:ok, client} = ExLibSRT.Client.start(state.address, state.port, state.stream_id)
    state = Map.put(state, :client, client)
    {[setup: :incomplete], state}
  end

  @impl true
  def handle_info(:srt_client_connected, _ctx, state) do
    {[setup: :complete], state}
  end

  @impl true
  def handle_info(msg, _ctx, state) do
    Membrane.Logger.warning("Unknown message received: #{inspect(msg)}")
    {[], state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    :ok = ExLibSRT.Client.send_data(buffer.payload, state.client)
    {[], state}
  end
end
