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

  test "if the MPEG TS muxes H264 and AAC streams" do
    # frames per second
    fps = 25
    input_video = File.read!("test/fixtures/bbb.h264")
    input_audio = File.read!("test/fixtures/bbb.aac")
    reference_path = "test/fixtures/reference_with_audio_and_video.ts"
    {nalu_payloads, _spliter} = NALuSplitter.split(input_video, NALuSplitter.new())
    {nalus, _parser} = NALuParser.parse_nalus(nalu_payloads, NALuParser.new())

    {aus, au_splitter} = AUSplitter.split(nalus, AUSplitter.new())
    {[last_au], _au_splitter} = AUSplitter.split([], true, au_splitter)

    aus = aus ++ [last_au]
    annexb_prefix = <<0, 0, 0, 1>>
    aus = Enum.map(aus, fn au -> Enum.map_join(au, &(annexb_prefix <> &1.payload)) end)

    video_packets =
      Enum.with_index(aus) |> Enum.map(fn {au, i} -> {i * 1000 / fps, :video, au} end)

    {aac_frames, _aac_parser} = Muxer.AACParser.parse(input_audio, Muxer.AACParser.new())

    audio_packets =
      Enum.with_index(aac_frames)
      |> Enum.map(fn {aac_frame, i} -> {i * 1000 * 1024 / 44_100, :audio, aac_frame} end)

    sorted_packets =
      Enum.sort_by(video_packets ++ audio_packets, fn {ts, _type, _packet} -> ts end)

    {payload1, state} = Muxer.new()
    {payload3, state} = Muxer.register_track(:audio, state)
    {payload2, state} = Muxer.register_track(:video, state)

    {packets, _state} =
      Enum.map_reduce(sorted_packets, state, fn {ts, type, packet}, state ->
        Muxer.put_frame(packet, type, ts, ts, state)
      end)

    payload4 = Enum.join(packets)
    payload = payload1 <> payload2 <> payload3 <> payload4
    assert payload == File.read!(reference_path)
  end
end
