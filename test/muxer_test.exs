defmodule Membrane.SRT.MuxerTest do
  @moduledoc false
  use ExUnit.Case, async: true
  alias Membrane.H26x.NALuSplitter
  alias Membrane.H264.NALuParser
  alias Membrane.H264.AUSplitter
  alias Membrane.MPEGTS.Muxer

  test "if the MPEG TS muxes H264 stream" do
    # frames per second
    fps = 30
    input = File.read!("test/fixtures/bbb.h264")
    reference_path = "test/fixtures/reference.ts"
    {nalu_payloads, _spliter} = NALuSplitter.split(input, NALuSplitter.new())
    {nalus, _parser} = NALuParser.parse_nalus(nalu_payloads, NALuParser.new())

    {aus, au_splitter} = AUSplitter.split(nalus, AUSplitter.new())
    {[last_au], _au_splitter} = AUSplitter.split([], true, au_splitter)

    aus = aus ++ [last_au]
    annexb_prefix = <<0, 0, 0, 1>>
    aus = Enum.map(aus, fn au -> Enum.map_join(au, &(annexb_prefix <> &1.payload)) end)

    {payload1, state} = Muxer.new()
    {payload2, state} = Muxer.register_track(:video, state)

    {packets, _state} =
      Enum.with_index(aus)
      |> Enum.map_reduce(state, fn {au_payload, i}, state ->
        Muxer.put_frame(au_payload, :video, i * 1000 / fps, i * 1000 / fps, state)
      end)

    payload3 = Enum.join(packets)
    payload = payload1 <> payload2 <> payload3
    assert payload == File.read!(reference_path)
  end
end
