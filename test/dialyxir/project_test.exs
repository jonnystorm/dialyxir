defmodule Dialyxir.ProjectTest do
  alias Dialyxir.Project

  use ExUnit.Case
  import ExUnit.CaptureIO, only: [capture_io: 1, capture_io: 2]

  defp in_project(app, f) when is_atom(app) do
    Mix.Project.in_project(app, "test/fixtures/#{Atom.to_string(app)}", fn _ -> f.() end)
  end

  defp in_project(apps, f) when is_list(apps) do
    path = Enum.map_join(apps, "/", &Atom.to_string/1)
    app = List.last(apps)
    Mix.Project.in_project(app, "test/fixtures/#{path}", fn _ -> f.() end)
  end

  test "Default Project PLT File in _build dir" do
    in_project(:default_apps, fn ->
      assert Regex.match?(~r/_build\/.*plt/, Project.plt_file())
    end)
  end

  test "Can specify a different local PLT path" do
    in_project(:alt_local_path, fn ->
      assert Regex.match?(~r/dialyzer\/.*plt/, Project.plt_file())
    end)
  end

  test "Can specify a different PLT file name" do
    in_project(:local_plt, fn ->
      assert Regex.match?(~r/local\.plt/, Project.plt_file())
    end)
  end

  test "Deprecation warning on use of bare :plt_file" do
    in_project(:local_plt, fn ->
      out = capture_io(&Project.check_config/0)
      assert Regex.match?(~r/.*plt_file.*deprecated.*/, out)
    end)
  end

  test "Can specify a different PLT file name along with :no_warn" do
    in_project(:local_plt_no_warn, fn ->
      assert Regex.match?(~r/local\.plt/, Project.plt_file())
    end)
  end

  test "No deprecation warning on use of plt_file: {:no_warn, myfile}" do
    in_project(:local_plt_no_warn, fn ->
      out = capture_io(&Project.check_config/0)
      refute Regex.match?(~r/.*plt_path.*deprecated.*/, out)
    end)
  end

  test "App list for default contains direct and
        indirect :application dependencies" do
    in_project(:default_apps, fn ->
      apps = Project.cons_apps()
      # direct
      assert Enum.member?(apps, :logger)
      # direct
      assert Enum.member?(apps, :public_key)
      # indirect
      assert Enum.member?(apps, :asn1)
    end)
  end

  test "App list for umbrella contains child dependencies
  indirect :application dependencies" do
    in_project(:umbrella, fn ->
      apps = Project.cons_apps()
      # direct
      assert Enum.member?(apps, :logger)
      # direct, child1
      assert Enum.member?(apps, :public_key)
      # indirect
      assert Enum.member?(apps, :asn1)
      # direct, child2
      assert Enum.member?(apps, :mix)
    end)
  end

  @tag :skip
  test "App list for umbrella contains all child dependencies
  when run from child directory" do
    in_project([:umbrella, :apps, :second_one], fn ->
      apps = Project.cons_apps()
      # direct
      assert Enum.member?(apps, :logger)
      # direct, child1
      assert Enum.member?(apps, :public_key)
      # indirect
      assert Enum.member?(apps, :asn1)
      # direct, child2
      assert Enum.member?(apps, :mix)
    end)
  end

  test "App list for :apps_direct contains only direct dependencies" do
    in_project(:direct_apps, fn ->
      apps = Project.cons_apps()
      # direct
      assert Enum.member?(apps, :logger)
      # direct
      assert Enum.member?(apps, :public_key)
      # indirect
      refute Enum.member?(apps, :asn1)
    end)
  end

  test "App list for :plt_ignore_apps does not contain the ignored dependency" do
    in_project(:ignore_apps, fn ->
      apps = Project.cons_apps()

      refute Enum.member?(apps, :logger)
    end)
  end

  test "Core PLT files located in mix home by default" do
    in_project(:default_apps, fn ->
      assert String.contains?(Project.erlang_plt(), Mix.Utils.mix_home())
    end)
  end

  test "Core PLT file paths can be specified with :plt_core_path" do
    in_project(:alt_core_path, fn ->
      assert String.contains?(Project.erlang_plt(), "_build")
    end)
  end

  test "By default core elixir and erlang plts are in mix.home" do
    in_project(:default_apps, fn ->
      assert String.contains?(Project.erlang_plt(), Mix.Utils.mix_home())
    end)
  end

  test "By default a dialyzer ignore file is nil" do
    in_project(:default_apps, fn ->
      assert Project.dialyzer_ignore_warnings() == nil
    end)
  end

  test "Filtered dialyzer warnings" do
    in_project(:default_apps, fn ->
      output_list =
        ~S"""
        project.ex:9 This should still be here
        project.ex:9: Guard test is_atom(_@5::#{'__exception__':='true', '__struct__':=_, _=>_}) can never succeed
        project.ex:9: Guard test is_binary(_@4::#{'__exception__':='true', '__struct__':=_, _=>_}) can never succeed
        """
        |> String.trim_trailing("\n")
        |> String.split("\n")

      pattern = ~S"""
      Guard test is_atom(_@5::#{'__exception__':='true', '__struct__':=_, _=>_}) can never succeed

      Guard test is_binary(_@4::#{'__exception__':='true', '__struct__':=_, _=>_}) can never succeed
      """

      lines = Project.filter_legacy_warnings(output_list, pattern)
      assert lines == ["project.ex:9 This should still be here"]
    end)
  end

  test "Project with non-existent dependency" do
    in_project(:nonexistent_deps, fn ->
      out = capture_io(:stderr, &Project.cons_apps/0)
      assert Regex.match?(~r/Error loading nonexistent, dependency list may be incomplete/, out)
    end)
  end

  test "igonored apps are removed in umbrella projects" do
    in_project(:umbrella_ignore_apps, fn ->
      refute Enum.member?(Project.cons_apps(), :logger)
    end)
  end

  test "Deprecation warning on use of plt_add_deps: true" do
    in_project(:plt_add_deps_deprecations, fn ->
      out = capture_io(&Project.cons_apps/0)
      assert Regex.match?(~r/.*deprecated.*plt_add_deps.*/, out)
    end)
  end

  test "list_unused_filters? works as intended" do
    assert Project.list_unused_filters?(list_unused_filters: true)
    refute Project.list_unused_filters?(list_unused_filters: nil)

    # Override in mix.exs
    in_project(:ignore, fn ->
      assert Project.list_unused_filters?(list_unused_filters: nil)
    end)
  end

  test "no_umbrella? works as expected" do
    in_project(:umbrella, fn ->
      refute Project.no_umbrella?()
    end)

    in_project(:no_umbrella, fn ->
      assert Project.no_umbrella?()
    end)
  end
end
