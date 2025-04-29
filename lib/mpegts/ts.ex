defmodule Membrane.MPEGTS.TS do
  @moduledoc false

  def serialize(pes, pid, state, is_first_part \\ true)

  def serialize(<<first::binary-size(184), rest::binary>>, pid, state, is_first_part) do
    tei = 0
    pusi = if is_first_part, do: 1, else: 0
    transport_priority = 0
    tsc = 0
    # just payload
    afc = 1
    cc = state.cc_map[pid]

    header = <<
      # sync byte
      0x47::8,
      tei::1,
      pusi::1,
      transport_priority::1,
      pid::13,
      tsc::2,
      afc::2,
      cc::22
    >>

    ts_packet = header <> first
    state = update_in(state, [:cc_map, pid], &(&1 + 1))
    {rest_of_packets, state} = serialize(rest, pid, state, false)
    {[ts_packet] ++ rest_of_packets, state}
  end

  def serialize(<<>>, _pid, state, is_first_part), do: {[], state}

  def serialize(payload, pid, state, is_first_part) do
    tei = 0
    pusi = if is_first_part, do: 1, else: 0
    transport_priority = 0
    tsc = 0
    # adaptation field nad payload
    afc = 3
    cc = state.cc_map[pid]

    header = <<
      # sync byte
      0x47::8,
      tei::1,
      pusi::1,
      transport_priority::1,
      pid::13,
      tsc::2,
      afc::2,
      cc::22
    >>

    case payload do
      <<first::binary-size(182), rest>> ->
        adaptation_field = create_adaptation_field(0)
        ts_packet = header <> adaptation_field <> first
        state = update_in(state, [:cc_map, pid], &(&1 + 1))
        {rest_of_packets, state} = serialize(rest, pid, state, false)
        {[ts_packet] ++ rest_of_packets, state}

      _other ->
        how_many_stuffing_bytes = 182 - byte_size(payload)
        adaptation_field = create_adaptation_field(how_many_stuffing_bytes)
        ts_packet = header <> adaptation_field <> payload
        state = update_in(state, [:cc_map, pid], &(&1 + 1))
        {[ts_packet], state}
    end
  end

  def create_adaptation_field(how_many_stuffing_bytes) do
    adoption_field_length = how_many_stuffing_bytes + 1
    discontinuity_indicator = 0
    random_access_indicator = 0
    elementary_stream_priority_indicator = 0
    pcr_flag = 0
    opcr_flag = 0
    splicing_point_flag = 0
    transport_private_data_flag = 0
    adaptation_field_extension_flag = 0

    stuffing = String.duplicate(<<255>>, how_many_stuffing_bytes)

    <<adoption_field_length::size(8), discontinuity_indicator::1, random_access_indicator::1,
      elementary_stream_priority_indicator::1, pcr_flag::1, opcr_flag::1, slicing_point_flag::1,
      transport_private_data_flag::1, adaptation_field_extension_flag::1, stuffing>>
  end
end
