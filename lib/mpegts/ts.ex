defmodule Membrane.MPEGTS.TS do
  @moduledoc false

  @opaque t :: %{continuity_counters_map: %{non_neg_integer() => non_neg_integer()}}

  @packet_length 188
  @header_length 4
  @max_payload_length @packet_length - @header_length
  @max_payload_length_with_adaptation @max_payload_length - 2

  @doc """
  Returns new instance of MPEG-TS packets serializer.
  """
  @spec new() :: t()
  def new() do
    %{continuity_counters_map: %{}}
  end

  @doc """
  Registeres new Program ID in the MPEG-TS packets stream.
  """
  @spec add_pid(t(), non_neg_integer()) :: t()
  def add_pid(state, pid) do
    put_in(state, [:continuity_counters_map, pid], 0)
  end

  @doc """
  Serializes Packetized Elementry Stream.
  """
  @spec serialize_pes(binary(), non_neg_integer(), t(), boolean(), boolean()) :: {[binary()], t()}
  def serialize_pes(pes, pid, state, is_keyframe, is_first_part \\ true)

  def serialize_pes(<<>>, _pid, state, _is_keyframe, _is_first_part), do: {[], state}

  def serialize_pes(
        <<first::binary-size(@max_payload_length_with_adaptation), rest::binary>>,
        pid,
        state,
        is_keyframe,
        is_first_part
      ) do
    header = create_header(pid, is_first_part, :payload_and_adaptation, state)
    random_access_indicator = if is_keyframe and is_first_part, do: 1, else: 0
    adaptation_field = create_adaptation_field(0, random_access_indicator)
    ts_packet = header <> adaptation_field <> first
    state = update_in(state, [:continuity_counters_map, pid], &(&1 + 1))
    {rest_of_packets, state} = serialize_pes(rest, pid, state, is_keyframe, false)
    {[ts_packet | rest_of_packets], state}
  end

  def serialize_pes(payload, pid, state, is_keyframe, is_first_part) do
    header = create_header(pid, is_first_part, :payload_and_adaptation, state)
    how_many_stuffing_bytes = @max_payload_length_with_adaptation - byte_size(payload)
    random_access_indicator = if is_keyframe and is_first_part, do: 1, else: 0
    adaptation_field = create_adaptation_field(how_many_stuffing_bytes, random_access_indicator)
    ts_packet = header <> adaptation_field <> payload
    state = update_in(state, [:continuity_counters_map, pid], &(&1 + 1))
    {[ts_packet], state}
  end

  @doc """
  Serializes Program Specific Information, like Program Association Tables or Program Mapping Table.
  """
  @spec serialize_psi(binary(), non_neg_integer(), t()) :: {[binary()], t()}
  def serialize_psi(payload, pid, state) do
    pointer_field = <<0::8>>
    header = create_header(pid, 1, :only_payload, state)
    padding_length = @max_payload_length - byte_size(payload) - byte_size(pointer_field)

    if padding_length < 0 do
      raise """
        PSI longer than #{@max_payload_length - byte_size(pointer_field)} is not supported.
        Provided PSI had: #{byte_size(payload)} bytes.
      """
    end

    padding = String.duplicate(<<0xFF>>, padding_length)
    packet = header <> pointer_field <> payload <> padding
    state = update_in(state, [:continuity_counters_map, pid], &(&1 + 1))
    {[packet], state}
  end

  defp create_header(pid, is_first_part, afc_type, state) do
    tei = 0
    pusi = if is_first_part, do: 1, else: 0
    transport_priority = 0
    tsc = 0

    afc =
      case afc_type do
        :only_payload -> 1
        :payload_and_adaptation -> 3
      end

    cc = Map.fetch!(state.continuity_counters_map, pid)

    <<
      # sync byte
      0x47::8,
      tei::1,
      pusi::1,
      transport_priority::1,
      pid::13,
      tsc::2,
      afc::2,
      cc::4
    >>
  end

  defp create_adaptation_field(how_many_stuffing_bytes, random_access_indicator) do
    adaptation_field_length = how_many_stuffing_bytes + 1
    discontinuity_indicator = 0
    elementary_stream_priority_indicator = 0
    pcr_flag = 0
    opcr_flag = 0
    slicing_point_flag = 0
    transport_private_data_flag = 0
    adaptation_field_extension_flag = 0

    stuffing = String.duplicate(<<255>>, how_many_stuffing_bytes)

    <<adaptation_field_length::size(8), discontinuity_indicator::1, random_access_indicator::1,
      elementary_stream_priority_indicator::1, pcr_flag::1, opcr_flag::1, slicing_point_flag::1,
      transport_private_data_flag::1, adaptation_field_extension_flag::1>> <> stuffing
  end
end
