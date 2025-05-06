defmodule Membrane.MPEGTS.CRC32 do
  @polynomial 0xEDB88320

  def calculate_crc(data) do
    crc = data
    |> String.to_charlist()
    |> Enum.reduce(0xFFFFFFFF, fn byte, crc ->
      crc = Bitwise.bxor(crc, byte)
      :lists.seq(1, 8) |> Enum.reduce(crc, fn _, acc ->
        if Bitwise.band(acc, 1) == 1 do
          Bitwise.bxor(Bitwise.bsr(acc, 1), @polynomial)
        else
          Bitwise.bsr(acc, 1)
        end
      end)
    end)
    |> complement()
    <<crc::32>>
  end

  defp complement(crc) do
    Bitwise.bxor(crc, 0xFFFFFFFF)
  end
end

