defmodule Membrane.MPEGTS.PSI do
  @reserved 0

  def serialize(psi_type, content) do
    # we assume that we have only a single program
    table_id = get_table_id(psi_type)
    section_syntax_indicator = 1
    reserved = 0
    section_length = byte_size(content)+5 # there are 5 bytes in the header behind this field
    transport_stream_id = 123 # TODO, but probably we are free to choose any value
    version_number = 0
    current_next_indicator = 1
    # we only have one section
    section_number = 0
    last_section_number = 0

    header = <<table_id::8, section_syntax_indicator::1, 0::1, @reserved::2, section_length::12,
transport_stream_id::16, reserved::2, version_number::5, current_next_indicator::1,
    section_number::8, last_section_number::8>>

    header <> content
  end

  defp get_table_id(:pat), do: 0
  defp get_table_id(:pmt), do: 2 # TODO
end
