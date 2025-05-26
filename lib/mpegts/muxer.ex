defmodule Membrane.MPEGTS.Muxer do
  @moduledoc """
  A Membrane Filter that provides muxing capabilities for the MPEG TS container.
  """

  use Membrane.Filter
  alias Membrane.MPEGTS.Muxer.Engine
  alias Membrane.TimestampQueue, as: TQ

  def_input_pad :audio_input,
    accepted_format: %Membrane.AAC{encapsulation: :ADTS},
    availability: :on_request

  def_input_pad :video_input,
    accepted_format: %Membrane.H264{alignment: :au},
    availability: :on_request

  def_output_pad :output, accepted_format: Membrane.RemoteStream

  @impl true
  def handle_init(_ctx, _opts) do
    {payload, muxer} = Engine.new()
    {[], %{tq: TQ.new(), muxer: muxer, buffered_payload: payload}}
  end

  @impl true
  def handle_pad_added(pad, %{playback: :stopped}, state) do
    state = update_in(state.tq, &TQ.register_pad(&1, pad, wait_on_buffers?: true))
    {binary, muxer} = Engine.register_track(get_track_type(pad), state.muxer)

    {[], %{state | muxer: muxer, buffered_payload: state.buffered_payload <> binary}}
  end

  @impl true
  def handle_pad_added(_pad, _ctx, _state) do
    raise "All the pads need to be connected before the muxer enters playing playback."
  end

  @impl true
  def handle_playing(_ctx, state) do
    {[
       stream_format: {:output, %Membrane.RemoteStream{}},
       buffer: {:output, %Membrane.Buffer{payload: state.buffered_payload, pts: 0, dts: 0}}
     ], %{state | buffered_payload: <<>>}}
  end

  @impl true
  def handle_stream_format(_pad, _stream_format, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_buffer(pad, buffer, _ctx, state) do
    buffer = %{buffer | pts: buffer.pts || buffer.dts, dts: buffer.dts || buffer.pts}
    {auto_demand_actions, tq} = TQ.push_buffer(state.tq, pad, buffer)
    state = %{state | tq: tq}
    {actions, state} = pop_items(state)
    {auto_demand_actions ++ actions, state}
  end

  @impl true
  def handle_end_of_stream(pad, ctx, state) do
    {actions, state} = update_in(state.tq, &TQ.push_end_of_stream(&1, pad)) |> pop_items()
    {actions ++ maybe_eos(ctx), state}
  end

  defp maybe_eos(ctx) do
    eos_on_all_inputs? =
      Enum.filter(ctx.pads, fn {pad_name, _pad} -> pad_name != :output end)
      |> Enum.all?(fn {_pad_name, pad} -> pad.end_of_stream? end)

    if eos_on_all_inputs?, do: [end_of_stream: :output], else: []
  end

  defp pop_items(state) do
    {auto_demand_actions, items, tq} = TQ.pop_available_items(state.tq)
    {actions, muxer} = process_popped_items(items, state.muxer)
    {auto_demand_actions ++ actions, %{state | tq: tq, muxer: muxer}}
  end

  defp process_popped_items(items, muxer) do
    Enum.flat_map_reduce(items, muxer, fn
      {_pad, :end_of_stream}, muxer ->
        {[], muxer}

      {pad, {:buffer, buffer}}, muxer ->
        pts_ms = Membrane.Time.as_milliseconds(buffer.pts, :round)
        dts_ms = Membrane.Time.as_milliseconds(buffer.dts, :round)

        {payload, muxer} =
          Engine.put_frame(buffer.payload, get_track_type(pad), pts_ms, dts_ms, muxer)

        {[
           buffer: {:output, %Membrane.Buffer{payload: payload, pts: buffer.pts, dts: buffer.dts}}
         ], muxer}

      {pad, {action, stream_element}}, muxer ->
        {[{action, {pad, stream_element}}], muxer}
    end)
  end

  defp get_track_type(Pad.ref(:audio_input, _ref)) do
    :audio
  end

  defp get_track_type(Pad.ref(:video_input, _ref)) do
    :video
  end
end
