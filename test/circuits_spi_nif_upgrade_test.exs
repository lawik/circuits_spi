# SPDX-FileCopyrightText: 2026 Lars Wikman
#
# SPDX-License-Identifier: Apache-2.0

defmodule CircuitsSPINifUpgradeTest do
  use ExUnit.Case

  import ExUnit.CaptureLog

  alias Circuits.SPI.Nif

  # Hot code upgrades load the NIF from a second copy of the app while the
  # current one is still loaded.
  @moduletag :tmp_dir

  setup do
    app_dir = Application.app_dir(:circuits_spi)

    on_exit(fn ->
      load_from(app_dir)
      :code.purge(Nif)
    end)

    %{app_dir: app_dir}
  end

  test "open buses keep working after an upgrade", %{app_dir: app_dir, tmp_dir: tmp_dir} do
    {:ok, spi} = Nif.open("my_spidev", 0, 8, 123_456, 10, false)

    assert {:module, Nif} == load_from(copy_app(app_dir, tmp_dir))
    :code.purge(Nif)

    assert {:ok, <<1, 2, 3>>} == Nif.transfer(spi, <<1, 2, 3>>)
    assert {:ok, %{speed_hz: 123_456}} = Nif.config(spi)
    Nif.close(spi)
  end

  test "upgrade is refused when the ABI differs", %{app_dir: app_dir, tmp_dir: tmp_dir} do
    {:ok, spi} = Nif.open("my_spidev", 0, 8, 123_456, 10, false)

    new_app_dir = copy_app(app_dir, tmp_dir)
    nif_path = Path.join(new_app_dir, "priv/spi_nif.so")
    nif = File.read!(nif_path) |> String.replace("spi_nif_abi_", "spi_nif_xyz_")
    File.write!(nif_path, nif)

    capture_log(fn -> assert {:error, :on_load_failure} == load_from(new_app_dir) end)

    assert {:ok, <<1, 2, 3>>} == Nif.transfer(spi, <<1, 2, 3>>)
    Nif.close(spi)
  end

  defp copy_app(app_dir, tmp_dir) do
    new_app_dir = Path.join(tmp_dir, "circuits_spi")
    File.cp_r!(app_dir, new_app_dir)
    new_app_dir
  end

  defp load_from(app_dir) do
    true = :code.replace_path(:circuits_spi, String.to_charlist(Path.join(app_dir, "ebin")))
    :code.purge(Nif)
    :code.load_file(Nif)
  end
end
