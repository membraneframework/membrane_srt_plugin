defmodule Membrane.SRT.MuxerTest do
  @moduledoc false
  use ExUnit.Case, async: true
  alias Membrane.H26x.NALuSplitter
  alias Membrane.H264.NALuParser
  alias Membrane.H264.AUSplitter
  alias Membrane.MPEGTS.Muxer

  @tag :sometag
  test "if the MPEG TS muxes H264 stream" do
    input_path = "test/fixtures/bbb.h264"
    reference_path = "test/fixtures/reference.ts"

    video_frames = get_video_frames(input_path, 30)
    {payload1, state} = Muxer.new()
    {payload2, state} = Muxer.register_track(:video, state)

    {packets, _state} =
      Enum.map_reduce(video_frames, state, fn {ts, type, frame}, state ->
        Muxer.put_frame(frame, type, ts, ts, state)
      end)

    payload3 = Enum.join(packets)
    payload = payload1 <> payload2 <> payload3
    assert payload == File.read!(reference_path)
  end

  @tag :sometag
  test "if the MPEG TS muxes H264 and AAC streams" do
    input_audio_path = "test/fixtures/bbb.aac"
    input_video_path = "test/fixtures/bbb.h264"
    reference_path = "test/fixtures/reference_with_audio_and_video.ts"

    audio_frames = get_audio_frames(input_audio_path, 1024, 44_100)
    video_frames = get_video_frames(input_video_path, 25)

    sorted_frames =
      Enum.sort_by(video_frames ++ audio_frames, fn {ts, _type, _packet} -> ts end)

    {payload1, state} = Muxer.new()
    {payload2, state} = Muxer.register_track(:audio, state)
    {payload3, state} = Muxer.register_track(:video, state)

    {packets, _state} =
      Enum.map_reduce(sorted_frames, state, fn {ts, type, frame}, state ->
        Muxer.put_frame(frame, type, ts, ts, state)
      end)

    payload4 = Enum.join(packets)
    payload = payload1 <> payload2 <> payload3 <> payload4
    assert payload == File.read!(reference_path)
  end

  defp get_audio_frames(input_path, samples_per_frame, sampling_frequency) do
    input = File.read!(input_path)
    {aac_frames, _aac_parser} = Muxer.AACParser.parse(input, Muxer.AACParser.new())

    Enum.with_index(aac_frames)
    |> Enum.map(fn {aac_frame, i} ->
      {i * 1000 * samples_per_frame / sampling_frequency, :audio, aac_frame}
    end)
  end

  defp get_video_frames(input_path, fps) do
    input = File.read!(input_path)
    {nalu_payloads, _spliter} = NALuSplitter.split(input, NALuSplitter.new())
    {nalus, _parser} = NALuParser.parse_nalus(nalu_payloads, NALuParser.new())

    {aus, au_splitter} = AUSplitter.split(nalus, AUSplitter.new())
    {[last_au], _au_splitter} = AUSplitter.split([], true, au_splitter)

    aus = aus ++ [last_au]
    annexb_prefix = <<0, 0, 0, 1>>
    aus = Enum.map(aus, fn au -> Enum.map_join(au, &(annexb_prefix <> &1.payload)) end)

    Enum.with_index(aus) |> Enum.map(fn {au, i} -> {i * 1000 / fps, :video, au} end)
  end
end
