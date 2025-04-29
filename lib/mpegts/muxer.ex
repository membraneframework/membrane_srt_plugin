defmodule Membrane.MPEGTS.Muxer do
  alias Membrane.MPEGTS.{PES, TS}

  def new() do
    %{
      pes: PES.new(),
      ts: TS.new()
    }
  end

  def put_frame(frame, id, ts, state) do
    {pes_packets, pes} = PES.serialize(frame, ts, ts, state.pes)

    {ts_packets, ts} =
      Enum.flat_map_reduce(pes_packets, ts, fn {pes_packet, ts} ->
        TS.serialize(pes_packet, ts)
      end)

    {pes_packets, %{state | pes: pes}}
  end
end
