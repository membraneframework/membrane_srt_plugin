defmodule Membrane.MPEGTS.Muxer.PES do
  @moduledoc false

  @doc """
  Serializes Packetized Elementry Stream.

  Packetized elementry stream needs to be either:
  * AAC frame for audio stream
  * H.264 access unit delimited with Access Unit Delimiter NAL unit for video stream

  The provided timestamps need to be represented with 90kHz clock rate.
  """
  @spec serialize(binary(), pos_integer(), non_neg_integer(), non_neg_integer()) :: binary()
  def serialize(payload, pid, pts, dts) do
    # Elementary stream specific header
    pes_scrambling_control = 0
    pes_priority = 0
    # maybe set 1
    data_alignment_indicator = 0
    copyright = 0
    original_or_copy = 0
    pts_dts_flag = if pts != nil and dts != nil, do: 0b11, else: 0b00
    escr_flag = 0
    es_rate_flag = 0
    dsm_trick_mode_flag = 0
    additional_copy_info_flag = 0
    pes_crc_flag = 0
    pes_extension_flag = 0
    encoded_timestamps = encode_timestamps(pts, dts)
    pes_header_data_length = byte_size(encoded_timestamps)

    es_specific_header =
      <<1::1, 0::1, pes_scrambling_control::1, pes_priority::2, data_alignment_indicator::1,
        copyright::1, original_or_copy::1, pts_dts_flag::2, escr_flag::1, es_rate_flag::1,
        dsm_trick_mode_flag::1, additional_copy_info_flag::1, pes_crc_flag::1,
        pes_extension_flag::1, pes_header_data_length>> <> encoded_timestamps

    # Common header
    packet_start_code_prefix = 1
    pes_packet_length = byte_size(es_specific_header) + byte_size(payload)
    stream_id = pid_to_stream_id(pid)

    common_header =
      <<packet_start_code_prefix::24, stream_id::binary-size(1), pes_packet_length::16>>

    common_header <> es_specific_header <> payload
  end

  defp pid_to_stream_id(pid) do
    # according to table 2-22
    <<1::1, 1::1, 1::1, 0::1, pid::4>>
  end

  defp encode_timestamps(pts, dts) when pts == nil or dts == nil do
    <<>>
  end

  defp encode_timestamps(pts, dts) do
    pts_binary = <<pts::33>>
    dts_binary = <<dts::33>>
    <<pts_upper::3, pts_middle::15, pts_lower::15>> = pts_binary
    <<dts_upper::3, dts_middle::15, dts_lower::15>> = dts_binary

    <<0b0011::4, pts_upper::3, 1::1, pts_middle::15, 1::1, pts_lower::15, 1::1, 0b0001::4,
      dts_upper::3, 1::1, dts_middle::15, 1::1, dts_lower::15, 1::1>>
  end
end
