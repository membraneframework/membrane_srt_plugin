defmodule Membrane.MPEGTS.PMT do
  @moduledoc false

  @reserved 0

  @doc """
  Returns serialized Program Map Table with given program number and version, for provided
  list of elementary stream PIDs that form given program.
  """
  @spec serialize(non_neg_integer(), non_neg_integer(), [
          {Membrane.MPEGTS.Muxer.track(), non_neg_integer()}
        ]) :: binary()
  def serialize(program_number, version, pids) do
    # CONTENT
    pcr_pid = 0x1FFF
    program_info_length = 0
    mappings = Enum.map_join(pids, fn {type, pid} -> generate_mapping(type, pid) end)

    # HEADER
    table_id = 0x02
    section_syntax_indicator = 1
    current_next_indicator = 1
    section_number = 0
    last_section_number = 0
    # There are 4 bytes for crc32 and 9 bytes in the
    # header behind this field
    section_length = byte_size(mappings) + 4 + 9

    header =
      <<table_id::8, section_syntax_indicator::1, 0::1, @reserved::2, section_length::12,
        program_number::16, @reserved::2, version::5, current_next_indicator::1,
        section_number::8, last_section_number::8, @reserved::3, pcr_pid::13, @reserved::4,
        program_info_length::12>>

    # CRC
    crc32_value = CRC.calculate(header <> mappings, :crc_32_mpeg_2)
    crc32 = <<crc32_value::32>>

    header <> mappings <> crc32
  end

  defp generate_mapping(mapping_type, pid) do
    stream_type = get_stream_type(mapping_type)
    es_info_length = 0
    <<stream_type::8, @reserved::3, pid::13, @reserved::4, es_info_length::12>>
  end

  # AAC
  defp get_stream_type(:audio), do: 0x0F

  # H264
  defp get_stream_type(:video), do: 0x1B
end
